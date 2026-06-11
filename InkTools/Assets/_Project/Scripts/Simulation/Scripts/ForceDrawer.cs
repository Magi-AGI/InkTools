using System.Collections.Generic;
using UnityEngine;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Shared utility to paint force/density into a RenderTexture from stroke samples.
    /// Intended for reuse by tools (e.g., BrushInputManager) and AI/cutscenes.
    /// Uses additive blending via DrawForce2D shader; best for low sample counts.
    /// </summary>
    [CreateAssetMenu(menuName = "InkTools/Simulation/Force Drawer")]
    public class ForceDrawer : ScriptableObject
    {
        [SerializeField] private Material drawMaterial;
        [SerializeField] private float defaultRadius = 0.05f;
        [SerializeField] private float defaultStrength = 1f;
        [SerializeField] private float defaultFalloff = 2f;

        public void DrawStroke(RenderTexture target, IReadOnlyList<Vector2> stroke, Vector2 forceDir)
        {
            if (target == null || drawMaterial == null || stroke == null || stroke.Count == 0) return;
            var prev = RenderTexture.active;
            RenderTexture.active = target;
            foreach (var uv in stroke)
            {
                DrawPoint(target, uv, forceDir, defaultRadius, defaultStrength, defaultFalloff);
            }
            RenderTexture.active = prev;
        }

        public void DrawPoint(RenderTexture target, Vector2 uv, Vector2 force, float radius, float strength, float falloff)
        {
            if (target == null || drawMaterial == null) return;
            drawMaterial.SetVector("_Center", new Vector4(uv.x, uv.y, 0, 0));
            drawMaterial.SetFloat("_Radius", radius);
            drawMaterial.SetFloat("_Strength", strength);
            drawMaterial.SetVector("_Force", new Vector4(force.x, force.y, 0, 0));
            drawMaterial.SetFloat("_Falloff", falloff);

            // Fullscreen quad; shader discards outside radius. Acceptable for low N.
            Graphics.Blit(Texture2D.blackTexture, target, drawMaterial);
        }
    }
}
