// Vorticity calculation and confinement for turbulent flow

#ifndef VORTICITY_INCLUDED
#define VORTICITY_INCLUDED

#include "SimulationCommon.hlsl"

// Textures are declared in main Fluids.compute

// Calculate vorticity (curl of velocity field)
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void Vorticity(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    // Get velocity samples
    NeighborSamples vel = GetNeighbors(_VelocityRead, id.xy, _SimParams.simulationSize);

    // Calculate curl: ω = ∂v/∂x - ∂u/∂y
    // In 2D, vorticity is a scalar (perpendicular to plane)
    // Store SIGNED value — sign encodes rotation direction (CW vs CCW),
    // which VorticityConfinement needs for correct force direction.
    ifloat vorticity = ((vel.right.y - vel.left.y) - (vel.up.x - vel.down.x)) * 0.5;

    _VorticityMag[id.xy] = vorticity;
}

// Helper: Calculate ink-weighted vorticity strength at a position
// Uses per-ink vorticity values and local ink concentrations
ifloat GetInkWeightedVorticityStrength(iuint2 pos, iuint2 simSize)
{
#ifdef PARTICLE_BUFFERS_DEFINED
    // Sample particle at this position
    iuint particleIndex = pos.y * simSize.x + pos.x;
    iparticle p = _ParticlesRead[particleIndex];

    // Calculate total ink and weighted sum
    ifloat totalInk = p.fire + p.water + p.plantSeeded + p.plantGrown +
                      p.steam + p.glitter + p.blackBody +
                      p.electricitySeeded + p.electricityGrown + p.ice;

    if (totalInk < 0.0001)
    {
        // No ink present, use base vorticity strength
        return _SimParams.vorticityStrength;
    }

    // Weighted average of per-ink vorticity contributions
    ifloat weightedVort = p.fire * _VorticityFire +
                          p.water * _VorticityWater +
                          p.plantSeeded * _VorticityPlantSeeded +
                          p.plantGrown * _VorticityPlantGrown +
                          p.steam * _VorticitySteam +
                          p.glitter * _VorticityGlitter +
                          p.blackBody * _VorticityBlackBody +
                          p.electricitySeeded * _VorticityElectricitySeeded +
                          p.electricityGrown * _VorticityElectricityGrown +
                          p.ice * _VorticityIce;

    // Normalize by total ink and scale by base vorticity strength
    return _SimParams.vorticityStrength * (weightedVort / totalInk);
#else
    // Fallback: no particle buffer, use global vorticity
    return _SimParams.vorticityStrength;
#endif
}

// Vorticity confinement - adds swirling motion back into the simulation
// Uses per-ink vorticity weights when particle buffer is available
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void VorticityConfinement(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    // Get vorticity magnitude samples
    iuint2 left = iuint2(max(id.x - 1, 0), id.y);
    iuint2 right = iuint2(min(id.x + 1, _SimParams.simulationSize.x - 1), id.y);
    iuint2 down = iuint2(id.x, max(id.y - 1, 0));
    iuint2 up = iuint2(id.x, min(id.y + 1, _SimParams.simulationSize.y - 1));

    // Read signed vorticity; use abs() for gradient of MAGNITUDE,
    // but keep signed center value for correct CW/CCW force direction.
    ifloat wL = abs(_VorticityMag[left]);
    ifloat wR = abs(_VorticityMag[right]);
    ifloat wD = abs(_VorticityMag[down]);
    ifloat wU = abs(_VorticityMag[up]);
    ifloat wC = _VorticityMag[id.xy]; // signed — encodes rotation direction

    // Gradient of vorticity magnitude (points toward stronger vortices)
    ifloat2 gradVort = ifloat2(wR - wL, wU - wD) * 0.5;

    // Normalize gradient
    ifloat gradMag = length(gradVort);
    if (gradMag > 0.0001)
    {
        gradVort = normalize(gradVort);

        // Get ink-weighted vorticity strength for this position
        ifloat localVortStrength = GetInkWeightedVorticityStrength(id.xy, iuint2(_SimParams.simulationSize));

        // Scale by resolution to compensate for texel-space finite differences:
        // curl and gradient both shrink with finer grids, so the confinement
        // force naturally weakens at higher resolution. Normalize to 256 baseline.
        ifloat resScale = _SimParams.simulationSize.x / 256.0;

        // Calculate confinement force
        // Force is perpendicular to gradient, scaled by signed vorticity (CW/CCW)
        ifloat2 vortForce = localVortStrength * wC * ifloat2(gradVort.y, -gradVort.x) * resScale;

        // dt-normalized impulse: scale by (real frame dt / fixed timestep) so the swirl injected
        // per real second is frame-rate independent. Byte-identical at the reference rate
        // (_FrameDeltaTime == _DeltaTime under deterministic/external step control); substepping
        // keeps the per-step impulse bounded at low framerates.
        ifloat2 velocity = _VelocityRead[id.xy].xy;
        velocity += vortForce * (_FrameDeltaTime / max(_DeltaTime, (ifloat)1e-6));

        // Clamp to prevent velocity explosion
        velocity = ClampVelocity(velocity);

        _VelocityWrite[id.xy] = ifloat4(velocity, 0, 1);
    }
    else
    {
        // No confinement needed
        _VelocityWrite[id.xy] = _VelocityRead[id.xy];
    }
}

// Enhanced vorticity with helicity preservation (for 3D-like effects in 2D)
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void VorticityHelicity(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    NeighborSamples vel = GetNeighbors(_VelocityRead, id.xy, _SimParams.simulationSize);

    // Standard vorticity
    ifloat vorticity = ((vel.right.y - vel.left.y) - (vel.up.x - vel.down.x)) * 0.5;

    // Calculate strain rate for additional turbulence
    ifloat2 dudx = (vel.right.xy - vel.left.xy) * 0.5;
    ifloat2 dudy = (vel.up.xy - vel.down.xy) * 0.5;

    // Strain rate magnitude
    ifloat strain = length(dudx) + length(dudy);

    // Combine vorticity with strain for enhanced turbulence
    // Preserve sign for VorticityConfinement force direction
    ifloat enhancedVort = vorticity * (1.0 + strain * 0.1);

    _VorticityMag[id.xy] = enhancedVort;
}

// Buoyancy force for temperature-driven flows (optional)
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void Buoyancy(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    // Read temperature/density as a proxy for buoyancy
    ifloat4 density = _DensityRead[id.xy];
    ifloat temperature = density.r; // Use red channel as temperature

    // Buoyancy force (upward for hot, downward for cold)
    ifloat ambientTemp = 0.0; // Ambient temperature
    ifloat buoyancy = (temperature - ambientTemp) * _SimParams.vorticityStrength; // Reuse vorticity strength

    // dt-normalized impulse (see VorticityConfinement). Byte-identical at the reference rate.
    ifloat2 velocity = _VelocityRead[id.xy].xy;
    velocity.y += buoyancy * (_FrameDeltaTime / max(_DeltaTime, (ifloat)1e-6));

    // Clamp to prevent velocity explosion
    velocity = ClampVelocity(velocity);

    _VelocityWrite[id.xy] = ifloat4(velocity, 0, 1);
}

#endif // VORTICITY_INCLUDED