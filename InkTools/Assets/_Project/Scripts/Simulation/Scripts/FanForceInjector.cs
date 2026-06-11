using UnityEngine;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Adds a radial fan force into the velocity texture each frame.
    /// </summary>
    public class FanForceInjector : MonoBehaviour
    {
        [SerializeField] private ComputeShader fanCompute;
        [SerializeField] private RenderTexture velocityTexture;
        [SerializeField] private Vector2 centerUV = new(0.5f, 0.5f);
        [SerializeField] private Vector2 force = new(0f, 0.02f);
        [SerializeField] private float radius = 0.1f;
        [SerializeField] private float falloff = 2f;
        [SerializeField] private bool apply = true;

        private int kernel;

        private void OnEnable()
        {
            if (fanCompute == null)
            {
                Debug.LogWarning("FanForceInjector: compute not set");
                enabled = false;
                return;
            }
            kernel = fanCompute.FindKernel("AddFan");
        }

        private void Update()
        {
            if (!apply || velocityTexture == null) return;

            fanCompute.SetTexture(kernel, "_Velocity", velocityTexture);
            fanCompute.SetFloats("_Center", centerUV.x, centerUV.y);
            fanCompute.SetFloats("_Force", force.x, force.y);
            fanCompute.SetFloat("_Radius", radius);
            fanCompute.SetFloat("_Falloff", falloff);

            int gx = Mathf.CeilToInt(velocityTexture.width / 8f);
            int gy = Mathf.CeilToInt(velocityTexture.height / 8f);
            fanCompute.Dispatch(kernel, gx, gy, 1);
        }

        public void SetVelocityTexture(RenderTexture rt) => velocityTexture = rt;
    }
}
