// Particle-based density simulation
// Based on reference implementation from References/Inkling

#ifndef PARTICLE_SIMULATION_INCLUDED
#define PARTICLE_SIMULATION_INCLUDED

#include "SimulationCommon.hlsl"

// NOTE: iparticle.cs is included in main Fluids.compute, not here, to avoid double inclusion

// Particle buffers (declared in main compute shader)
#ifndef PARTICLE_BUFFERS_DEFINED
RWStructuredBuffer<iparticle> _ParticlesRead;
RWStructuredBuffer<iparticle> _ParticlesWrite;
#endif

// Parameters for particle injection (must be set from C# before dispatching)
// Note: These are declared in main Fluids.compute via ForceParams, we just reference them here

// Bilinear interpolation for particle values
iparticle BilinearSampleParticles(ifloat2 pos, iuint2 bufferSize)
{
    int2 zero = int2(0, 0);
    int2 sizeBounds = int2(bufferSize.x - 1, bufferSize.y - 1);
    int2 topRight = clamp(ceil(pos), zero, sizeBounds);
    int2 bottomLeft = clamp(floor(pos), zero, sizeBounds);

    ifloat2 delta = pos - (ifloat2)bottomLeft;

    // Sample four neighboring particles
    iparticle lt = _ParticlesRead[topRight.y * bufferSize.x + bottomLeft.x];
    iparticle rt = _ParticlesRead[topRight.y * bufferSize.x + topRight.x];
    iparticle lb = _ParticlesRead[bottomLeft.y * bufferSize.x + bottomLeft.x];
    iparticle rb = _ParticlesRead[bottomLeft.y * bufferSize.x + topRight.x];

    // Bilinear interpolation
    iparticle result;
    result.fire = lerp(lerp(lb.fire, rb.fire, delta.x), lerp(lt.fire, rt.fire, delta.x), delta.y);
    result.water = lerp(lerp(lb.water, rb.water, delta.x), lerp(lt.water, rt.water, delta.x), delta.y);
    result.plantSeeded = lerp(lerp(lb.plantSeeded, rb.plantSeeded, delta.x), lerp(lt.plantSeeded, rt.plantSeeded, delta.x), delta.y);
    result.plantGrown = lerp(lerp(lb.plantGrown, rb.plantGrown, delta.x), lerp(lt.plantGrown, rt.plantGrown, delta.x), delta.y);
    result.steam = lerp(lerp(lb.steam, rb.steam, delta.x), lerp(lt.steam, rt.steam, delta.x), delta.y);
    result.glitter = lerp(lerp(lb.glitter, rb.glitter, delta.x), lerp(lt.glitter, rt.glitter, delta.x), delta.y);
    result.blackBody = lerp(lerp(lb.blackBody, rb.blackBody, delta.x), lerp(lt.blackBody, rt.blackBody, delta.x), delta.y);
    result.electricitySeeded = lerp(lerp(lb.electricitySeeded, rb.electricitySeeded, delta.x), lerp(lt.electricitySeeded, rt.electricitySeeded, delta.x), delta.y);
    result.electricityGrown = lerp(lerp(lb.electricityGrown, rb.electricityGrown, delta.x), lerp(lt.electricityGrown, rt.electricityGrown, delta.x), delta.y);
    result.ice = lerp(lerp(lb.ice, rb.ice, delta.x), lerp(lt.ice, rt.ice, delta.x), delta.y);

    // Color overrides use max instead of lerp (preserve user colors)
    result.red = max(max(lb.red, rb.red), max(lt.red, rt.red));
    result.green = max(max(lb.green, rb.green), max(lt.green, rt.green));
    result.blue = max(max(lb.blue, rb.blue), max(lt.blue, rt.blue));
    result.alpha = max(max(lb.alpha, rb.alpha), max(lt.alpha, rt.alpha));

    return result;
}

// Sample velocity with bilinear interpolation (particles may be higher resolution than velocity)
ifloat2 GetVelocityAtParticle(ifloat2 particlePos, iuint2 particleSize, iuint2 velocitySize)
{
    // Map particle position to velocity grid
    ifloat2 velocityPos = (particlePos / (ifloat2)particleSize) * (ifloat2)velocitySize;

    int2 zero = int2(0, 0);
    int2 sizeBounds = int2(velocitySize.x - 1, velocitySize.y - 1);
    int2 topRight = clamp(ceil(velocityPos), zero, sizeBounds);
    int2 bottomLeft = clamp(floor(velocityPos), zero, sizeBounds);

    ifloat2 delta = velocityPos - (ifloat2)bottomLeft;

    // Sample velocity texture (defined in main shader)
    ifloat4 lt = _VelocityRead[int2(bottomLeft.x, topRight.y)];
    ifloat4 rt = _VelocityRead[int2(topRight.x, topRight.y)];
    ifloat4 lb = _VelocityRead[int2(bottomLeft.x, bottomLeft.y)];
    ifloat4 rb = _VelocityRead[int2(topRight.x, bottomLeft.y)];

    // Bilinear interpolation of velocity
    ifloat2 h1 = lerp(lt.xy, rt.xy, delta.x);
    ifloat2 h2 = lerp(lb.xy, rb.xy, delta.x);
    ifloat2 velocity = lerp(h2, h1, delta.y);

    // Scale velocity to particle grid
    return velocity * ((ifloat2)particleSize / (ifloat2)velocitySize);
}

