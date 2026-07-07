// Heat: scalar environment/temperature field transport.
//
// Heat is modeled as its OWN scalar ping-pong layer (RWTexture2D<ifloat>), analogous to
// velocity/pressure/divergence — NOT as an iparticle pigment channel. This keeps heat out of
// the particle "mass" totals (PressureProjection/Vorticity) and lets buoyancy sample it as an
// external field later (CP5), replacing the current _DensityRead.r fake-temperature proxy.
//
// CP1 scope: passive transport only (advection by velocity + decay toward ambient + optional
// diffusion). There are NO heat sources and heat drives NOTHING yet, so with heat == 0 the whole
// sim is byte-identical to pre-heat. Dedicated scalar kernels are used (rather than binding a
// scalar RHalf RT into the generic ifloat4 _Quantity* advection) for API safety across backends.
//
// NOTE (CP2/CP3): heat transport does not yet respect obstacle boundaries — advection back-traces
// and diffusion averages freely across _ObstacleRead solids. This is inert while heat == 0; gate
// AdvectHeat/DiffuseHeat around _ObstacleRead when heat gains sources (requires binding the
// obstacle RT to these kernels in FluidSolver).

#ifndef HEAT_INCLUDED
#define HEAT_INCLUDED

#include "SimulationCommon.hlsl"

// Heat textures (_HeatRead/_HeatWrite) and uniforms (_ThermalDissipation/_ThermalDiffusion/
// _AmbientTemperature) are declared in the main Fluids.compute.

// Bilinear sample of a scalar heat texture. Uses SIGNED pixel-space coords + clamp so texels near
// uv==0 (where uv - halfTexel goes slightly negative) don't underflow an unsigned cast to a huge
// index. floor() gives the correct base cell for negative coords; the fractional weight follows it.
ifloat SampleHeatBilinear(RWTexture2D<ifloat> tex, ifloat2 uv, ifloat2 simSize)
{
    // Sample center in pixel space (texel centers at +0.5).
    ifloat2 coord = uv * simSize - 0.5;
    ifloat2 baseF = floor(coord);
    ifloat2 f = coord - baseF;

    int2 b = (int2)baseF;
    int2 maxc = int2((int)simSize.x - 1, (int)simSize.y - 1);
    int2 p00 = clamp(b,             int2(0, 0), maxc);
    int2 p10 = clamp(b + int2(1, 0), int2(0, 0), maxc);
    int2 p01 = clamp(b + int2(0, 1), int2(0, 0), maxc);
    int2 p11 = clamp(b + int2(1, 1), int2(0, 0), maxc);

    ifloat v00 = tex[(iuint2)p00];
    ifloat v10 = tex[(iuint2)p10];
    ifloat v01 = tex[(iuint2)p01];
    ifloat v11 = tex[(iuint2)p11];

    return lerp(lerp(v00, v10, f.x), lerp(v01, v11, f.x), f.y);
}

// Semi-Lagrangian advection of scalar heat by the velocity field, with exponential decay toward
// ambient. Mirrors Advection() but for a scalar quantity and with heat-specific decay.
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void AdvectHeat(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    ifloat2 uv = PixelToUV(id.xy, _SimParams.simulationSize);

    // Sample velocity (pixel-space units) and back-trace by real frame dt (dt-normalized flow).
    ifloat2 velocity = _VelocityRead[id.xy].xy;
    ifloat2 velocityUV = velocity / _SimParams.simulationSize;
    ifloat2 prevUV = saturate(uv - (velocityUV * _FrameDeltaTime));

    ifloat advected = SampleHeatBilinear(_HeatRead, prevUV, _SimParams.simulationSize);

    // Decay toward ambient: retention is per-second, dt-normalized so cooling is frame-rate
    // independent. _ThermalDissipation == 1 => persistent; ambient default 0.
    ifloat retention = pow(max(_ThermalDissipation, 0.0), _FrameDeltaTime);
    _HeatWrite[id.xy] = _AmbientTemperature + (advected - _AmbientTemperature) * retention;
}

// Scalar heat diffusion: blend toward the cardinal-neighbor average by _ThermalDiffusion (0..1).
// Heat is expected to spread faster than pigments, so this is a separate knob from ink viscosity.
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void DiffuseHeat(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    iuint2 size = iuint2(_SimParams.simulationSize);

    iuint2 left  = iuint2(max((int)id.x - 1, 0), id.y);
    iuint2 right = iuint2(min(id.x + 1, size.x - 1), id.y);
    iuint2 down  = iuint2(id.x, max((int)id.y - 1, 0));
    iuint2 up    = iuint2(id.x, min(id.y + 1, size.y - 1));

    ifloat center = _HeatRead[id.xy];
    ifloat avg = (_HeatRead[left] + _HeatRead[right] + _HeatRead[down] + _HeatRead[up]) * 0.25;

    _HeatWrite[id.xy] = lerp(center, avg, saturate(_ThermalDiffusion));
}

// Heat sources (CP3): fire concentration emits heat into the field. Add-only — this reads the
// particle buffer but NEVER writes it, so fire is unaffected. Non-fire cells add nothing. The
// source is dt-normalized (_FrameDeltaTime) so substeps/framerate don't change emission strength,
// and clamped to _MaxHeat to prevent runaway. When disabled, current heat passes through unchanged.
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void AddHeatSources(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    iuint2 size = iuint2(_SimParams.simulationSize);
    iuint idx = id.y * size.x + id.x;

    ifloat heat = _HeatRead[id.xy];

    if (_EnableHeatSources != 0)
    {
        ifloat fire = _ParticlesRead[idx].fire;
        heat = min(_MaxHeat, heat + fire * _FireHeatEmissionRate * _FrameDeltaTime);
    }

    _HeatWrite[id.xy] = heat;
}

#endif // HEAT_INCLUDED
