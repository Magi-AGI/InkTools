// Heat: scalar environment/temperature field transport.
//
// Heat is modeled as its OWN scalar ping-pong layer (RWTexture2D<ifloat>), analogous to
// velocity/pressure/divergence — NOT as an iparticle pigment channel. This keeps heat out of
// the particle "mass" totals (PressureProjection/Vorticity) and lets buoyancy sample it as an
// external field later (CP5), replacing the current _DensityRead.r fake-temperature proxy.
//
// Staged build-up:
//   CP1: passive transport foundation — advection by velocity + decay toward ambient + optional
//        diffusion. Dedicated scalar kernels are used (rather than binding a scalar RHalf RT into
//        the generic ifloat4 _Quantity* advection) for API safety across backends.
//   CP3: passive fire heat source — AddHeatSources adds heat from fire concentration (add-only,
//        does not modify particles). Heat is now non-zero wherever fire exists.
//   CP4: obstacle-aware transport (see note below).
// Heat still drives NOTHING else yet (no buoyancy/reactions/phase changes) — it is diagnostic state,
// visible only via the Heat debug view (_Channels2.z), never affecting Combined rendering.
//
// CP4: heat transport is now obstacle-aware (no-flux). DiffuseHeat treats obstacle neighbors as the
// center value (no exchange across a solid) and leaves obstacle cells un-diffused; AdvectHeat does
// not advect into obstacle cells and, if the velocity back-trace path crosses a solid, falls back to
// the current cell's heat instead of jumping heat across the obstacle. Requires _ObstacleRead bound
// to both kernels (done in FluidSolver.Step). IsObstacle()/_ObstacleRead come from Obstacles.hlsl,
// which Fluids.compute includes before this file.

#ifndef HEAT_INCLUDED
#define HEAT_INCLUDED

#include "SimulationCommon.hlsl"

// Heat textures (_HeatRead/_HeatWrite) and uniforms (_ThermalDissipation/_ThermalDiffusion/
// _AmbientTemperature) are declared in the main Fluids.compute.

// CP8a: every heat write must land inside the valid temperature range [_MinTemperature, _MaxHeat].
//
// The floor is _MinTemperature, NOT _AmbientTemperature. Those are different concepts: the ambient
// (neutral / room) temperature is only what heat RELAXES TOWARD, whereas the min is the absolute
// floor. Clamping to the neutral would make room temperature the coldest attainable state, so ice
// could never form. Sub-neutral temperatures are valid and must survive transport untouched.
//
// This is applied on EVERY write path (including the obstacle and sources-disabled early-outs),
// because with thermal interactions disabled the transport kernels are the ONLY thing writing heat —
// nothing downstream would correct an out-of-range value.
ifloat ClampTemperature(ifloat t)
{
    return clamp(t, _MinTemperature, _MaxHeat);
}

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

    ifloat2 simSize = _SimParams.simulationSize;
    ifloat retention = pow(max(_ThermalDissipation, 0.0), _FrameDeltaTime);
    ifloat current = _HeatRead[id.xy];

    // Obstacle cells don't pull fluid heat into themselves; just decay what they already hold.
    if (IsObstacle(id.xy) > 0.5)
    {
        _HeatWrite[id.xy] = ClampTemperature(_AmbientTemperature + (current - _AmbientTemperature) * retention);
        return;
    }

    ifloat2 uv = PixelToUV(id.xy, simSize);

    // Sample velocity (pixel-space units) and back-trace by real frame dt (dt-normalized flow).
    ifloat2 velocity = _VelocityRead[id.xy].xy;
    ifloat2 velocityUV = velocity / simSize;
    ifloat2 prevUV = saturate(uv - (velocityUV * _FrameDeltaTime));

    // No-flux advection: if the back-trace path crosses a solid, don't jump heat across it — fall
    // back to the current cell's heat. A fixed 4-sample march (from this cell toward the source)
    // keeps the obstacle test bounded and catches thin obstacles between cell and source.
    ifloat2 curPix  = (ifloat2)id.xy;
    ifloat2 prevPix = prevUV * simSize - 0.5;
    int2 maxc = int2((int)simSize.x - 1, (int)simSize.y - 1);
    bool blocked = false;
    [unroll]
    for (int s = 1; s <= 4; s++)
    {
        ifloat2 pos = lerp(curPix, prevPix, (ifloat)s / 4.0);
        int2 cell = clamp((int2)floor(pos + 0.5), int2(0, 0), maxc);
        if (IsObstacle((iuint2)cell) > 0.5)
            blocked = true;
    }

    ifloat advected = blocked ? current : SampleHeatBilinear(_HeatRead, prevUV, simSize);

    // Decay toward the NEUTRAL (room) temperature: retention is per-second, dt-normalized so cooling
    // is frame-rate independent. _ThermalDissipation == 1 => persistent.
    _HeatWrite[id.xy] = ClampTemperature(_AmbientTemperature + (advected - _AmbientTemperature) * retention);
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

    // Obstacle cells are not diffused (they don't exchange heat with the fluid); pass through.
    if (IsObstacle(id.xy) > 0.5)
    {
        _HeatWrite[id.xy] = ClampTemperature(center);
        return;
    }

    // No-flux: an obstacle neighbor contributes the center value (no exchange across the solid).
    ifloat hL = IsObstacle(left)  > 0.5 ? center : _HeatRead[left];
    ifloat hR = IsObstacle(right) > 0.5 ? center : _HeatRead[right];
    ifloat hD = IsObstacle(down)  > 0.5 ? center : _HeatRead[down];
    ifloat hU = IsObstacle(up)    > 0.5 ? center : _HeatRead[up];
    ifloat avg = (hL + hR + hD + hU) * 0.25;

    _HeatWrite[id.xy] = ClampTemperature(lerp(center, avg, saturate(_ThermalDiffusion)));
}

// Injection heat stamp (CP8b): writes a TARGET temperature into the heat field using the injection's
// own centre/radius/gaussian falloff, so a painted ink arrives at a sensible initial temperature.
//
// This kernel is deliberately ink-AGNOSTIC: it just stamps `_InjectionTargetHeat`. The caller decides
// what that target is per ink (Inkling maps Fire -> max, Water -> neutral, Ice -> min), which keeps
// gameplay semantics out of the engine package.
//
// It is a ONE-SHOT INITIAL CONDITION applied when an injection is queued — NOT a per-frame source. It
// therefore does not revive the free continuous fire heat that CP7b/CP7d deliberately removed: fire's
// ongoing emission remains owned by the thermal-interactions pass, with its fuel cost.
//
// GaussianFalloff is 1.0 at distance 0, so the centre lands exactly on the target; cells outside the
// radius pass through untouched. The result is clamped to [_MinTemperature, _MaxHeat] like every other
// heat write, so an out-of-range target cannot escape the valid range.
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void StampInjectionHeat(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    ifloat current = _HeatRead[id.xy];
    ifloat result = current;

    ifloat2 pos = (ifloat2)id.xy;
    ifloat dist = length(pos - _ForceParams.position);

    if (dist < _ForceParams.radius)
    {
        ifloat falloff = GaussianFalloff(dist, _ForceParams.radius);
        result = lerp(current, _InjectionTargetHeat, falloff);
    }

    _HeatWrite[id.xy] = ClampTemperature(result);
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

    // Clamp on EVERY path, not just when sources are enabled — otherwise an out-of-range value would
    // pass straight through this kernel untouched.
    _HeatWrite[id.xy] = ClampTemperature(heat);
}

#endif // HEAT_INCLUDED
