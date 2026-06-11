// Optical flow integration for fluid simulation
// Allows injecting velocity from video/camera input

#ifndef OPTICAL_FLOW_INCLUDED
#define OPTICAL_FLOW_INCLUDED

#include "SimulationCommon.hlsl"

// Input textures for optical flow
RWTexture2D<ifloat4> _FlowInput;      // External optical flow data
RWTexture2D<ifloat4> _VideoFrame;     // Current video frame
RWTexture2D<ifloat4> _PrevFrame;      // Previous video frame

// Parameters
ifloat _FlowScale;                    // Scale factor for flow injection
ifloat _FlowThreshold;                 // Minimum flow magnitude to inject
ifloat _FlowSmoothing;                 // Temporal smoothing factor

// Lucas-Kanade optical flow calculation
ifloat2 CalculateLucasKanadeFlow(iuint2 coord, ifloat2 simSize)
{
    // Calculate image gradients
    ifloat4 center = _VideoFrame[coord];

    // Spatial derivatives (Sobel)
    ifloat4 dx = (_VideoFrame[coord + iuint2(1, 0)] - _VideoFrame[coord - iuint2(1, 0)]) * 0.5;
    ifloat4 dy = (_VideoFrame[coord + iuint2(0, 1)] - _VideoFrame[coord - iuint2(0, 1)]) * 0.5;

    // Temporal derivative
    ifloat4 dt = _VideoFrame[coord] - _PrevFrame[coord];

    // Use luminance for flow calculation
    ifloat Ix = dot(dx.rgb, ifloat3(0.299, 0.587, 0.114));
    ifloat Iy = dot(dy.rgb, ifloat3(0.299, 0.587, 0.114));
    ifloat It = dot(dt.rgb, ifloat3(0.299, 0.587, 0.114));

    // Window for Lucas-Kanade (3x3)
    ifloat sumIx2 = 0, sumIy2 = 0, sumIxIy = 0;
    ifloat sumIxIt = 0, sumIyIt = 0;

    for (int y = -1; y <= 1; y++)
    {
        for (int x = -1; x <= 1; x++)
        {
            iuint2 pos = coord + iuint2(x, y);
            pos = clamp(pos, iuint2(0, 0), iuint2(simSize) - 1);

            ifloat4 dx_local = (_VideoFrame[pos + iuint2(1, 0)] - _VideoFrame[pos - iuint2(1, 0)]) * 0.5;
            ifloat4 dy_local = (_VideoFrame[pos + iuint2(0, 1)] - _VideoFrame[pos - iuint2(0, 1)]) * 0.5;
            ifloat4 dt_local = _VideoFrame[pos] - _PrevFrame[pos];

            ifloat Ix_local = dot(dx_local.rgb, ifloat3(0.299, 0.587, 0.114));
            ifloat Iy_local = dot(dy_local.rgb, ifloat3(0.299, 0.587, 0.114));
            ifloat It_local = dot(dt_local.rgb, ifloat3(0.299, 0.587, 0.114));

            sumIx2 += Ix_local * Ix_local;
            sumIy2 += Iy_local * Iy_local;
            sumIxIy += Ix_local * Iy_local;
            sumIxIt += Ix_local * It_local;
            sumIyIt += Iy_local * It_local;
        }
    }

    // Solve linear system
    ifloat det = sumIx2 * sumIy2 - sumIxIy * sumIxIy;

    if (abs(det) < 0.001)
        return ifloat2(0, 0);

    ifloat2 flow;
    flow.x = (-sumIy2 * sumIxIt + sumIxIy * sumIyIt) / det;
    flow.y = (sumIxIy * sumIxIt - sumIx2 * sumIyIt) / det;

    return flow;
}

// Horn-Schunck optical flow (global smoothness)
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void OpticalFlowHornSchunck(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    // Calculate gradients
    ifloat4 center = _VideoFrame[id.xy];
    ifloat4 dx = (_VideoFrame[id.xy + iuint2(1, 0)] - _VideoFrame[id.xy - iuint2(1, 0)]) * 0.5;
    ifloat4 dy = (_VideoFrame[id.xy + iuint2(0, 1)] - _VideoFrame[id.xy - iuint2(0, 1)]) * 0.5;
    ifloat4 dt = _VideoFrame[id.xy] - _PrevFrame[id.xy];

    // Luminance gradients
    ifloat Ix = dot(dx.rgb, ifloat3(0.299, 0.587, 0.114));
    ifloat Iy = dot(dy.rgb, ifloat3(0.299, 0.587, 0.114));
    ifloat It = dot(dt.rgb, ifloat3(0.299, 0.587, 0.114));

    // Get average flow from neighbors
    ifloat2 avgFlow = ifloat2(0, 0);
    avgFlow += _FlowInput[id.xy + iuint2(1, 0)].xy;
    avgFlow += _FlowInput[id.xy - iuint2(1, 0)].xy;
    avgFlow += _FlowInput[id.xy + iuint2(0, 1)].xy;
    avgFlow += _FlowInput[id.xy - iuint2(0, 1)].xy;
    avgFlow *= 0.25;

    // Horn-Schunck iteration
    ifloat alpha = 1.0; // Smoothness weight
    ifloat denom = alpha * alpha + Ix * Ix + Iy * Iy;

    ifloat2 flow;
    flow.x = avgFlow.x - Ix * (Ix * avgFlow.x + Iy * avgFlow.y + It) / denom;
    flow.y = avgFlow.y - Iy * (Ix * avgFlow.x + Iy * avgFlow.y + It) / denom;

    _VelocityWrite[id.xy] = ifloat4(flow, 0, 1);
}

