using UnityEngine;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Renders a velocity field as arrows using DrawProcedural. Debug/inspection only.
    /// </summary>
    public class VelocityArrowsRenderer : MonoBehaviour
    {
        [SerializeField] private Material arrowsMaterial;
        [SerializeField] private RenderTexture velocityTexture;
        [SerializeField] private float gridStepPixels = 16f;
        [SerializeField] private float arrowScale = 0.05f;
        [SerializeField] private Color color = Color.white;
        [SerializeField] private bool render = true;

        public void SetVelocityTexture(RenderTexture rt) => velocityTexture = rt;

        private void OnRenderObject()
        {
            if (!render || arrowsMaterial == null || velocityTexture == null) return;

            arrowsMaterial.SetTexture("_VelTex", velocityTexture);
            arrowsMaterial.SetFloat("_GridStep", gridStepPixels);
            arrowsMaterial.SetFloat("_Scale", arrowScale);
            arrowsMaterial.SetColor("_Color", color);

            // Compute instance count based on grid
            int cols = Mathf.Max(1, Mathf.FloorToInt(velocityTexture.width / gridStepPixels));
            int rows = Mathf.Max(1, Mathf.FloorToInt(velocityTexture.height / gridStepPixels));
            int count = cols * rows;

            arrowsMaterial.SetPass(0);
            Graphics.DrawProceduralNow(MeshTopology.Points, count, 1);
        }
    }
}
