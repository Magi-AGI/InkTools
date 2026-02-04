using UnityEngine;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Injects optical-flow-derived velocity into the simulation velocity RT.
    /// Designed as a reusable service: feed camera/video frames, get velocity output.
    /// </summary>
    public class OpticalFlowInjector : MonoBehaviour
    {
        [SerializeField] private ComputeShader opticalFlowCompute;
        [SerializeField] private RenderTexture sourceFrame;    // RGB input
        [SerializeField] private RenderTexture prevFrame;      // prior RGB input
        [SerializeField] private RenderTexture velocityInput;  // sim velocity (read)
        [SerializeField] private RenderTexture velocityOutput; // sim velocity (write)
        [SerializeField, Range(0f, 4f)] private float flowScale = 1f;
        [SerializeField, Range(0f, 1f)] private float flowThreshold = 0.01f;
        [SerializeField, Range(0f, 1f)] private float flowSmoothing = 0.2f;

        private int kExtract;
        private int kInject;
        private RenderTexture flowRT;

        private void OnEnable()
        {
            if (opticalFlowCompute == null)
            {
                Debug.LogWarning("OpticalFlowInjector: compute not set");
                enabled = false;
                return;
            }
            kExtract = opticalFlowCompute.FindKernel("ExtractVideoFlow");
            kInject = opticalFlowCompute.FindKernel("InjectOpticalFlow");
            AllocateFlowRT();
        }

        private void OnDisable()
        {
            Release(ref flowRT);
        }

        private void Update()
        {
            if (!InputsValid()) return;

            // Extract flow from current/prev frames into flowRT
            opticalFlowCompute.SetTexture(kExtract, "_VideoFrame", sourceFrame);
            opticalFlowCompute.SetTexture(kExtract, "_PrevFrame", prevFrame);
            opticalFlowCompute.SetTexture(kExtract, "_FlowInput", flowRT);
            Dispatch2D(kExtract, sourceFrame.width, sourceFrame.height);

            // Inject flow into velocity
            opticalFlowCompute.SetTexture(kInject, "_FlowInput", flowRT);
            opticalFlowCompute.SetTexture(kInject, "_VelocityRead", velocityInput);
            opticalFlowCompute.SetTexture(kInject, "_VelocityWrite", velocityOutput);
            opticalFlowCompute.SetFloat("_FlowScale", flowScale);
            opticalFlowCompute.SetFloat("_FlowThreshold", flowThreshold);
            opticalFlowCompute.SetFloat("_FlowSmoothing", flowSmoothing);
            Dispatch2D(kInject, velocityOutput.width, velocityOutput.height);
        }

        private bool InputsValid()
        {
            return sourceFrame != null && prevFrame != null && velocityInput != null && velocityOutput != null;
        }

        private void AllocateFlowRT()
        {
            Release(ref flowRT);
            if (sourceFrame == null) return;
            flowRT = new RenderTexture(sourceFrame.width, sourceFrame.height, 0, RenderTextureFormat.RGFloat)
            {
                enableRandomWrite = true,
                useMipMap = false,
                autoGenerateMips = false
            };
            flowRT.Create();
        }

        private void Dispatch2D(int kernel, int w, int h)
        {
            int tx = Mathf.CeilToInt(w / 8f);
            int ty = Mathf.CeilToInt(h / 8f);
            opticalFlowCompute.Dispatch(kernel, tx, ty, 1);
        }

        private void Release(ref RenderTexture rt)
        {
            if (rt != null)
            {
                rt.Release();
                Destroy(rt);
                rt = null;
            }
        }
    }
}