// Inject optical flow into fluid velocity
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void InjectOpticalFlow(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    // Get optical flow
    ifloat2 flow = _FlowInput[id.xy].xy;

    // Scale and threshold
    flow *= _FlowScale;
    ifloat flowMag = length(flow);

    if (flowMag < _FlowThreshold)
    {
        // Keep existing velocity
        _VelocityWrite[id.xy] = _VelocityRead[id.xy];
        return;
    }

    // Blend with existing velocity
    ifloat2 currentVel = _VelocityRead[id.xy].xy;
    ifloat2 newVel = lerp(currentVel, flow, _FlowSmoothing);

    _VelocityWrite[id.xy] = ifloat4(newVel, 0, 1);
}

// Extract flow from video difference
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void ExtractVideoFlow(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    // Simple frame difference for motion detection
    ifloat4 current = _VideoFrame[id.xy];
    ifloat4 previous = _PrevFrame[id.xy];

    // RGB difference
    ifloat3 diff = current.rgb - previous.rgb;

    // Convert to flow (simplified)
    ifloat2 flow = ifloat2(0, 0);

    // Check neighbors for motion direction
    ifloat3 leftDiff = _VideoFrame[id.xy - iuint2(1, 0)].rgb - _PrevFrame[id.xy - iuint2(1, 0)].rgb;
    ifloat3 rightDiff = _VideoFrame[id.xy + iuint2(1, 0)].rgb - _PrevFrame[id.xy + iuint2(1, 0)].rgb;
    ifloat3 upDiff = _VideoFrame[id.xy + iuint2(0, 1)].rgb - _PrevFrame[id.xy + iuint2(0, 1)].rgb;
    ifloat3 downDiff = _VideoFrame[id.xy - iuint2(0, 1)].rgb - _PrevFrame[id.xy - iuint2(0, 1)].rgb;

    // Estimate flow direction from difference pattern
    flow.x = dot(rightDiff - leftDiff, ifloat3(0.333, 0.333, 0.333));
    flow.y = dot(upDiff - downDiff, ifloat3(0.333, 0.333, 0.333));

    // Store flow
    _FlowInput[id.xy] = ifloat4(flow * 10.0, 0, 1); // Scale up for visibility
}

// Pyramidal Lucas-Kanade for large motions
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void PyramidalOpticalFlow(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    // Start with coarse flow estimate
    ifloat2 coarseFlow = _FlowInput[id.xy / 2].xy * 2.0; // Upsample from lower level

    // Refine with local Lucas-Kanade
    ifloat2 localFlow = CalculateLucasKanadeFlow(id.xy, _SimParams.simulationSize);

    // Combine coarse and fine
    ifloat2 flow = coarseFlow + localFlow;

    _VelocityWrite[id.xy] = ifloat4(flow, 0, 1);
}

// Dense optical flow using phase correlation
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void PhaseCorrelationFlow(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    // This would require FFT support which is complex in compute shaders
    // Simplified version using local correlation

    const int windowSize = 5;
    ifloat2 bestFlow = ifloat2(0, 0);
    ifloat bestCorr = -1.0;

    // Search window
    for (int dy = -2; dy <= 2; dy++)
    {
        for (int dx = -2; dx <= 2; dx++)
        {
            ifloat corr = 0.0;
            ifloat norm1 = 0.0;
            ifloat norm2 = 0.0;

            // Calculate correlation
            for (int wy = -windowSize/2; wy <= windowSize/2; wy++)
            {
                for (int wx = -windowSize/2; wx <= windowSize/2; wx++)
                {
                    iuint2 pos1 = id.xy + iuint2(wx, wy);
                    iuint2 pos2 = id.xy + iuint2(wx + dx, wy + dy);

                    pos1 = clamp(pos1, iuint2(0, 0), iuint2(_SimParams.simulationSize) - 1);
                    pos2 = clamp(pos2, iuint2(0, 0), iuint2(_SimParams.simulationSize) - 1);

                    ifloat val1 = dot(_PrevFrame[pos1].rgb, ifloat3(0.333, 0.333, 0.333));
                    ifloat val2 = dot(_VideoFrame[pos2].rgb, ifloat3(0.333, 0.333, 0.333));

                    corr += val1 * val2;
                    norm1 += val1 * val1;
                    norm2 += val2 * val2;
                }
            }

            // Normalize correlation
            if (norm1 > 0 && norm2 > 0)
            {
                corr = corr / sqrt(norm1 * norm2);

                if (corr > bestCorr)
                {
                    bestCorr = corr;
                    bestFlow = ifloat2(dx, dy);
                }
            }
        }
    }

    _VelocityWrite[id.xy] = ifloat4(bestFlow, 0, 1);
}

#endif // OPTICAL_FLOW_INCLUDED