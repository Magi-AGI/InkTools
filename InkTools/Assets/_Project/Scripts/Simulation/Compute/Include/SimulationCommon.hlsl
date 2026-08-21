// Common utilities and helper functions for fluid simulation

#ifndef SIMULATION_COMMON_INCLUDED
#define SIMULATION_COMMON_INCLUDED

#include "SimulationTypes.hlsl"

// Global simulation parameters - these will be initialized in each kernel
#ifndef SIMPARAMS_DEFINED
#define SIMPARAMS_DEFINED
SimulationParams _SimParams;
ForceParams _ForceParams;
#endif

// Helper function for boundary checks
bool IsValidPixel(iuint2 coord, ifloat2 simSize)
{
    return coord.x < (iuint)simSize.x && coord.y < (iuint)simSize.y;
}

// Bilinear sampling for RWTexture2D with ifloat4
ifloat4 SampleBilinear(RWTexture2D<ifloat4> tex, ifloat2 uv, ifloat2 simSize)
{
    ifloat2 texelSize = 1.0 / simSize;
    ifloat2 p = uv - texelSize * 0.5;

    ifloat2 f = frac(p * simSize);

    iuint2 p00 = iuint2(p * simSize);
    iuint2 p10 = iuint2(min(p00.x + 1, simSize.x - 1), p00.y);
    iuint2 p01 = iuint2(p00.x, min(p00.y + 1, simSize.y - 1));
    iuint2 p11 = iuint2(min(p00.x + 1, simSize.x - 1), min(p00.y + 1, simSize.y - 1));

    ifloat4 v00 = tex[p00];
    ifloat4 v10 = tex[p10];
    ifloat4 v01 = tex[p01];
    ifloat4 v11 = tex[p11];

    return lerp(
        lerp(v00, v10, f.x),
        lerp(v01, v11, f.x),
        f.y
    );
}

// Overload for float4 textures. Only compiled in true-half mode (INKTOOLS_IFLOAT_HALF):
// there ifloat4 is half4, a distinct type from float4, so this overload is genuinely needed.
// Under the DEFAULT float mode ifloat4 IS float4, so the ifloat4 overload above already covers
// float4 textures and defining this too is a redefinition (D3D11 "redefinition of 'SampleBilinear'").
// Guarded so true-half experiments keep both overloads.
#ifdef INKTOOLS_IFLOAT_HALF
ifloat4 SampleBilinear(RWTexture2D<float4> tex, ifloat2 uv, ifloat2 simSize)
{
    ifloat2 texelSize = 1.0 / simSize;
    ifloat2 p = uv - texelSize * 0.5;

    ifloat2 f = frac(p * simSize);

    iuint2 p00 = iuint2(p * simSize);
    iuint2 p10 = iuint2(min(p00.x + 1, simSize.x - 1), p00.y);
    iuint2 p01 = iuint2(p00.x, min(p00.y + 1, simSize.y - 1));
    iuint2 p11 = iuint2(min(p00.x + 1, simSize.x - 1), min(p00.y + 1, simSize.y - 1));

    float4 v00 = tex[p00];
    float4 v10 = tex[p10];
    float4 v01 = tex[p01];
    float4 v11 = tex[p11];

    float4 result = lerp(
        lerp(v00, v10, f.x),
        lerp(v01, v11, f.x),
        f.y
    );

    return ifloat4(result);
}
#endif // INKTOOLS_IFLOAT_HALF

// Get neighbor samples with boundary conditions
struct NeighborSamples
{
    ifloat4 left;
    ifloat4 right;
    ifloat4 down;
    ifloat4 up;
    ifloat4 center;
};

NeighborSamples GetNeighbors(RWTexture2D<ifloat4> tex, iuint2 coord, ifloat2 simSize)
{
    NeighborSamples samples;

    // Sample with clamping
    iuint2 left = iuint2(max(coord.x - 1, 0), coord.y);
    iuint2 right = iuint2(min(coord.x + 1, simSize.x - 1), coord.y);
    iuint2 down = iuint2(coord.x, max(coord.y - 1, 0));
    iuint2 up = iuint2(coord.x, min(coord.y + 1, simSize.y - 1));

    samples.left = tex[left];
    samples.right = tex[right];
    samples.down = tex[down];
    samples.up = tex[up];
    samples.center = tex[coord];

    return samples;
}

// Apply boundary conditions for velocity
ifloat2 ApplyVelocityBoundary(ifloat2 velocity, iuint2 coord, ifloat2 simSize, int boundaryType)
{
    if (boundaryType == BOUNDARY_NO_SLIP)
    {
        // No-slip: velocity is zero at walls
        if (coord.x == 0 || coord.x >= (iuint)(simSize.x - 1)) velocity.x = 0;
        if (coord.y == 0 || coord.y >= (iuint)(simSize.y - 1)) velocity.y = 0;
    }
    else if (boundaryType == BOUNDARY_FREE_SLIP)
    {
        // Free-slip: only normal component is zero
        if (coord.x == 0 || coord.x >= (iuint)(simSize.x - 1)) velocity.x = 0;
        if (coord.y == 0 || coord.y >= (iuint)(simSize.y - 1)) velocity.y = 0;
    }

    return velocity;
}

// Maximum velocity magnitude to prevent simulation explosion
#define MAX_VELOCITY_MAGNITUDE 500.0

// Clamp velocity to maximum magnitude to prevent explosion
ifloat2 ClampVelocity(ifloat2 velocity)
{
    ifloat mag = length(velocity);
    if (mag > MAX_VELOCITY_MAGNITUDE)
    {
        velocity = velocity * (MAX_VELOCITY_MAGNITUDE / mag);
    }
    return velocity;
}

// Gaussian falloff for force injection
ifloat GaussianFalloff(ifloat distance, ifloat radius)
{
    if (distance >= radius) return 0.0;

    ifloat normalized = distance / radius;
    return exp(-normalized * normalized * 4.0); // Smooth gaussian
}

// Quadratic falloff for force injection
ifloat QuadraticFalloff(ifloat distance, ifloat radius)
{
    if (distance >= radius) return 0.0;

    ifloat falloff = 1.0 - (distance / radius);
    return falloff * falloff;
}

// Convert pixel coordinates to UV
ifloat2 PixelToUV(iuint2 pixel, ifloat2 simSize)
{
    return (ifloat2(pixel) + 0.5) / simSize;
}

// Convert UV to pixel coordinates
iuint2 UVToPixel(ifloat2 uv, ifloat2 simSize)
{
    return iuint2(uv * simSize);
}

#endif // SIMULATION_COMMON_INCLUDED