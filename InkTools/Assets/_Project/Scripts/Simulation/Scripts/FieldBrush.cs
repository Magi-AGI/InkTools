using System.Collections.Generic;
using UnityEngine;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Generic field brush utility: paints into a target RT using a material pass.
    /// Intended for pressure/heat/velocity painting (similar to Powder Toy tools).
    /// </summary>
    [CreateAssetMenu(menuName = "InkTools/Simulation/Field Brush")]
    public class FieldBrush : ScriptableObject
    {
        [SerializeField] private Material paintMaterial;
        [SerializeField] private string centerParam = "_Center";
        [SerializeField] private string radiusParam = "_Radius";
        [SerializeField] private string strengthParam = "_Strength";
        [SerializeField] private string falloffParam = "_Falloff";
        [SerializeField] private float defaultRadius = 0.05f;
        [SerializeField] private float defaultStrength = 1f;
        [SerializeField] private float defaultFalloff = 2f;

        /// <summary>
        /// Paint a series of UV points into the target using the configured material.
        /// </summary>
        public void Paint(RenderTexture target, IReadOnlyList<Vector2> uvs, float strength = -1f, float radius = -1f, float falloff = -1f)
        {
            if (target == null || paintMaterial == null || uvs == null || uvs.Count == 0) return;

            float r = radius > 0 ? radius : defaultRadius;
            float s = strength > 0 ? strength : defaultStrength;
            float f = falloff > 0 ? falloff : defaultFalloff;

            var prev = RenderTexture.active;
            RenderTexture.active = target;

            foreach (var uv in uvs)
            {
                paintMaterial.SetVector(centerParam, new Vector4(uv.x, uv.y, 0, 0));
                paintMaterial.SetFloat(radiusParam, r);
                paintMaterial.SetFloat(strengthParam, s);
                paintMaterial.SetFloat(falloffParam, f);

                // Fullscreen blit; shader should discard outside radius
                Graphics.Blit(Texture2D.blackTexture, target, paintMaterial);
            }

            RenderTexture.active = prev;
        }
    }
}
