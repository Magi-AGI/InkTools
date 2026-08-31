// Type definitions for consistent usage between C# and HLSL.
//
// D2/M0: `ifloat` defaults to FLOAT (storage-float), NOT half. iparticle uses `ifloat` fields, and the
// particle ComputeBuffer's C#-side stride (Marshal.SizeOf<iparticle>()) must match the GPU layout every
// backend produces. M0 grew iparticle to 15 fields = a portable 60 bytes in float; `half` would make it
// 30 bytes, only safe where the shader compiler promotes half in structured buffers (NOT guaranteed on DX12/mobile).
//
// Central switch, mirrored in HLSL (InkToolsTypes.hlsl gates the SAME symbol). Do NOT hand-edit either
// side: the InkTools > ifloat Mode Editor toggle (InkToolsIFloatModeToggle) is the SINGLE WRITER of this
// C# Standalone scripting define AND the generated HLSL include, and an EditMode audit test trips on any
// drift between them. Flipping to half is a future half-vs-float experiment (D3) that must be validated on
// DX11/DX12/iOS Metal/Android Vulkan before shipping. Default OFF = float on both sides (60-byte layout).
#if INKTOOLS_IFLOAT_HALF
global using ifloat = Unity.Mathematics.half;
global using ifloat2 = Unity.Mathematics.half2;
global using ifloat3 = Unity.Mathematics.half3;
global using ifloat4 = Unity.Mathematics.half4;
#else
global using ifloat = System.Single;
global using ifloat2 = Unity.Mathematics.float2;
global using ifloat3 = Unity.Mathematics.float3;
global using ifloat4 = Unity.Mathematics.float4;
#endif

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

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Type definitions for Magi.InkTools simulation systems.
    /// These types ensure consistency between C# and compute shaders.
    /// </summary>
    public static class SimTypes
    {
        // D2: kept in sync with the canonical InkToolsTypes.hlsl — `ifloat` DEFAULTS TO FLOAT, with an
        // opt-in INKTOOLS_IFLOAT_HALF branch for the future half-vs-float experiment (D3). Previously this
        // string branched on UNITY_HALF_PRECISION_SUPPORT (half-by-default), which contradicted the safe
        // 60-byte particle-buffer contract. This constant is currently unused (the shared header
        // InkToolsTypes.hlsl is the live include path); it is updated only to avoid re-introducing the
        // old half-by-default drift if anything ever consumes it.
        public const string HLSL_TYPES_INCLUDE = @"
// HLSL type definitions to match C# types
#ifndef MAGI_INKTOOLS_TYPES_INCLUDED
#define MAGI_INKTOOLS_TYPES_INCLUDED

#ifdef INKTOOLS_IFLOAT_HALF
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