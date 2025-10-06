#if CSHARP_7_3_OR_NEWER
using System;
using System.Runtime.InteropServices;
using Unity.Mathematics;

namespace Magi.InkTools.Simulation
{
  [StructLayout(LayoutKind.Sequential, Pack = 0)]
  [Serializable]
#else
#define public
#endif
  public struct InjectionParams
  {
    public float4 point;     // xy: position, z: radius, w: strength
    public float4 force;     // xy: force vector, zw: unused
    public float4 color;     // rgba: color to inject

#if CSHARP_7_3_OR_NEWER

    public static InjectionParams Default => new InjectionParams
    {
      point = new float4(0.5f, 0.5f, 0.05f, 1f),
      force = float4.zero,
      color = new float4(1, 1, 1, 1)
    };

  }   // InjectionParams

}   // Magi.InkTools.Simulation

#else

  };  // InjectionParams

#endif