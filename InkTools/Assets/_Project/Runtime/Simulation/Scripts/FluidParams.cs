#if CSHARP_7_3_OR_NEWER
using System;
using System.Runtime.InteropServices;
using Unity.Mathematics;

namespace Magi.InkTools.Runtime.Simulation
{
  [StructLayout(LayoutKind.Sequential, Pack = 0)]
  [Serializable]
#else
#define public
#endif
  public struct FluidParams
  {
    public int resolution;
    public float deltaTime;
    public float viscosity;
    public float vorticity;
    public float dissipation;
    public float velocityDissipation;
    public float2 padding;

#if CSHARP_7_3_OR_NEWER

    public static FluidParams Default => new FluidParams
    {
      resolution = 256,
      deltaTime = 0.016f,
      viscosity = 0.0001f,
      vorticity = 10f,
      dissipation = 0.998f,
      velocityDissipation = 0.999f,
      padding = float2.zero
    };

  }   // FluidParams

}   // Magi.InkTools.Runtime.Simulation

#else

  };  // FluidParams

#endif