using UnityEngine;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Renders divergence (R) and curl (G) of velocity into a target RT for debug overlays.
    /// </summary>
    public class SplitVelocityRenderer : MonoBehaviour
    {
        [SerializeField] private ComputeShader splitCompute;
        [SerializeField] private RenderTexture velocityTexture;
        [SerializeField] private RenderTexture output;
        [SerializeField] private bool render = true;

        private int kernel;
        public RenderTexture Output => output;

        private void OnEnable()
        {
            if (splitCompute == null)
            {
                Debug.LogWarning("SplitVelocityRenderer: compute not set");
                enabled = false;
                return;
            }
            kernel = splitCompute.FindKernel("Split");
        }

        private void Update()
        {
            if (!render || velocityTexture == null || output == null) return;

            splitCompute.SetTexture(kernel, "_Velocity", velocityTexture);
            splitCompute.SetTexture(kernel, "_Out", output);

            int gx = Mathf.CeilToInt(output.width / 8f);
            int gy = Mathf.CeilToInt(output.height / 8f);
            splitCompute.Dispatch(kernel, gx, gy, 1);
        }

        public void SetVelocityTexture(RenderTexture rt) => velocityTexture = rt;
    }
}
