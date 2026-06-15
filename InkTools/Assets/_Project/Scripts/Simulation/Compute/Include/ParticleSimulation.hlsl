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

    // Current particle value (for partial advection)
    iparticle p = _ParticlesRead[particleIndex];

    // Sample particle value at back-traced position
    iparticle advected = BilinearSampleParticles(prevPos, particleSize);

    // Optional per-ink advection weights (0 = static, 1 = fully advected)
#define ADVE(ct, wt) lerp(p.ct, advected.ct, wt)
    iparticle outp;
    outp.fire = ADVE(fire, _AdvectionFire);
    outp.water = ADVE(water, _AdvectionWater);
    outp.plantSeeded = ADVE(plantSeeded, _AdvectionPlantSeeded);
    outp.plantGrown = ADVE(plantGrown, _AdvectionPlantGrown);
    outp.steam = ADVE(steam, _AdvectionSteam);
    outp.glitter = ADVE(glitter, _AdvectionGlitter);
    outp.blackBody = ADVE(blackBody, _AdvectionBlackBody);
    outp.electricitySeeded = ADVE(electricitySeeded, _AdvectionElectricitySeeded);
    outp.electricityGrown = ADVE(electricityGrown, _AdvectionElectricityGrown);
    outp.ice = ADVE(ice, _AdvectionIce);

    // Preserve color overrides from advected sample
    outp.red = advected.red;
    outp.green = advected.green;
    outp.blue = advected.blue;
    outp.alpha = advected.alpha;

    _ParticlesWrite[particleIndex] = outp;
#undef ADVE
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

    // Apply per-ink dissipation rates. Uniforms are per-SECOND retention; pow(retention, dt)
    // makes the decay frame-rate independent (product over a real second == the per-second value).
    // max(.,0) keeps the base non-negative (retention is always 0..1) and silences the
    // "pow(f,e) for negative f" compiler warning.
    float dt = _FrameDeltaTime;
    p.fire *= pow(max(_DissipationFire, 0.0), dt);
    p.water *= pow(max(_DissipationWater, 0.0), dt);
    p.plantSeeded *= pow(max(_DissipationPlantSeeded, 0.0), dt);
    p.plantGrown *= pow(max(_DissipationPlantGrown, 0.0), dt);
    p.steam *= pow(max(_DissipationSteam, 0.0), dt);
    p.glitter *= pow(max(_DissipationGlitter, 0.0), dt);
    p.blackBody *= pow(max(_DissipationBlackBody, 0.0), dt);
    p.electricitySeeded *= pow(max(_DissipationElectricitySeeded, 0.0), dt);
    p.electricityGrown *= pow(max(_DissipationElectricityGrown, 0.0), dt);
    p.ice *= pow(max(_DissipationIce, 0.0), dt);

    // Do NOT dissipate color overrides - these are user-set and should persist

    _ParticlesWrite[particleIndex] = p;
}

// Diffuse particle concentrations (per-ink viscosity/spreading)
// Higher viscosity values cause more spreading to neighbors
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void DiffuseParticles(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    iuint2 particleSize = iuint2(_SimParams.simulationSize);

    if (id.x >= particleSize.x || id.y >= particleSize.y) return;

    iuint particleIndex = id.y * particleSize.x + id.x;
    iparticle p = _ParticlesRead[particleIndex];

    // Sample cardinal neighbors
    iuint2 left = iuint2(max((int)id.x - 1, 0), id.y);
    iuint2 right = iuint2(min(id.x + 1, particleSize.x - 1), id.y);
    iuint2 down = iuint2(id.x, max((int)id.y - 1, 0));
    iuint2 up = iuint2(id.x, min(id.y + 1, particleSize.y - 1));

    iparticle pL = _ParticlesRead[left.y * particleSize.x + left.x];
    iparticle pR = _ParticlesRead[right.y * particleSize.x + right.x];
    iparticle pD = _ParticlesRead[down.y * particleSize.x + down.x];
    iparticle pU = _ParticlesRead[up.y * particleSize.x + up.x];

    // Average of cardinal neighbors
    #define NEIGHBOR_AVG(field) ((pL.field + pR.field + pD.field + pU.field) * 0.25)

    // Apply per-ink viscosity (blend with neighbor average)
    // viscosity=0 means no spreading, viscosity=1 means full blur
    p.fire = lerp(p.fire, NEIGHBOR_AVG(fire), _ViscosityFire);
    p.water = lerp(p.water, NEIGHBOR_AVG(water), _ViscosityWater);
    p.plantSeeded = lerp(p.plantSeeded, NEIGHBOR_AVG(plantSeeded), _ViscosityPlantSeeded);
    p.plantGrown = lerp(p.plantGrown, NEIGHBOR_AVG(plantGrown), _ViscosityPlantGrown);
    p.steam = lerp(p.steam, NEIGHBOR_AVG(steam), _ViscositySteam);
    p.glitter = lerp(p.glitter, NEIGHBOR_AVG(glitter), _ViscosityGlitter);
    p.blackBody = lerp(p.blackBody, NEIGHBOR_AVG(blackBody), _ViscosityBlackBody);
    p.electricitySeeded = lerp(p.electricitySeeded, NEIGHBOR_AVG(electricitySeeded), _ViscosityElectricitySeeded);
    p.electricityGrown = lerp(p.electricityGrown, NEIGHBOR_AVG(electricityGrown), _ViscosityElectricityGrown);
    p.ice = lerp(p.ice, NEIGHBOR_AVG(ice), _ViscosityIce);

    #undef NEIGHBOR_AVG

    // Do NOT diffuse color overrides - these are user-set and should persist

    _ParticlesWrite[particleIndex] = p;
}

// External parameter for ink type routing (set from C#, matches InkTypeId enum)
// Declared in Fluids.compute: int _InkTypeIndex;

// Helper: Add value to ink field by index (0-9, matches InkTypeId enum)
void AddInkByIndex(inout iparticle p, int idx, ifloat amount)
{
    switch (idx)
    {
        case 0: p.fire = saturate(p.fire + amount); break;
        case 1: p.water = saturate(p.water + amount); break;
        case 2: p.plantSeeded = saturate(p.plantSeeded + amount); break;
        case 3: p.plantGrown = saturate(p.plantGrown + amount); break;
        case 4: p.steam = saturate(p.steam + amount); break;
        case 5: p.glitter = saturate(p.glitter + amount); break;
        case 6: p.blackBody = saturate(p.blackBody + amount); break;
        case 7: p.electricitySeeded = saturate(p.electricitySeeded + amount); break;
        case 8: p.electricityGrown = saturate(p.electricityGrown + amount); break;
        case 9: p.ice = saturate(p.ice + amount); break;
    }
}

// Add particles with Gaussian falloff around injection point
// Uses ForceParams.position, .radius, and .densityAmount from main shader
// Uses _InkTypeIndex to route injection to the correct iparticle field
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

        // Route injection to the specified ink channel
        AddInkByIndex(p, _InkTypeIndex, amount);
    }

    _ParticlesWrite[particleIndex] = p;
}

#endif // PARTICLE_SIMULATION_INCLUDED
