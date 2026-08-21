// InkTools type definitions for HLSL
// Matches the C# global usings in Types.cs
//
// D2: `ifloat` defaults to FLOAT (storage-float), NOT half. This is deliberate and load-bearing:
// iparticle uses `ifloat` fields, and a StructuredBuffer<iparticle> must have a layout that every backend
// agrees on. `float` fields are unambiguously 56 bytes on FXC/DXC/Metal/Vulkan; `half` fields are only
// 56 where the compiler promotes half in structured buffers, which is NOT guaranteed on DX12/mobile.
// Keeping float here preserves the safe 56-byte cross-platform particle layout.
//
// The switch is CENTRAL and consistent with C# (Types.cs gates the same symbol): define
// INKTOOLS_IFLOAT_HALF (shader keyword / global define AND the matching C# scripting define) to flip both
// sides to half for a future half-vs-float experiment. That experiment (D3) must be validated on
// DX11 + DX12 + iOS Metal + Android Vulkan before shipping, because half StructuredBuffer storage/stride
// behaviour differs per backend. Default OFF = float everywhere.

#ifndef INKTOOLS_TYPES_HLSL
#define INKTOOLS_TYPES_HLSL

#ifdef INKTOOLS_IFLOAT_HALF
    // Experimental 16-bit storage (D3 — requires per-backend validation).
    #define ifloat half
    #define ifloat2 half2
    #define ifloat3 half3
    #define ifloat4 half4
#else
    // Default: storage-float. Guarantees the 56-byte iparticle layout on every backend.
    #define ifloat float
    #define ifloat2 float2
    #define ifloat3 float3
    #define ifloat4 float4
#endif

// idouble types - map to float for mobile performance
#define idouble float
#define idouble2 float2
#define idouble3 float3
#define idouble4 float4
#define idouble4x4 float4x4

#endif // INKTOOLS_TYPES_HLSL