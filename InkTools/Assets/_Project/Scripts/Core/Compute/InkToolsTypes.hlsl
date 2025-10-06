// InkTools type definitions for HLSL
// Matches the C# global usings in Types.cs
// Hardware without half support will automatically promote to float

#ifndef INKTOOLS_TYPES_HLSL
#define INKTOOLS_TYPES_HLSL

// ifloat types - use half precision (hardware will promote if unsupported)
#define ifloat half
#define ifloat2 half2
#define ifloat3 half3
#define ifloat4 half4

// idouble types - map to float for mobile performance
#define idouble float
#define idouble2 float2
#define idouble3 float3
#define idouble4 float4
#define idouble4x4 float4x4

#endif // INKTOOLS_TYPES_HLSL