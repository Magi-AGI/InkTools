// Pressure projection to enforce incompressible flow

#ifndef PRESSURE_PROJECTION_INCLUDED
#define PRESSURE_PROJECTION_INCLUDED

#include "SimulationCommon.hlsl"

// Textures are declared in main Fluids.compute

// Calculate divergence of velocity field
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void Divergence(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    // Get velocity samples
    NeighborSamples vel = GetNeighbors(_VelocityRead, id.xy, _SimParams.simulationSize);

    // Apply boundary conditions (no flow through walls)
    if (id.x == 0) vel.left.x = -vel.right.x;
    if (id.x >= (iuint)(_SimParams.simulationSize.x - 1)) vel.right.x = -vel.left.x;
    if (id.y == 0) vel.down.y = -vel.up.y;
    if (id.y >= (iuint)(_SimParams.simulationSize.y - 1)) vel.up.y = -vel.down.y;

    // Calculate divergence: div = ∂u/∂x + ∂v/∂y
    ifloat divergence = ((vel.right.x - vel.left.x) + (vel.up.y - vel.down.y)) * 0.5;

    _DivergenceWrite[id.xy] = divergence;
}

// Pressure solver using Jacobi iteration
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void Pressure(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    // Read divergence
    ifloat divergence = _DivergenceRead[id.xy];

    // Get pressure samples
    NeighborSamples pressure = GetNeighbors(_PressureRead, id.xy, _SimParams.simulationSize);

    // Boundary conditions (pressure at walls)
    if (id.x == 0) pressure.left = pressure.right;
    if (id.x >= (iuint)(_SimParams.simulationSize.x - 1)) pressure.right = pressure.left;
    if (id.y == 0) pressure.down = pressure.up;
    if (id.y >= (iuint)(_SimParams.simulationSize.y - 1)) pressure.up = pressure.down;

    // Jacobi iteration for Poisson equation
    ifloat newPressure = (pressure.left.x + pressure.right.x +
                         pressure.down.x + pressure.up.x - divergence) * 0.25;

    _PressureWrite[id.xy] = ifloat4(newPressure, 0, 0, 1);
}

// Subtract pressure gradient from velocity to make it divergence-free
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void SubtractGradient(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    // Get pressure samples
    NeighborSamples pressure = GetNeighbors(_PressureRead, id.xy, _SimParams.simulationSize);

    // Calculate pressure gradient
    ifloat2 gradient = ifloat2(
        pressure.right.x - pressure.left.x,
        pressure.up.x - pressure.down.x
    ) * 0.5;

    // Subtract gradient from velocity
    ifloat2 velocity = _VelocityRead[id.xy].xy;
    velocity -= gradient;

    // Don't apply boundary conditions here - they're already handled in divergence
    // Applying them twice causes artifacts
    // velocity = ApplyVelocityBoundary(velocity, id.xy, _SimParams.simulationSize, BOUNDARY_NO_SLIP);

    _VelocityWrite[id.xy] = ifloat4(velocity, 0, 1);
}

// Red-Black Gauss-Seidel for faster convergence
// This converges roughly 2x faster than Jacobi iteration
[numthreads(THREAD_GROUP_SIZE, THREAD_GROUP_SIZE, 1)]
void PressureRedBlack(iuint3 id : SV_DispatchThreadID)
{
    INIT_PARAMS

    if (!IsValidPixel(id.xy, _SimParams.simulationSize)) return;

    // Check if this is a red or black cell
    iuint checkerboard = (id.x + id.y) & 1;

    // Use a parameter to select red (0) or black (1) cells
    // This should be set from C# before dispatching
    iuint colorPass = iuint(_SimParams.alpha); // Repurpose alpha as color selector
    if (checkerboard != colorPass) return;

    ifloat divergence = _DivergenceRead[id.xy];

    // For Red-Black, we read and write to the same texture
    // Red cells update first, then black cells see the updated red values
    NeighborSamples pressure = GetNeighbors(_PressureRead, id.xy, _SimParams.simulationSize);

    // Boundary conditions
    if (id.x == 0) pressure.left = pressure.right;
    if (id.x >= (iuint)(_SimParams.simulationSize.x - 1)) pressure.right = pressure.left;
    if (id.y == 0) pressure.down = pressure.up;
    if (id.y >= (iuint)(_SimParams.simulationSize.y - 1)) pressure.up = pressure.down;

    // Gauss-Seidel update (in-place)
    ifloat newPressure = (pressure.left.x + pressure.right.x +
                         pressure.down.x + pressure.up.x - divergence) * 0.25;

    // Write directly back to read buffer for Gauss-Seidel
    _PressureRead[id.xy] = ifloat4(newPressure, 0, 0, 1);
}

#endif // PRESSURE_PROJECTION_INCLUDED