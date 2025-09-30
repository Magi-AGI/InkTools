using UnityEngine;
using Unity.Mathematics;

// The ifloat, idouble and other types are already defined as global usings in
// InkTools/Assets/_Project/Runtime/Simulation/Scripts/Types.cs

namespace InkTools.Simulation.Runtime
{

    /// <summary>
    /// Simulation parameters structure matching HLSL definition
    /// </summary>
    [System.Serializable]
    public struct SimulationParams
    {
        public float deltaTime;
        public float viscosity;
        public float dissipation;
        public float vorticityStrength;
        public Vector2 simulationSize;
        public float alpha;           // Jacobi parameter
        public float inverseBeta;     // Jacobi parameter

        public static SimulationParams Default => new SimulationParams
        {
            deltaTime = 0.016f,
            viscosity = 0.01f,
            dissipation = 0.98f,
            vorticityStrength = 2.0f,
            simulationSize = new Vector2(512, 512),
            alpha = 1.0f,
            inverseBeta = 0.25f
        };

        /// <summary>
        /// Calculate Jacobi parameters from viscosity and timestep
        /// </summary>
        public void CalculateJacobiParams(int resolution)
        {
            float dx = 1.0f / resolution;
            alpha = dx * dx / (viscosity * deltaTime);
            inverseBeta = 1.0f / (4.0f + alpha);
        }
    }

    /// <summary>
    /// Force injection parameters matching HLSL definition
    /// </summary>
    [System.Serializable]
    public struct ForceParams
    {
        public Vector2 position;
        public Vector2 direction;
        public float radius;
        public float strength;
        public float densityAmount;

        public static ForceParams Default => new ForceParams
        {
            position = new Vector2(256, 256),
            direction = new Vector2(1, 0),
            radius = 20.0f,
            strength = 5.0f,
            densityAmount = 1.0f
        };
    }

    /// <summary>
    /// Boundary condition types
    /// </summary>
    public enum BoundaryCondition
    {
        None = 0,
        NoSlip = 1,
        FreeSlip = 2
    }

    /// <summary>
    /// Kernel names for compute shader dispatch
    /// </summary>
    public static class FluidKernels
    {
        // Core simulation kernels
        public const string Advection = "Advection";
        public const string Diffusion = "Diffusion";
        public const string Divergence = "Divergence";
        public const string Pressure = "Pressure";
        public const string SubtractGradient = "SubtractGradient";
        public const string Vorticity = "Vorticity";
        public const string VorticityConfinement = "VorticityConfinement";
        public const string AddForce = "AddForce";
        public const string AddDensity = "AddDensity";
        public const string Clear = "Clear";

        // Advanced kernels
        public const string AdvectVelocity = "AdvectVelocity";
        public const string AdvectionMacCormack = "AdvectionMacCormack";
        public const string DiffuseQuantity = "DiffuseQuantity";
        public const string PressureRedBlack = "PressureRedBlack";
        public const string VorticityHelicity = "VorticityHelicity";
        public const string Buoyancy = "Buoyancy";
        public const string AddRadialForce = "AddRadialForce";
        public const string AddVortexForce = "AddVortexForce";
        public const string AddColoredSmoke = "AddColoredSmoke";
    }

    /// <summary>
    /// Compute shader property names
    /// </summary>
    public static class FluidProperties
    {
        // Textures
        public const string VelocityRead = "_VelocityRead";
        public const string VelocityWrite = "_VelocityWrite";
        public const string DensityRead = "_DensityRead";
        public const string DensityWrite = "_DensityWrite";
        public const string PressureRead = "_PressureRead";
        public const string PressureWrite = "_PressureWrite";
        public const string DivergenceRead = "_DivergenceRead";
        public const string DivergenceWrite = "_DivergenceWrite";
        public const string VorticityMag = "_VorticityMag";
        public const string QuantityRead = "_QuantityRead";
        public const string QuantityWrite = "_QuantityWrite";

        // Parameters
        public const string DeltaTime = "_DeltaTime";
        public const string Dissipation = "_Dissipation";
        public const string Viscosity = "_Viscosity";
        public const string VorticityStrength = "_VorticityStrength";
        public const string SimulationSize = "_SimulationSize";
        public const string Alpha = "_Alpha";
        public const string InverseBeta = "_InverseBeta";

        // Force parameters
        public const string ForcePosition = "_ForcePosition";
        public const string ForceDirection = "_ForceDirection";
        public const string ForceRadius = "_ForceRadius";
        public const string ForceStrength = "_ForceStrength";
        public const string DensityAmount = "_DensityAmount";
    }
}