// Advect particles using semi-Lagrangian method
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void AdvectParticles(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    iuint2 particleSize = iuint2(_SimParams.simulationSize);

    if (id.x >= particleSize.x || id.y >= particleSize.y) return;

    iuint particleIndex = id.y * particleSize.x + id.x;

    // Get velocity at this particle position
    ifloat2 velocity = GetVelocityAtParticle((ifloat2)id.xy, particleSize, iuint2(_SimParams.simulationSize));

    // Back-trace position
    ifloat2 prevPos = (ifloat2)id.xy - velocity * _SimParams.deltaTime;

    // Absorbing boundary: if back-traced position is outside the domain,
    // the particle has no valid source and is killed.  This prevents
    // density pileup at edges caused by clamped bilinear sampling.
    if (prevPos.x < 0 || prevPos.y < 0 ||
        prevPos.x > (ifloat)(particleSize.x - 1) ||
        prevPos.y > (ifloat)(particleSize.y - 1))
    {
        iparticle empty;
        empty.fire = (ifloat)0; empty.water = (ifloat)0;
        empty.plantSeeded = (ifloat)0; empty.plantGrown = (ifloat)0;
        empty.steam = (ifloat)0; empty.glitter = (ifloat)0;
        empty.blackBody = (ifloat)0;
        empty.electricitySeeded = (ifloat)0; empty.electricityGrown = (ifloat)0;
        empty.ice = (ifloat)0;
        empty.red = (ifloat)0; empty.green = (ifloat)0;
        empty.blue = (ifloat)0; empty.alpha = (ifloat)0;
        _ParticlesWrite[particleIndex] = empty;
        return;
    }

    // Sample particle value at back-traced position
    iparticle advected = BilinearSampleParticles(prevPos, particleSize);

    _ParticlesWrite[particleIndex] = advected;
}

// Dissipate particle concentrations over time
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void DissipateParticles(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    iuint2 particleSize = iuint2(_SimParams.simulationSize);

    if (id.x >= particleSize.x || id.y >= particleSize.y) return;

    iuint particleIndex = id.y * particleSize.x + id.x;
    iparticle p = _ParticlesRead[particleIndex];

    // Apply dissipation to all ink concentrations
    p.fire *= _SimParams.dissipation;
    p.water *= _SimParams.dissipation;
    p.plantSeeded *= _SimParams.dissipation;
    p.plantGrown *= _SimParams.dissipation;
    p.steam *= _SimParams.dissipation;
    p.glitter *= _SimParams.dissipation;
    p.blackBody *= _SimParams.dissipation;
    p.electricitySeeded *= _SimParams.dissipation;
    p.electricityGrown *= _SimParams.dissipation;
    p.ice *= _SimParams.dissipation;

    // Do NOT dissipate color overrides - these are user-set and should persist

    _ParticlesWrite[particleIndex] = p;
}

// Add particles with Gaussian falloff around injection point
// Uses ForceParams.position, .radius, and .densityAmount from main shader
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void AddParticlesGaussian(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    iuint2 particleSize = iuint2(_SimParams.simulationSize);

    if (id.x >= particleSize.x || id.y >= particleSize.y) return;

    iuint particleIndex = id.y * particleSize.x + id.x;
    iparticle p = _ParticlesRead[particleIndex];

    // Calculate distance from injection point
    ifloat2 pos = (ifloat2)id.xy;
    ifloat dist = length(pos - _ForceParams.position);

    if (dist < _ForceParams.radius)
    {
        ifloat falloff = GaussianFalloff(dist, _ForceParams.radius);
        ifloat amount = _ForceParams.densityAmount * falloff;

        // Route injection to channels via densityColor weights
        p.fire  = saturate(p.fire  + amount * _ForceParams.densityColor.r);
        p.water = saturate(p.water + amount * _ForceParams.densityColor.g);
        p.ice   = saturate(p.ice   + amount * _ForceParams.densityColor.b);
    }

    _ParticlesWrite[particleIndex] = p;
}

#endif // PARTICLE_SIMULATION_INCLUDED
