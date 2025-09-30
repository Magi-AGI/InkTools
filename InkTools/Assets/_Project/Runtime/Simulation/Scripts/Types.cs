// Type definitions for consistent usage between C# and HLSL
// Uses Unity.Mathematics half type for 16-bit floating point on mobile

global using ifloat = Unity.Mathematics.half;
global using ifloat2 = Unity.Mathematics.half2;
global using ifloat3 = Unity.Mathematics.half3;
global using ifloat4 = Unity.Mathematics.half4;

// idouble maps to float for mobile performance (not actual double)
global using idouble = System.Single;
global using idouble2 = Unity.Mathematics.float2;
global using idouble3 = Unity.Mathematics.float3;
global using idouble4 = Unity.Mathematics.float4;
global using idouble4x4 = Unity.Mathematics.float4x4;

// Standard precision types
global using float2 = Unity.Mathematics.float2;
global using float3 = Unity.Mathematics.float3;
global using float4 = Unity.Mathematics.float4;
global using float2x2 = Unity.Mathematics.float2x2;
global using float3x3 = Unity.Mathematics.float3x3;
global using float4x4 = Unity.Mathematics.float4x4;

global using int2 = Unity.Mathematics.int2;
global using int3 = Unity.Mathematics.int3;
global using int4 = Unity.Mathematics.int4;
global using uint2 = Unity.Mathematics.uint2;
global using uint3 = Unity.Mathematics.uint3;
global using uint4 = Unity.Mathematics.uint4;

namespace Magi.InkTools.Runtime.Simulation
{
    /// <summary>
    /// Type definitions for Magi.InkTools simulation systems.
    /// These types ensure consistency between C# and compute shaders.
    /// </summary>
    public static class SimTypes
    {
        public const string HLSL_TYPES_INCLUDE = @"
// HLSL type definitions to match C# types
#ifndef MAGI_INKTOOLS_TYPES_INCLUDED
#define MAGI_INKTOOLS_TYPES_INCLUDED

#ifdef UNITY_HALF_PRECISION_SUPPORT
    #define ifloat half
    #define ifloat2 half2
    #define ifloat3 half3
    #define ifloat4 half4
#else
    #define ifloat float
    #define ifloat2 float2
    #define ifloat3 float3
    #define ifloat4 float4
#endif

#endif // MAGI_INKTOOLS_TYPES_INCLUDED
";
    }
}