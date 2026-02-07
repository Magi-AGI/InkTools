using UnityEngine;

namespace Magi.InkTools.TestHelpers
{
    /// <summary>
    /// Test stub for ISimulationReader. All properties are configurable via public setters.
    /// Plain C# class (no MonoBehaviour) for edit-mode tests.
    /// </summary>
    public class StubSimulationReader : Simulation.ISimulationReader
    {
        public int Resolution { get; set; } = 256;
        public float Timestep { get; set; } = 0.016f;
        public float Viscosity { get; set; } = 0.0001f;
        public float Vorticity { get; set; } = 5f;
        public float Dissipation { get; set; } = 0.999f;
        public float VelocityDissipation { get; set; } = 0.99f;

        public RenderTexture DensityTexture { get; set; }
        public RenderTexture VelocityTexture { get; set; }
        public RenderTexture DisplayTexture { get; set; }
        public RenderTexture ObstacleTexture { get; set; }
        public ComputeBuffer ParticleBuffer { get; set; }

        public float LastFrameMs { get; set; }
        public (float advection, float diffusion, float pressure, float projection, float vorticity) DetailedTimings { get; set; }

        public RenderTexture GetDensityTexture() => DensityTexture;
        public RenderTexture GetVelocityTexture() => VelocityTexture;
        public RenderTexture GetDisplayTexture() => DisplayTexture;
        public RenderTexture GetObstacleTexture() => ObstacleTexture;
        public ComputeBuffer GetParticleBuffer() => ParticleBuffer;
        public float GetLastFrameMs() => LastFrameMs;

        public (float advection, float diffusion, float pressure, float projection, float vorticity)
            GetDetailedTimings() => DetailedTimings;
    }
}
