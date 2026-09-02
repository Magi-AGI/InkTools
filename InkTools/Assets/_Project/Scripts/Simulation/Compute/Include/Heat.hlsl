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
// CP4 made heat transport obstacle-aware (NO-FLUX: obstacles blocked heat ENTIRELY). CP8d/CP8k/CP8l
// dismantled that because it was a modelling error: an ink obstacle (ice, plant) is MATTER, not vacuum,
// and matter CONDUCTS heat. CP8q then overcorrected — it gave heat an ADVECTIVE path through solids too,
// which conflated the two physics. CP8z restores the clean split (Lake: "we may have made a mistake in
// allowing advection through obstacles when what we really needed was conduction"):
//
//   • CONDUCTION crosses solids (DiffuseHeat) — matter exchanges heat, and solids conduct BETTER than
//     fluid. This is how a flame melts adjacent ice and heats plant to ignition.
//   • ADVECTION does NOT cross solids — advection is transport BY THE FLUID, and fluid cannot enter a
//     solid. Heat has no special advective licence a wall would deny to mass.
//
// The obstacle mask therefore has TWO distinct roles, one per kernel:
//
//   AdvectHeat  — in the DEFAULT strict mode (_HeatObstacleMode 0) the mask is a BARRIER again: a solid
//                 cell does not advect at all, and a fluid back-trace that crosses a solid is refused
//                 (no-flux). CP8q's advective behaviour (mask as a "borrow velocity" detector plus the
//                 pre-boundary snapshot) survives ONLY as the opt-in legacy mode 1, for Fire-vs-Ice A/B.
//   DiffuseHeat — reads the mask ONLY to choose between _ThermalDiffusionSolid and _ThermalDiffusion; it
//                 is a CONDUCTIVITY SELECTOR, never a barrier, and never blocks exchange. _ObstacleRead
//                 must STAY BOUND for this kernel (FluidSolver.Step binds it).
//
// LIMITATION, unchanged and worth restating: the mask merges geometry AND ink-generated obstacles into a
// single RFloat, so we cannot distinguish a stone wall from a block of ice — both get the solid rate.
// Defensible (stone conducts heat too), but it is an approximation. A per-cell CONDUCTIVITY mask is the
// principled fix and would slot straight into the `rate` selection in DiffuseHeat.

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

    ifloat2 uv = PixelToUV(id.xy, simSize);

    // Sample velocity (pixel-space units) and back-trace by real frame dt (dt-normalized flow).
    ifloat2 velocity = _VelocityRead[id.xy].xy;

    // CP8z — STRICT CONDUCTION-ONLY (default, _HeatObstacleMode == 0).
    //
    // Lake: "we may have made a mistake in allowing advection through obstacles when what we really
    // needed was conduction."
    //
    // Advection is transport BY THE FLUID; conduction is transport THROUGH MATTER. A solid blocks fluid,
    // so it blocks ADVECTIVE heat transport — but it is still matter, so heat crosses it by CONDUCTION
    // (DiffuseHeat, which reads the mask only as a conductivity selector and never as a barrier). CP8q
    // conflated the two by giving heat an advective path through solids; CP8z removes that from the
    // default model and restores the clean split:
    //
    //   • a SOLID cell does not advect at all — it only decays what it holds; DiffuseHeat warms it.
    //   • a FLUID cell whose back-trace path crosses a solid does NOT sample across it (no-flux),
    //     so heat cannot teleport through a thin wall or ride the flow around/into a barrier.
    //
    // The host binds the CLIPPED velocity field here in strict mode, so there is no unclipped snapshot to
    // punch heat through a solid. _ThermalSolidPermeability is ignored. The legacy CP8q advective path is
    // preserved verbatim below for _HeatObstacleMode == 1 so the Fire-vs-Ice harness can compare them.
    if (_HeatObstacleMode == 0)
    {
        // A solid conducts (DiffuseHeat) but never advects — just relax what it holds toward ambient.
        if (IsObstacle(id.xy) > 0.5)
        {
            _HeatWrite[id.xy] = ClampTemperature(_AmbientTemperature + (current - _AmbientTemperature) * retention);
            return;
        }

        ifloat2 sVelUV = velocity / simSize;
        ifloat2 sPrevUV = saturate(uv - (sVelUV * _FrameDeltaTime));

        // No-flux back-trace: a fixed 4-sample march from this cell toward the source. If any sampled
        // cell along the path is solid, the flow would have had to cross a wall to bring that heat here,
        // so refuse it and keep the current value. Catches thin obstacles between cell and source.
        ifloat2 sCurPix  = (ifloat2)id.xy;
        ifloat2 sPrevPix = sPrevUV * simSize - 0.5;
        int2 sMaxc = int2((int)simSize.x - 1, (int)simSize.y - 1);
        bool sBlocked = false;
        [unroll]
        for (int ss = 1; ss <= 4; ss++)
        {
            ifloat2 sPos = lerp(sCurPix, sPrevPix, (ifloat)ss / 4.0);
            int2 sCell = clamp((int2)floor(sPos + 0.5), int2(0, 0), sMaxc);
            if (IsObstacle((iuint2)sCell) > 0.5)
                sBlocked = true;
        }

        ifloat sAdvected = sBlocked ? current : SampleHeatBilinear(_HeatRead, sPrevUV, simSize);
        _HeatWrite[id.xy] = ClampTemperature(_AmbientTemperature + (sAdvected - _AmbientTemperature) * retention);
        return;
    }

    // ── LEGACY advective path (_HeatObstacleMode == 1), retained for A/B only ────────────────────────
    // CP8q — HEAT IS ENERGY, NOT MASS: it must cross into solids even though mass cannot.
    //
    // Lake: "I do want the heat to advect through the obstacle ice. The point is that the ice should melt
    // when exposed to a heat source, and the obstacle created by ice blocking that heat from transferring
    // effectively stops the ice from melting."
    //
    // ApplyObstacleBoundary (Obstacles.hlsl) zeroes velocity INSIDE every solid and clips neighbouring
    // flow that points into one. That is correct for MASS/MOMENTUM — fluid must not enter a wall. But
    // AdvectHeat reads the same already-clipped field, so a solid cell back-traced with zero velocity,
    // sampled its own heat, and obstacle ice became a PERFECT THERMAL BARRIER. It could never warm from
    // an adjacent flame, so it could never reach the melt threshold — exactly the reported bug.
    //
    // The fix has TWO halves and BOTH are required — either alone is a no-op:
    //
    //   (a) HERE: inside a solid, heat borrows the surrounding fluid's velocity (the flow pressing on the
    //       face), scaled by _ThermalSolidPermeability. Mass/velocity blocking is untouched; permeability
    //       0 leaves the cell's own velocity, restoring the old behaviour exactly.
    //
    //   (b) IN C#: FluidSolver snapshots velocity into ctx.VelocityThermal BEFORE ApplyObstacleBoundary
    //       runs, and binds THAT to this kernel instead of the clipped ctx.Velocity.Read.
    //
    // (b) is what makes (a) work, and it was learned the hard way. With the clipped field, (a) alone was
    // MEASURED ineffective — face temperature identical at permeability 0 and 1 (0.04540 either way) —
    // because ApplyObstacleBoundary does not only zero the SOLID's velocity, it ALSO clips the adjacent
    // fluid's inward flow. There was simply nothing left near the face to borrow. Feeding this kernel the
    // pre-boundary snapshot restores that inward flow, so the borrow finally has a real source.
    //
    // NOTE the snapshot is one frame late (heat transport runs earlier in the step than the snapshot),
    // which is consistent with semi-Lagrangian advection already working off prior state. It is ZEROED in
    // ClearAll alongside the velocity buffers, so first use after allocation/reset is deterministic.
    if (IsObstacle(id.xy) > 0.5)
    {
        iuint2 size = iuint2(simSize);
        iuint2 l = iuint2(max((int)id.x - 1, 0), id.y);
        iuint2 r = iuint2(min(id.x + 1, size.x - 1), id.y);
        iuint2 d = iuint2(id.x, max((int)id.y - 1, 0));
        iuint2 u = iuint2(id.x, min(id.y + 1, size.y - 1));

        ifloat2 borrowed = (_VelocityRead[l].xy + _VelocityRead[r].xy
                          + _VelocityRead[d].xy + _VelocityRead[u].xy) * 0.25;

        // lerp, NOT `borrowed * permeability`: at permeability 0 the cell keeps its OWN velocity, so the
        // behaviour is byte-identical to pre-CP8q for any caller that supplies one. (At runtime a solid's
        // own velocity is zero anyway, so lerp(0, borrowed, p) == borrowed * p there — but forcing zero
        // would have broken existing tests that hand the kernel an explicit velocity inside a solid.)
        velocity = lerp(velocity, borrowed, saturate(_ThermalSolidPermeability));
    }

    ifloat2 velocityUV = velocity / simSize;
    ifloat2 prevUV = saturate(uv - (velocityUV * _FrameDeltaTime));

    // CP8k removed two obstacle behaviours from this kernel: (1) an early-out, so an obstacle cell never
    // sampled anything and only decayed what it already held, and (2) a no-flux back-trace, so heat
    // could not be carried across a solid. Neither is a barrier any more.
    //
    // CP8q: the kernel DOES still read the mask, but purely as a solid DETECTOR — to decide whether a
    // cell may borrow its neighbours' velocity for heat transport. It is never a no-flux gate.
    //
    // CP8m said advection into ice "cannot, and never could" happen, because ApplyObstacleBoundary zeroes
    // solid velocity — and concluded conduction was the ONLY way heat enters ice.
    //
    // CP8q SUPERSEDES that conclusion. The observation was accurate about the old code, but it treated an
    // implementation consequence as an immutable law. Zeroed velocity is a MASS boundary condition; heat
    // is energy and has no reason to inherit it. See the permeability block above: solid cells now borrow
    // the adjacent fluid's velocity for heat transport only.
    //
    // Still true and still load-bearing: a FLUID cell whose back-trace crosses a solid no longer has its
    // heat pinned, so heat can flow past and around ink solids instead of being dammed by them.
    //
    // NOTE the limitation, unchanged: the obstacle mask merges geometry AND ink-generated obstacles into
    // one RFloat, so we cannot tell a stone wall from a block of ice. A per-cell CONDUCTIVITY mask is the
    // principled fix, and it would slot into the rate selection in DiffuseHeat — not here.
    ifloat advected = SampleHeatBilinear(_HeatRead, prevUV, simSize);

    // Decay toward the NEUTRAL (room) temperature: retention is per-second, dt-normalized so cooling
    // is frame-rate independent. _ThermalDissipation == 1 => persistent.
    _HeatWrite[id.xy] = ClampTemperature(_AmbientTemperature + (advected - _AmbientTemperature) * retention);
}

