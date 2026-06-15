// Semi-Lagrangian advection for stable fluid simulation

#ifndef ADVECTION_INCLUDED
#define ADVECTION_INCLUDED

#include "SimulationCommon.hlsl"

// Textures are declared in main Fluids.compute

// Advection kernel - traces particles back in time
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void Advection(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    ifloat2 uv = PixelToUV(id.xy, _SimParams.simulationSize);

    // Sample velocity at current position
    ifloat2 velocity = _VelocityRead[id.xy].xy;

    // Trace particle back in time (semi-Lagrangian)
    // Velocity is already in pixel-space units, convert to UV-space for advection
    ifloat2 velocityUV = velocity / _SimParams.simulationSize;
    // dt-normalized: trace back by real frame dt so flow speed is frame-rate independent
    // (was the fixed _SimParams.deltaTime). Equal to deltaTime under deterministic/external step control.
    ifloat2 prevUV = uv - (velocityUV * _FrameDeltaTime);

    // Clamp to boundaries
    prevUV = saturate(prevUV);

    // Sample quantity at previous position using bilinear interpolation
    ifloat4 quantity = SampleBilinear(_QuantityRead, prevUV, _SimParams.simulationSize);

    // Apply dissipation (dt-normalized: _SimParams.dissipation is per-second retention)
    _QuantityWrite[id.xy] = quantity * pow(max(_SimParams.dissipation, 0.0), _FrameDeltaTime);
}

// Specialized velocity advection with boundary conditions
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void AdvectVelocity(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    ifloat2 uv = PixelToUV(id.xy, _SimParams.simulationSize);

    // Sample velocity at current position
    ifloat2 velocity = _VelocityRead[id.xy].xy;

    // Trace particle back in time
    // Velocity is already in pixel-space units, convert to UV-space for advection
    ifloat2 velocityUV = velocity / _SimParams.simulationSize;
    // dt-normalized: trace back by real frame dt (was fixed _SimParams.deltaTime).
    ifloat2 prevUV = uv - (velocityUV * _FrameDeltaTime);

    // Clamp to boundaries
    prevUV = saturate(prevUV);

    // Sample velocity at previous position
    ifloat4 prevVelocity = SampleBilinear(_VelocityRead, prevUV, _SimParams.simulationSize);

    // Apply boundary conditions
    prevVelocity.xy = ApplyVelocityBoundary(prevVelocity.xy, id.xy, _SimParams.simulationSize, BOUNDARY_NO_SLIP);

    // Write with velocity-specific dissipation (dt-normalized: per-second retention)
    _VelocityWrite[id.xy] = ifloat4(prevVelocity.xy * pow(max(_SimParams.dissipation, 0.0), _FrameDeltaTime), 0, 1);
}

// MacCormack advection for higher accuracy (optional, more expensive)
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void AdvectionMacCormack(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    ifloat2 uv = PixelToUV(id.xy, _SimParams.simulationSize);
    ifloat2 velocity = _VelocityRead[id.xy].xy;

    // Convert velocity to UV-space
    ifloat2 velocityUV = velocity / _SimParams.simulationSize;

    // Forward step (dt-normalized: real frame dt, was fixed _SimParams.deltaTime)
    ifloat2 posBack = uv - (velocityUV * _FrameDeltaTime);
    posBack = saturate(posBack);
    ifloat4 phi_n_hat = SampleBilinear(_QuantityRead, posBack, _SimParams.simulationSize);

    // Backward step
    ifloat2 velBack = SampleBilinear(_VelocityRead, posBack, _SimParams.simulationSize).xy;
    ifloat2 velBackUV = velBack / _SimParams.simulationSize;
    ifloat2 posForward = posBack + (velBackUV * _FrameDeltaTime);
    posForward = saturate(posForward);
    ifloat4 phi_n_1 = SampleBilinear(_QuantityRead, posForward, _SimParams.simulationSize);

    // Error correction
    ifloat4 phi_n = _QuantityRead[id.xy];
    ifloat4 corrected = phi_n_hat + 0.5 * (phi_n - phi_n_1);

    // Apply dissipation (dt-normalized: per-second retention)
    _QuantityWrite[id.xy] = corrected * pow(max(_SimParams.dissipation, 0.0), _FrameDeltaTime);
}

#endif // ADVECTION_INCLUDED