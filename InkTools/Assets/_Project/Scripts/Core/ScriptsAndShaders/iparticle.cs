#if CSHARP_7_3_OR_NEWER

using System;
using System.Runtime.InteropServices;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Particle data structure for ink simulation.
    /// This is an X-Macro file that compiles as both C# and HLSL.
    /// Matches the struct definition in compute shaders.
    /// </summary>
    [StructLayout(LayoutKind.Sequential, Pack = 0)]
    [Serializable]
#else
#define public
#endif
    // D2: fields use `ifloat` (the shared x-macro type), for consistency across the C#/HLSL boundary and
    // so a future half-vs-float experiment can flip storage centrally. `ifloat` DEFAULTS TO FLOAT
    // (Types.cs / InkToolsTypes.hlsl). M0 (true Metal): this struct now has 15 ifloat fields = 60 bytes in
    // the default float mode (Metal added at ink index 10, after Ice and before the color overrides). The
    // particle ComputeBuffer stride and the float readback mirrors must match 60. Do NOT flip ifloat to half
    // without the D3 per-backend validation: a 30-byte iparticle would break the StructuredBuffer layout
    // contract (see SimulationResources.AllocateParticleBuffers and its stride guard, now 60).
    public struct iparticle
    {
        // Ink type concentrations
        public ifloat fire;              // fire ink
        public ifloat water;             // water ink
        public ifloat plantSeeded;       // plant (seeded)
        public ifloat plantGrown;        // plant (grown)
        public ifloat steam;             // steam ink
        public ifloat glitter;           // glitter ink
        public ifloat blackBody;         // black body ink
        public ifloat electricitySeeded; // electricity / lightning (seeded)
        public ifloat electricityGrown;  // electricity / lightning (grown)
        public ifloat ice;               // ice ink
        public ifloat metal;             // metal ink (index 10) — conductive substrate, distinct from blackBody

        // Color overrides (for custom rendering)
        public ifloat red;               // red color override
        public ifloat green;             // green color override
        public ifloat blue;              // blue color override
        public ifloat alpha;             // alpha override

#if CSHARP_7_3_OR_NEWER

    }   // iparticle

}   // Magi.InkTools.Simulation

#else

    };  // iparticle

#endif
