# InkTools

GPU-accelerated fluid simulation and cellular automata Unity Package (UPM) providing core simulation systems for ink-based interactions.

## Overview

InkTools provides high-performance, non-game-specific simulation components that power the Inkling ecosystem. Built as a Unity Package Manager (UPM) compatible library, it offers reusable fluid dynamics and cellular automata systems.

## Package Structure

### com.inktools.sim

GPU fluids and cellular automata with compute shaders and C# bindings.

```
Packages/
└── com.inktools.sim/
    ├── package.json                  # Package manifest
    ├── Runtime/
    │   ├── Compute/                  # Compute shader infrastructure
    │   │   ├── FluidSolver.compute   # Navier-Stokes fluid solver
    │   │   ├── CellularAutomata.compute
    │   │   └── Common.hlsl           # Shared HLSL definitions
    │   └── Simulation/               # C# simulation framework
    │       ├── FluidSimulation.cs
    │       ├── CASystem.cs
    │       ├── MaterialProperties.cs
    │       └── ParticleData.cs
    └── Editor/
        └── Debug/                    # Editor debugging tools
            ├── SimulationDebugger.cs
            └── PerformanceProfiler.cs
```

## Features

### Fluid Dynamics
- **Stable Fluid Solver**: Jos Stam's algorithm adapted for GPU
- **Multi-Material Support**: Different ink types with unique properties
- **Deterministic Simulation**: Reproducible results with fixed seeds
- **Resolution Scaling**: Adaptive quality from 256x256 to 2048x2048

### Cellular Automata
- **5-Layer System**: Chemistry, Metabolism, Structure, Information, Evolution
- **GPU Parallel Updates**: Compute shader based processing
- **Rule Customization**: JSON-based rule configuration
- **State Serialization**: Save/load simulation states

### Cross-Platform Types
Unified data types for C#/HLSL interoperability:
- `ifloat` (16-bit float)
- `idouble` (32-bit float)
- `ishort` (16-bit unsigned)

## Installation

### Via Unity Package Manager

1. Open Package Manager in Unity
2. Click "+" → "Add package from disk..."
3. Navigate to `InkTools/Packages/com.inktools.sim/package.json`

### Via manifest.json

Add to your project's `Packages/manifest.json`:

```json
{
  "dependencies": {
    "com.inktools.sim": "file:../../InkTools/Packages/com.inktools.sim"
  }
}
```

### Via MagiUnityDependencyManager

Add to your `depfile.yaml`:

```yaml
packages:
  - name: com.inktools.sim
    path: ../InkTools/Packages/com.inktools.sim
```

## Usage Examples

### Basic Fluid Simulation

```csharp
using InkTools.Sim;

public class FluidDemo : MonoBehaviour
{
    private FluidSimulation fluid;

    void Start()
    {
        var config = new FluidConfig
        {
            Resolution = 512,
            Viscosity = 0.0001f,
            Diffusion = 0.00001f
        };

        fluid = new FluidSimulation(config);
        fluid.Initialize();
    }

    void Update()
    {
        fluid.AddVelocity(Input.mousePosition, Vector2.up * 100);
        fluid.Step(Time.deltaTime);
    }
}
```

### Cellular Automata Integration

```csharp
using InkTools.Sim.CA;

public class CADemo : MonoBehaviour
{
    private CASystem automata;

    void Start()
    {
        automata = new CASystem(256, 256);
        automata.LoadRules("biochemical_rules.json");
        automata.Initialize();
    }

    void FixedUpdate()
    {
        automata.Update();
    }
}
```

## Performance

### Target Specifications
- **Simulation Budget**: < 4ms per frame
- **Memory Usage**: < 100MB GPU memory
- **Platform Support**: Mobile (iOS/Android), Desktop, WebGPU

### Optimization Features
- Adaptive resolution based on device capabilities
- Compute shader LOD system
- Temporal caching for static regions
- Async GPU readback for data export

## API Reference

### Core Classes

#### FluidSimulation
Main fluid dynamics controller.

```csharp
public class FluidSimulation
{
    public void Initialize();
    public void Step(float deltaTime);
    public void AddVelocity(Vector2 position, Vector2 force);
    public void AddDensity(Vector2 position, float amount, MaterialType type);
    public RenderTexture GetDensityTexture();
    public RenderTexture GetVelocityTexture();
}
```

#### CASystem
Cellular automata engine.

```csharp
public class CASystem
{
    public void Initialize();
    public void Update();
    public void SetCell(int x, int y, CellState state);
    public CellState GetCell(int x, int y);
    public void LoadRules(string rulesPath);
}
```

## Development

### Requirements
- Unity 2022.3 LTS or newer
- Compute shader support (SM 5.0+)
- Git LFS for binary assets

### Testing

Run tests via Unity Test Runner:
```
Window → General → Test Runner → Run All
```

### Debugging

Enable debug overlays in Editor:
```csharp
InkToolsDebug.EnableOverlay = true;
InkToolsDebug.ShowPerformanceStats = true;
```

## Integration with Inkling

InkTools provides the foundational simulation layer (LOD 0) for Inkling:

1. **Data Generation**: Export simulation textures for ML training
2. **Deterministic Replay**: Reproducible simulations for dataset creation
3. **Performance Scaling**: Automatic quality adjustment per device
4. **Shader Variants**: Multiple rendering paths for different tiers

## Related Projects

- **[Inkling](../Inkling)**: Main game implementation
- **[InkModel](../InkModel)**: ML training pipeline
- **[MagiUnityTools](../MagiUnityTools)**: Shared Unity utilities
- **[MagiUnityDependencyManager](../MagiUnityDependencyManager)**: Package management

## References

- Jos Stam's "Stable Fluids" (SIGGRAPH 1999)
- GPU Gems fluid dynamics chapters
- Unity Compute Shader documentation

## License

See [LICENSE](LICENSE) for details.

