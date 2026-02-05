using UnityEngine;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Optional ambient heat field: advects/diffuses a scalar heat texture with edge reset.
    /// Feature-flagged debug component.
    /// </summary>
    public class AmbientHeatSystem : MonoBehaviour
    {
        [SerializeField] private ComputeShader heatCompute;
        [SerializeField] private RenderTexture velocityTexture;
        [SerializeField] private RenderTexture heat;
        [SerializeField] private RenderTexture heatPrev;
        [SerializeField] private float advectionAmount = 0.7f;
        [SerializeField] private float diffusion = 0.02f;
        [SerializeField] private float edgeResetValue = 295.15f;
        [SerializeField] private bool run = false;

        private int kernel;

        private void OnEnable()
        {
            if (heatCompute == null)
            {
                Debug.LogWarning("AmbientHeatSystem: compute not set");
                enabled = false;
                return;
            }
            kernel = heatCompute.FindKernel("AdvectHeat");
        }

        private void Update()
        {
            if (!run || velocityTexture == null || heat == null || heatPrev == null) return;

            // ping-pong: copy current heat to heatPrev
            Graphics.Blit(heat, heatPrev);

            heatCompute.SetTexture(kernel, "_Velocity", velocityTexture);
            heatCompute.SetTexture(kernel, "_Heat", heat);
            heatCompute.SetTexture(kernel, "_HeatPrev", heatPrev);
            heatCompute.SetFloat("_DeltaTime", Time.deltaTime);
            heatCompute.SetFloat("_AdvectionAmount", advectionAmount);
            heatCompute.SetFloat("_Diffusion", diffusion);
            heatCompute.SetFloat("_EdgeResetValue", edgeResetValue);

            int gx = Mathf.CeilToInt(heat.width / 8f);
            int gy = Mathf.CeilToInt(heat.height / 8f);
            heatCompute.Dispatch(kernel, gx, gy, 1);
        }

        public void SetVelocityTexture(RenderTexture rt) => velocityTexture = rt;
    }
}
