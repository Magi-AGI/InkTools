// Multi-resolution rendering for fluid simulation
// Allows running simulation at lower resolution while displaying at higher resolution

#ifndef MULTI_RESOLUTION_INCLUDED
#define MULTI_RESOLUTION_INCLUDED

#include "SimulationCommon.hlsl"

// Bilinear upsampling for display
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void UpsampleBilinear(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    ifloat2 displaySize = _SimParams.simulationSize * 2.0; // Example: 2x upsampling
    if (!IsValidPixel(id.xy, displaySize)) return;

    // Calculate UV in simulation space
    ifloat2 uv = ifloat2(id.xy) / displaySize;
    ifloat2 simCoord = uv * _SimParams.simulationSize;

    // Bilinear sampling
    ifloat4 value = SampleBilinear(_DensityRead, simCoord, _SimParams.simulationSize);

    _DensityWrite[id.xy] = value;
}

// Bicubic upsampling for smoother results
ifloat4 SampleBicubic(RWTexture2D<ifloat4> tex, ifloat2 coord, ifloat2 texSize)
{
    ifloat2 texelSize = 1.0 / texSize;
    ifloat2 p = coord - 0.5;
    ifloat2 f = frac(p);
    p = floor(p) + 0.5;

    // Catmull-Rom weights
    ifloat2 w0 = -0.5 * f * f * f + f * f - 0.5 * f;
    ifloat2 w1 = 1.5 * f * f * f - 2.5 * f * f + 1.0;
    ifloat2 w2 = -1.5 * f * f * f + 2.0 * f * f + 0.5 * f;
    ifloat2 w3 = 0.5 * f * f * f - 0.5 * f * f;

    // Sample 16 texels
    ifloat4 result = ifloat4(0, 0, 0, 0);
    for (int y = -1; y <= 2; y++)
    {
        for (int x = -1; x <= 2; x++)
        {
            ifloat2 samplePos = p + ifloat2(x, y);
            samplePos = clamp(samplePos, ifloat2(0, 0), texSize - 1);

            ifloat wx = (x == -1) ? w0.x : (x == 0) ? w1.x : (x == 1) ? w2.x : w3.x;
            ifloat wy = (y == -1) ? w0.y : (y == 0) ? w1.y : (y == 1) ? w2.y : w3.y;

            result += tex[iuint2(samplePos)] * wx * wy;
        }
    }

    return result;
}

// Downsampling with averaging (for hierarchical solvers)
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void DownsampleAverage(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    ifloat2 coarseSize = _SimParams.simulationSize * 0.5;
    if (!IsValidPixel(id.xy, coarseSize)) return;

    // Sample 2x2 block and average
    iuint2 fineCoord = id.xy * 2;
    ifloat4 value = ifloat4(0, 0, 0, 0);

    value += _QuantityRead[fineCoord];
    value += _QuantityRead[fineCoord + iuint2(1, 0)];
    value += _QuantityRead[fineCoord + iuint2(0, 1)];
    value += _QuantityRead[fineCoord + iuint2(1, 1)];

    _QuantityWrite[id.xy] = value * 0.25;
}

// Temporal upsampling with motion compensation
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void TemporalUpsample(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    ifloat2 displaySize = _SimParams.simulationSize * 2.0;
    if (!IsValidPixel(id.xy, displaySize)) return;

    // Current frame sample
    ifloat2 uv = ifloat2(id.xy) / displaySize;
    ifloat2 simCoord = uv * _SimParams.simulationSize;
    ifloat4 current = SampleBilinear(_DensityRead, simCoord, _SimParams.simulationSize);

    // Get velocity for motion compensation
    ifloat2 velocity = SampleBilinear(_VelocityRead, simCoord, _SimParams.simulationSize).xy;

    // Previous frame sample (motion compensated)
    ifloat2 prevCoord = ifloat2(id.xy) - velocity * _SimParams.deltaTime;
    prevCoord = clamp(prevCoord, ifloat2(0, 0), displaySize - 1);
    ifloat4 previous = _PressureRead[iuint2(prevCoord)]; // Using pressure buffer as temporal storage

    // Temporal blend with motion compensation
    ifloat blendFactor = 0.9; // High persistence for smooth results
    ifloat4 result = lerp(current, previous, blendFactor);

    _DensityWrite[id.xy] = result;
}

// LOD selection based on view distance
ifloat GetLODLevel(ifloat2 position, ifloat2 viewerPos, ifloat maxDistance)
{
    ifloat distance = length(position - viewerPos);
    ifloat lodLevel = saturate(distance / maxDistance) * 3.0; // 4 LOD levels
    return lodLevel;
}

// Adaptive resolution based on velocity magnitude
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void AdaptiveResolution(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    // Get local velocity magnitude
    ifloat2 velocity = _VelocityRead[id.xy].xy;
    ifloat speed = length(velocity);

    // Areas with high velocity need higher resolution
    ifloat resolutionScale = saturate(speed * 0.1) + 0.25; // 0.25 to 1.25 scale

    // Store resolution hint for adaptive solver
    _DivergenceWrite[id.xy] = resolutionScale; // Reuse divergence buffer as resolution map
}

#endif // MULTI_RESOLUTION_INCLUDED