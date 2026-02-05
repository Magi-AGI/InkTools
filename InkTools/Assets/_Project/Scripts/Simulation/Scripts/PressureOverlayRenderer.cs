using UnityEngine;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Copies pressure (assumed packed in velocity.z) to a debug RT.
    /// </summary>
    public class PressureOverlayRenderer : MonoBehaviour
    {
        [SerializeField] private ComputeShader pressureCompute;
        [SerializeField] private RenderTexture velocityTexture;
        [SerializeField] private RenderTexture output;
        [SerializeField] private bool render = true;

        private int kernel;
        public RenderTexture Output => output;

        private void OnEnable()
        {
            if (pressureCompute == null)
            {
                Debug.LogWarning("PressureOverlayRenderer: compute not set");
                enabled = false;
                return;
            }
            kernel = pressureCompute.FindKernel("CopyPressure");
        }

        private void Update()
        {
            if (!render || velocityTexture == null || output == null) return;
            pressureCompute.SetTexture(kernel, "_Velocity", velocityTexture);
            pressureCompute.SetTexture(kernel, "_Out", output);

            int gx = Mathf.CeilToInt(output.width / 8f);
            int gy = Mathf.CeilToInt(output.height / 8f);
            pressureCompute.Dispatch(kernel, gx, gy, 1);
        }

        public void SetVelocityTexture(RenderTexture rt) => velocityTexture = rt;
    }
}
