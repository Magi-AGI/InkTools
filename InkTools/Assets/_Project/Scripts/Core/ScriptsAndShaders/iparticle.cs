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
    // (Types.cs / InkToolsTypes.hlsl), so this struct is 56 bytes exactly as before — the particle
    // ComputeBuffer stride and the float readback mirrors are unchanged. Do NOT flip ifloat to half
    // without the D3 per-backend validation: a 28-byte iparticle would break the StructuredBuffer layout
    // contract (see SimulationResources.CreateParticleBuffers and its stride guard).
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
