// Force and density injection for user interaction

#ifndef FORCE_INJECTION_INCLUDED
#define FORCE_INJECTION_INCLUDED

#include "SimulationCommon.hlsl"

// Textures are declared in main Fluids.compute

// Add external force to velocity field
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void AddForce(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    ifloat2 pos = ifloat2(id.xy);
    ifloat dist = length(pos - _ForceParams.position);

    ifloat4 velocity = _VelocityRead[id.xy];

    if (dist < _ForceParams.radius)
    {
        // Use Gaussian falloff for smoother forces
        ifloat falloff = GaussianFalloff(dist, _ForceParams.radius);
        ifloat2 force = _ForceParams.direction * _ForceParams.strength * falloff;

        velocity.xy += force * _SimParams.deltaTime;
    }

    _VelocityWrite[id.xy] = velocity;
}

// Add density/dye to simulation
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void AddDensity(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    ifloat2 pos = ifloat2(id.xy);
    ifloat dist = length(pos - _ForceParams.position);

    ifloat4 density = _DensityRead[id.xy];

    if (dist < _ForceParams.radius)
    {
        ifloat falloff = GaussianFalloff(dist, _ForceParams.radius);

        // Add colored density with temperature gradient
        ifloat4 newDensity = ifloat4(
            _ForceParams.densityAmount * falloff,           // Red (temperature/heat)
            _ForceParams.densityAmount * falloff * 0.5,     // Green
            _ForceParams.densityAmount * falloff * 0.1,     // Blue
            1.0
        );

        density = saturate(density + newDensity);
    }

    _DensityWrite[id.xy] = density;
}

// Add radial impulse force
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void AddRadialForce(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    ifloat2 pos = ifloat2(id.xy);
    ifloat2 toPoint = pos - _ForceParams.position;
    ifloat dist = length(toPoint);

    ifloat4 velocity = _VelocityRead[id.xy];

    if (dist < _ForceParams.radius && dist > 0.001)
    {
        ifloat falloff = GaussianFalloff(dist, _ForceParams.radius);

        // Radial force (outward from center)
        ifloat2 radialDir = normalize(toPoint);
        ifloat2 force = radialDir * _ForceParams.strength * falloff;

        velocity.xy += force * _SimParams.deltaTime;
    }

    _VelocityWrite[id.xy] = velocity;
}

// Add vortex/swirl force
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void AddVortexForce(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    ifloat2 pos = ifloat2(id.xy);
    ifloat2 toPoint = pos - _ForceParams.position;
    ifloat dist = length(toPoint);

    ifloat4 velocity = _VelocityRead[id.xy];

    if (dist < _ForceParams.radius && dist > 0.001)
    {
        ifloat falloff = QuadraticFalloff(dist, _ForceParams.radius);

        // Tangential force (perpendicular to radial)
        ifloat2 radialDir = normalize(toPoint);
        ifloat2 tangent = ifloat2(-radialDir.y, radialDir.x);
        ifloat2 force = tangent * _ForceParams.strength * falloff;

        velocity.xy += force * _SimParams.deltaTime;
    }

    _VelocityWrite[id.xy] = velocity;
}

// Clear all fields
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void Clear(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    _VelocityWrite[id.xy] = ifloat4(0, 0, 0, 0);
    _DensityWrite[id.xy] = ifloat4(0, 0, 0, 0);
    _PressureWrite[id.xy] = ifloat4(0, 0, 0, 0);
    _DivergenceWrite[id.xy] = 0.0;
    _VorticityMag[id.xy] = 0.0;
}

// Add colored smoke with multiple channels
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void AddColoredSmoke(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    ifloat2 pos = ifloat2(id.xy);
    ifloat dist = length(pos - _ForceParams.position);

    ifloat4 density = _DensityRead[id.xy];

    if (dist < _ForceParams.radius)
    {
        ifloat falloff = GaussianFalloff(dist, _ForceParams.radius);

        // Temperature-based color gradient
        ifloat temp = falloff * _ForceParams.densityAmount;

        // Fire-like gradient: black -> red -> orange -> yellow -> white
        ifloat3 color;
        if (temp < 0.25)
        {
            // Black to red
            color = lerp(ifloat3(0, 0, 0), ifloat3(1, 0, 0), temp * 4.0);
        }
        else if (temp < 0.5)
        {
            // Red to orange
            color = lerp(ifloat3(1, 0, 0), ifloat3(1, 0.5, 0), (temp - 0.25) * 4.0);
        }
        else if (temp < 0.75)
        {
            // Orange to yellow
            color = lerp(ifloat3(1, 0.5, 0), ifloat3(1, 1, 0), (temp - 0.5) * 4.0);
        }
        else
        {
            // Yellow to white
            color = lerp(ifloat3(1, 1, 0), ifloat3(1, 1, 1), (temp - 0.75) * 4.0);
        }

        density.rgb = saturate(density.rgb + color * falloff);
        density.a = 1.0;
    }

    _DensityWrite[id.xy] = density;
}

#endif // FORCE_INJECTION_INCLUDED