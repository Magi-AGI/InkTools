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
    ifloat vorticity = ((vel.right.y - vel.left.y) - (vel.up.x - vel.down.x)) * 0.5;

    // Store magnitude for vorticity confinement
    _VorticityMag[id.xy] = abs(vorticity);
}

// Vorticity confinement - adds swirling motion back into the simulation
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

    ifloat wL = _VorticityMag[left];
    ifloat wR = _VorticityMag[right];
    ifloat wD = _VorticityMag[down];
    ifloat wU = _VorticityMag[up];
    ifloat wC = _VorticityMag[id.xy];

    // Gradient of vorticity magnitude (points to higher vorticity)
    ifloat2 gradVort = ifloat2(wR - wL, wU - wD) * 0.5;

    // Normalize gradient
    ifloat gradMag = length(gradVort);
    if (gradMag > 0.0001)
    {
        gradVort = normalize(gradVort);

        // Calculate confinement force
        // Force is perpendicular to gradient, scaled by vorticity magnitude
        ifloat2 vortForce = _SimParams.vorticityStrength * wC * ifloat2(gradVort.y, -gradVort.x);

        // Add force to velocity
        ifloat2 velocity = _VelocityRead[id.xy].xy;
        velocity += vortForce * _SimParams.deltaTime;

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
    ifloat enhancedVort = abs(vorticity) * (1.0 + strain * 0.1);

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

    // Apply buoyancy force (vertical only)
    ifloat2 velocity = _VelocityRead[id.xy].xy;
    velocity.y += buoyancy * _SimParams.deltaTime;

    _VelocityWrite[id.xy] = ifloat4(velocity, 0, 1);
}

#endif // VORTICITY_INCLUDED