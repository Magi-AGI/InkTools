using System.Collections.Generic;
using UnityEngine;

namespace Magi.InkTools.TestHelpers
{
    /// <summary>
    /// Test stub for ISimulationWriter. Tracks all calls for assertion.
    /// Plain C# class (no MonoBehaviour) for edit-mode tests.
    /// </summary>
    public class StubSimulationWriter : Simulation.ISimulationWriter
    {
        public struct ForceCall
        {
            public Vector2 Position;
            public Vector2 Force;
        }

        public struct DensityCall
        {
            public Vector2 Position;
            public Color Color;
            public int InkTypeIndex;
        }

        public struct StampCall
        {
            public Vector2 UvPosition;
            public Texture2D Stamp;
            public float DensityMultiplier;
            public bool UseColorOverride;
            public Color OverrideColor;
        }

        public struct ClearMaskCall
        {
            public Vector2 UvPosition;
            public Texture2D Mask;
            public float BlackLuminanceThreshold;
        }

        public struct ObstacleStampCall
        {
            public Vector2 UvPosition;
            public Texture2D Stamp;
        }

        public List<ForceCall> ForceInjections { get; } = new();
        public List<DensityCall> DensityInjections { get; } = new();
        public List<StampCall> DensityStamps { get; } = new();
        public List<ClearMaskCall> ClearMasks { get; } = new();
        public List<ObstacleStampCall> ObstacleStamps { get; } = new();

        public int TotalCalls => ForceInjections.Count + DensityInjections.Count +
                                 DensityStamps.Count + ClearMasks.Count + ObstacleStamps.Count;

        public void InjectForce(Vector2 position, Vector2 force)
            => ForceInjections.Add(new ForceCall { Position = position, Force = force });

        public void InjectDensity(Vector2 position, Color color, int inkTypeIndex = 0)
            => DensityInjections.Add(new DensityCall { Position = position, Color = color, InkTypeIndex = inkTypeIndex });

        public void StampDensity(Vector2 uvPosition, Texture2D stamp, float densityMultiplier,
            bool useColorOverride, Color overrideColor)
            => DensityStamps.Add(new StampCall
            {
                UvPosition = uvPosition, Stamp = stamp, DensityMultiplier = densityMultiplier,
                UseColorOverride = useColorOverride, OverrideColor = overrideColor
            });

        public void ClearDensityWithMask(Vector2 uvPosition, Texture2D mask, float blackLuminanceThreshold = 0.2f)
            => ClearMasks.Add(new ClearMaskCall
            {
                UvPosition = uvPosition, Mask = mask, BlackLuminanceThreshold = blackLuminanceThreshold
            });

        public void StampObstacles(Vector2 uvPosition, Texture2D stamp)
            => ObstacleStamps.Add(new ObstacleStampCall { UvPosition = uvPosition, Stamp = stamp });

        public void Reset()
        {
            ForceInjections.Clear();
            DensityInjections.Clear();
            DensityStamps.Clear();
            ClearMasks.Clear();
            ObstacleStamps.Clear();
        }
    }
}
