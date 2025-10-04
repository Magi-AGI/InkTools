// Unified type definitions for consistency between C# and HLSL
// Includes the existing InkTools type definitions

#ifndef SIMULATION_TYPES_INCLUDED
#define SIMULATION_TYPES_INCLUDED

// Include the existing InkTools type definitions
#include "../../../FluidTools/Simulation/Compute/InkToolsTypes.hlsl"

// Additional integer type aliases for consistency
#define iint int
#define iint2 int2
#define iint3 int3
#define iint4 int4

#define iuint uint
#define iuint2 uint2
#define iuint3 uint3
#define iuint4 uint4

// Simulation-specific structures
struct SimulationParams
{
    ifloat deltaTime;
    ifloat viscosity;
    ifloat dissipation;
    ifloat vorticityStrength;
    ifloat2 simulationSize;
    ifloat alpha;           // Jacobi parameter
    ifloat inverseBeta;     // Jacobi parameter
};

struct ForceParams
{
    ifloat2 position;
    ifloat2 direction;
    ifloat radius;
    ifloat strength;
    ifloat densityAmount;
};

// Common texture declarations
#define DECLARE_VELOCITY_TEXTURES \
    RWTexture2D<ifloat4> _VelocityRead; \
    RWTexture2D<ifloat4> _VelocityWrite;

#define DECLARE_DENSITY_TEXTURES \
    RWTexture2D<ifloat4> _DensityRead; \
    RWTexture2D<ifloat4> _DensityWrite;

#define DECLARE_PRESSURE_TEXTURES \
    RWTexture2D<ifloat4> _PressureRead; \
    RWTexture2D<ifloat4> _PressureWrite;

#define DECLARE_SCALAR_TEXTURES \
    RWTexture2D<ifloat> _DivergenceRead; \
    RWTexture2D<ifloat> _DivergenceWrite; \
    RWTexture2D<ifloat> _VorticityMag;

// Thread group size constant
#define THREAD_GROUP_SIZE 8

// Boundary condition types
#define BOUNDARY_NONE 0
#define BOUNDARY_NO_SLIP 1
#define BOUNDARY_FREE_SLIP 2

#endif // SIMULATION_TYPES_INCLUDED
