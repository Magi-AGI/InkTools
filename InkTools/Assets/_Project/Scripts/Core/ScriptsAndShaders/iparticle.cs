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
