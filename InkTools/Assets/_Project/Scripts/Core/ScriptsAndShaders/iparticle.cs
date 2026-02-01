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
        public float fire;              // fire ink
        public float water;             // water ink
        public float plantSeeded;       // plant (seeded)
        public float plantGrown;        // plant (grown)
        public float steam;             // steam ink
        public float glitter;           // glitter ink
        public float blackBody;         // black body ink
        public float electricitySeeded; // electricity / lightning (seeded)
        public float electricityGrown;  // electricity / lightning (grown)
        public float ice;               // ice ink

        // Color overrides (for custom rendering)
        public float red;               // red color override
        public float green;             // green color override
        public float blue;              // blue color override
        public float alpha;             // alpha override

#if CSHARP_7_3_OR_NEWER

    }   // iparticle

}   // Magi.InkTools.Simulation

#else

    };  // iparticle

#endif
