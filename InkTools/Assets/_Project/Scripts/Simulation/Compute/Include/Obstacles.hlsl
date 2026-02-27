// Obstacle and boundary handling for fluid simulation

#ifndef OBSTACLES_INCLUDED
#define OBSTACLES_INCLUDED

#include "SimulationCommon.hlsl"

// Obstacle texture (0 = fluid, 1 = solid)
RWTexture2D<ifloat> _ObstacleRead;
RWTexture2D<ifloat> _ObstacleWrite;

// Create obstacle map from SDF or collision data
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void UpdateObstacles(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    // For now, just create boundary walls
    ifloat obstacle = 0.0;

    // Create walls at edges (with thickness)
    iuint wallThickness = 2;
    if (id.x < wallThickness || id.x >= (iuint)(_SimParams.simulationSize.x - wallThickness) ||
        id.y < wallThickness || id.y >= (iuint)(_SimParams.simulationSize.y - wallThickness))
    {
        obstacle = 1.0;
    }

    // Add circular obstacle in center (example)
    ifloat2 center = _SimParams.simulationSize * 0.5;
    ifloat radius = min(_SimParams.simulationSize.x, _SimParams.simulationSize.y) * 0.1;
    ifloat dist = length(ifloat2(id.xy) - center);
    if (dist < radius)
    {
        obstacle = 1.0;
    }

    _ObstacleWrite[id.xy] = obstacle;
}

// Apply obstacle boundary conditions to velocity
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void ApplyObstacleBoundary(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    ifloat obstacle = _ObstacleRead[id.xy];

    // If this cell is an obstacle, set velocity to zero
    if (obstacle > 0.5)
    {
        _VelocityWrite[id.xy] = ifloat4(0, 0, 0, 0);
        return;
    }

    // Check neighbors and enforce no-slip boundary
    ifloat2 velocity = _VelocityRead[id.xy].xy;

    // Left neighbor
    if (id.x > 0 && _ObstacleRead[iuint2(id.x - 1, id.y)] > 0.5)
    {
        velocity.x = max(velocity.x, 0.0); // No flow into obstacle
    }
    // Right neighbor
    if (id.x < (iuint)(_SimParams.simulationSize.x - 1) && _ObstacleRead[iuint2(id.x + 1, id.y)] > 0.5)
    {
        velocity.x = min(velocity.x, 0.0); // No flow into obstacle
    }
    // Bottom neighbor
    if (id.y > 0 && _ObstacleRead[iuint2(id.x, id.y - 1)] > 0.5)
    {
        velocity.y = max(velocity.y, 0.0); // No flow into obstacle
    }
    // Top neighbor
    if (id.y < (iuint)(_SimParams.simulationSize.y - 1) && _ObstacleRead[iuint2(id.x, id.y + 1)] > 0.5)
    {
        velocity.y = min(velocity.y, 0.0); // No flow into obstacle
    }

    _VelocityWrite[id.xy] = ifloat4(velocity, 0, 1);
}

// Helper function to check if position is inside obstacle
ifloat IsObstacle(iuint2 pos)
{
    if (pos.x >= (iuint)_SimParams.simulationSize.x || pos.y >= (iuint)_SimParams.simulationSize.y)
        return 1.0; // Outside bounds is treated as obstacle

    return _ObstacleRead[pos];
}

// Modified neighbor sampling that respects obstacles
NeighborSamples GetNeighborsWithObstacles(RWTexture2D<ifloat4> tex, iuint2 coord, ifloat2 simSize)
{
    NeighborSamples samples = GetNeighbors(tex, coord, simSize);

    // If neighbor is obstacle, use center value (no-slip)
    if (IsObstacle(iuint2(max(coord.x - 1, 0), coord.y)) > 0.5)
        samples.left = samples.center;
    if (IsObstacle(iuint2(min(coord.x + 1, simSize.x - 1), coord.y)) > 0.5)
        samples.right = samples.center;
    if (IsObstacle(iuint2(coord.x, max(coord.y - 1, 0))) > 0.5)
        samples.down = samples.center;
    if (IsObstacle(iuint2(coord.x, min(coord.y + 1, simSize.y - 1))) > 0.5)
        samples.up = samples.center;

    return samples;
}

// Per-ink obstacle thresholds (0 = not an obstacle ink, >0 = threshold)
float _ObstacleThresholdFire;
float _ObstacleThresholdWater;
float _ObstacleThresholdPlantSeeded;
float _ObstacleThresholdPlantGrown;
float _ObstacleThresholdSteam;
float _ObstacleThresholdGlitter;
float _ObstacleThresholdBlackBody;
float _ObstacleThresholdElectricitySeeded;
float _ObstacleThresholdElectricityGrown;
float _ObstacleThresholdIce;

// Generate obstacle mask from ink concentrations in particle buffer.
// Only writes 1.0 (additive with geometry obstacles). Never clears.
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void InkToObstacles(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    iuint idx = id.y * (iuint)_SimParams.simulationSize.x + id.x;
    iparticle p = _ParticlesRead[idx];

    // Check each ink against its obstacle threshold (0 = skip)
    if ((_ObstacleThresholdFire              > 0 && p.fire              >= _ObstacleThresholdFire) ||
        (_ObstacleThresholdWater             > 0 && p.water             >= _ObstacleThresholdWater) ||
        (_ObstacleThresholdPlantSeeded       > 0 && p.plantSeeded       >= _ObstacleThresholdPlantSeeded) ||
        (_ObstacleThresholdPlantGrown        > 0 && p.plantGrown        >= _ObstacleThresholdPlantGrown) ||
        (_ObstacleThresholdSteam             > 0 && p.steam             >= _ObstacleThresholdSteam) ||
        (_ObstacleThresholdGlitter           > 0 && p.glitter           >= _ObstacleThresholdGlitter) ||
        (_ObstacleThresholdBlackBody         > 0 && p.blackBody         >= _ObstacleThresholdBlackBody) ||
        (_ObstacleThresholdElectricitySeeded > 0 && p.electricitySeeded >= _ObstacleThresholdElectricitySeeded) ||
        (_ObstacleThresholdElectricityGrown  > 0 && p.electricityGrown  >= _ObstacleThresholdElectricityGrown) ||
        (_ObstacleThresholdIce               > 0 && p.ice              >= _ObstacleThresholdIce))
    {
        _ObstacleWrite[id.xy] = 1.0;
    }
}

#endif // OBSTACLES_INCLUDED