using UnityEngine;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Renders a magnitude/threshold mask of the velocity field to a target RT for debug overlays.
    /// </summary>
    public class VelocityMaskRenderer : MonoBehaviour
    {
        [SerializeField] private ComputeShader maskCompute;
        [SerializeField] private RenderTexture velocityTexture;
        [SerializeField] private RenderTexture maskOutput;
        [SerializeField] private float threshold = 0.1f;
        [SerializeField] private bool render = true;

        private int kernel;

        private void OnEnable()
        {
            if (maskCompute == null)
            {
                Debug.LogWarning("VelocityMaskRenderer: compute not set");
                enabled = false;
                return;
            }
            kernel = maskCompute.FindKernel("Mask");
        }

        private void Update()
        {
            if (!render || velocityTexture == null || maskOutput == null) return;

            maskCompute.SetTexture(kernel, "_Velocity", velocityTexture);
            maskCompute.SetTexture(kernel, "_MaskOut", maskOutput);
            maskCompute.SetFloat("_Threshold", threshold);

            int gx = Mathf.CeilToInt(maskOutput.width / 8f);
            int gy = Mathf.CeilToInt(maskOutput.height / 8f);
            maskCompute.Dispatch(kernel, gx, gy, 1);
        }

        public void SetVelocityTexture(RenderTexture rt) => velocityTexture = rt;
    }
}
