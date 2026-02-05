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
        [Header("Inputs")]
        [SerializeField] private RenderTexture sourceFrame;    // RGB input
        [SerializeField] private RenderTexture prevFrame;      // prior RGB input
        [SerializeField] private RenderTexture velocityInput;  // sim velocity (read)
        [SerializeField] private RenderTexture velocityOutput; // sim velocity (write)
        [SerializeField] private bool autoCopySourceToPrev = true;
        [SerializeField] private int downsample = 1; // 1 = full res, 2 = half, etc.
        [SerializeField, Range(0f, 4f)] private float flowScale = 1f;
        [SerializeField, Range(0f, 1f)] private float flowThreshold = 0.01f;
        [SerializeField, Range(0f, 1f)] private float flowSmoothing = 0.2f;

        private int kExtract;
        private int kInject;
        private RenderTexture flowRT;
        private RenderTexture downsampledSrc;
        private RenderTexture downsampledPrev;

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
            AllocateRTs();
        }

        private void OnDisable()
        {
            Release(ref flowRT);
            Release(ref downsampledSrc);
            Release(ref downsampledPrev);
        }

        private void Update()
        {
            if (!InputsValid()) return;

            EnsureRTs();

            // Optional downsample for speed
            var src = DownsampleIfNeeded(sourceFrame, ref downsampledSrc);
            var prev = DownsampleIfNeeded(prevFrame, ref downsampledPrev);

            // Extract flow from current/prev frames into flowRT
            opticalFlowCompute.SetTexture(kExtract, "_VideoFrame", src);
            opticalFlowCompute.SetTexture(kExtract, "_PrevFrame", prev);
            opticalFlowCompute.SetTexture(kExtract, "_FlowInput", flowRT);
            Dispatch2D(kExtract, flowRT.width, flowRT.height);

            // Inject flow into velocity
            opticalFlowCompute.SetTexture(kInject, "_FlowInput", flowRT);
            opticalFlowCompute.SetTexture(kInject, "_VelocityRead", velocityInput);
            opticalFlowCompute.SetTexture(kInject, "_VelocityWrite", velocityOutput);
            opticalFlowCompute.SetFloat("_FlowScale", flowScale);
            opticalFlowCompute.SetFloat("_FlowThreshold", flowThreshold);
            opticalFlowCompute.SetFloat("_FlowSmoothing", flowSmoothing);
            Dispatch2D(kInject, velocityOutput.width, velocityOutput.height);

            if (autoCopySourceToPrev)
            {
                Graphics.Blit(sourceFrame, prevFrame);
            }
        }

        private bool InputsValid()
        {
            return sourceFrame != null && prevFrame != null && velocityInput != null && velocityOutput != null;
        }

        private void AllocateRTs()
        {
            Release(ref flowRT);
            Release(ref downsampledSrc);
            Release(ref downsampledPrev);
            if (sourceFrame == null) return;

            int w = Mathf.Max(1, sourceFrame.width / Mathf.Max(1, downsample));
            int h = Mathf.Max(1, sourceFrame.height / Mathf.Max(1, downsample));

            flowRT = CreateRT(w, h, RenderTextureFormat.RGFloat);
            downsampledSrc = CreateRT(w, h, sourceFrame.format);
            downsampledPrev = CreateRT(w, h, prevFrame != null ? prevFrame.format : sourceFrame.format);
        }

        private RenderTexture DownsampleIfNeeded(RenderTexture src, ref RenderTexture dst)
        {
            if (dst == null || flowRT == null || dst.width != flowRT.width || dst.height != flowRT.height)
            {
                Release(ref dst);
                if (flowRT == null) return null;
                dst = CreateRT(flowRT.width, flowRT.height, src.format);
            }
            Graphics.Blit(src, dst);
            return dst;
        }

        private RenderTexture CreateRT(int w, int h, RenderTextureFormat fmt)
        {
            var rt = new RenderTexture(w, h, 0, fmt)
            {
                enableRandomWrite = true,
                useMipMap = false,
                autoGenerateMips = false
            };
            rt.Create();
            return rt;
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