// Scalar heat CONDUCTION: exponential approach to the cardinal-neighbour average.
//
// CP8l — TWO fixes here, one a real bug and one a design requirement.
//
// (1) dt-NORMALISATION. This used to be a flat `lerp(center, avg, _ThermalDiffusion)` applied ONCE PER
//     FRAME, with no _FrameDeltaTime — the only heat term in the whole file that was not dt-normalised.
//     At 60fps a 0.2 blend/frame is an effective rate of ~12/sec, which meant conduction beat fire's own
//     dt-normalised emission by SIX TO ONE: a fire cell could not hold its own temperature, and any hot
//     spot smeared out before it could melt ice or ignite plant. It was also frame-rate dependent, so the
//     whole thermal model behaved differently on a slow machine.
//
//     _ThermalDiffusion is now a PER-SECOND rate, and the per-frame blend is 1 - exp(-rate*dt): a proper
//     frame-rate-independent exponential approach. NOTE the units changed — an old value of 0.2 is NOT
//     the same as a new value of 0.2.
//
// (2) SOLIDS CONDUCT BETTER THAN FLUID. Lake: "Heat should travel even more readily through solids than
//     it does in the open fluids." This is physically right — ice and rock conduct far better than the
//     water/air around them.
//
//     CP8z: in the DEFAULT strict model, conduction is once again the ONLY way heat crosses a solid —
//     advection is transport by the fluid, and fluid cannot enter a solid. So this rate is the whole
//     story for a solid's heat ingress. (CP8q briefly added an advective interface path via
//     _ThermalSolidPermeability + a pre-boundary velocity snapshot; that survives only as the opt-in
//     legacy mode 1, and does nothing in the default model.)
//
//     LIMITATION, stated plainly: the obstacle mask merges geometry AND ink-generated obstacles into one
//     RFloat, so this cannot tell a stone wall from a block of ice — both get the solid rate. That is
//     defensible (stone conducts too) but it is an approximation, not a distinction we can currently make.
ifloat ConductionBlend(ifloat ratePerSecond, ifloat dt)
{
    return saturate(1.0 - exp(-max(ratePerSecond, 0.0) * dt));
}
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

    // CP8d — CONDUCTION IGNORES OBSTACLES, DELIBERATELY.
    //
    // Conduction is transport THROUGH MATTER, and an ink obstacle IS matter — ice and plant are solids,
    // not vacuum. Real ice conducts heat (that is why it melts when you put a flame near it), and real
    // vegetation heats up until it ignites.
    //
    // CONDUCTION vs ADVECTION — the distinction CP8z restored. Conduction crosses a solid (this kernel);
    // advection does not (AdvectHeat, strict mode). That is the correct split: conduction is transport
    // through matter, advection is transport by the fluid, and fluid cannot enter a solid.
    //
    // History, so the reversals are legible: CP8k briefly sealed obstacles off from advection too, which
    // left conduction unable to outpace the melt drawing heat back out, so ice never melted. CP8q then
    // overcorrected by giving heat an ADVECTIVE path through solids (a pre-boundary velocity snapshot plus
    // _ThermalSolidPermeability). Lake judged that a modelling mistake — "we may have made a mistake in
    // allowing advection through obstacles when what we really needed was conduction" — so CP8z made
    // strict conduction-only the default and demoted the advective path to opt-in legacy mode 1. The real
    // fix for "ice never melted" is to make CONDUCTION strong enough (thermalDiffusionSolid), not to open
    // an advective loophole. Conduction is once again the ONLY way heat enters a solid in the default model.
    //
    // CP8l: this kernel STILL reads the mask, but its meaning has inverted — it is now a CONDUCTIVITY
    // SELECTOR (solid rate vs fluid rate), never a barrier. Nothing here blocks heat exchange.)
    //
    // Treating ink obstacles as no-flux made them PERFECT INSULATORS: fire next to a plant could never
    // warm it, so heat-driven ignition was physically impossible and dense ice could never be melted
    // from outside. That is the bug this fixes.
    //
    // Note the obstacle mask merges geometry AND ink-generated obstacles into one RFloat, so we cannot
    // distinguish them here. That is fine: a stone wall conducts heat too. If insulating geometry is
    // ever wanted, the right mechanism is a per-cell CONDUCTIVITY mask (how fast heat crosses), not
    // resurrecting the velocity obstacle mask — which would re-conflate the two physics.
    ifloat avg = (_HeatRead[left] + _HeatRead[right] + _HeatRead[down] + _HeatRead[up]) * 0.25;

    // CP8l: solids conduct BETTER than open fluid. Keyed on whether THIS cell is solid — heat entering,
    // crossing and leaving a block of ice all travel at the solid rate, which is what makes a block heat
    // through rather than only skinning at the surface.
    //
    // CP8m — the max() is a SAFETY INVARIANT, not a style choice. "Solids conduct at least as readily as
    // fluid" is the entire design intent, so encode it here rather than trusting the host to upload a
    // sane value. It also closes a genuinely nasty failure mode: an unset compute-shader float is ZERO,
    // so if _ThermalDiffusionSolid is ever not uploaded (e.g. the C# assembly fails to compile and Unity
    // silently keeps running the last good build, while the SHADER — which compiles separately — happily
    // picks up the new uniform), every obstacle cell would get rate 0 and ice would become a PERFECT
    // INSULATOR. That is strictly worse than the CP4 behaviour this file spent three checkpoints
    // removing, and it fails SILENTLY. With max(), an unset solid rate degrades to the fluid rate.
    //
    // CP8o — THERMAL-SOLID classification is DECOUPLED from the VELOCITY obstacle mask.
    //
    // IsObstacle is written by InkToObstacles at Ice.obstacleThreshold (0.5), and that threshold governs
    // FLUID BLOCKING — Lake wants it kept high so thin ice does not dam flow. But conduction needs painted
    // ice (deposited at ~densityAmount 0.3) to count as solid so it can heat THROUGH and melt. CP8n tried
    // to satisfy both by lowering the mask threshold to 0.15; that coupled the two and made thin ice block
    // flow, which Lake rejected. So conduction now reads the ICE CONCENTRATION directly against its OWN
    // threshold (_ThermalSolidThresholdIce, ~0.1), fully independent of the flow-obstacle threshold.
    //
    // Geometry and other ink obstacles still count as thermal-solid via IsObstacle, so walls conduct too.
    uint pidx = id.y * size.x + id.x;
    bool iceThermalSolid = _ThermalSolidThresholdIce > 0.0
                         && _ParticlesRead[pidx].ice >= _ThermalSolidThresholdIce;
    // M3b: true Metal is also thermal-solid by CONCENTRATION (>= _ThermalSolidThresholdMetal, ~0.1), the
    // same decoupled mechanism as ice — SEPARATE from Metal's 0.5 flow-obstacle threshold. Dense metal
    // (>=0.5) already conducts via IsObstacle; this adds thin/sub-obstacle metal conduction. BlackBody is
    // NOT metal and is never classified here. Reuses the generic solid rate (no distinct metal rate yet).
    bool metalThermalSolid = _ThermalSolidThresholdMetal > 0.0
                          && _ParticlesRead[pidx].metal >= _ThermalSolidThresholdMetal;
    bool thermalSolid = iceThermalSolid || metalThermalSolid || (IsObstacle(id.xy) > 0.5);

    ifloat solidRate = max(_ThermalDiffusionSolid, _ThermalDiffusion);
    ifloat rate = thermalSolid ? solidRate : _ThermalDiffusion;

    _HeatWrite[id.xy] = ClampTemperature(lerp(center, avg, ConductionBlend(rate, _FrameDeltaTime)));
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
