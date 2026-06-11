using UnityEngine;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Produces current/previous frames from a Camera for optical flow injection.
    /// Optionally re-renders the camera each LateUpdate if captureOnUpdate is enabled.
    /// </summary>
    [DefaultExecutionOrder(-10)]
    public class OpticalFlowCameraSource : MonoBehaviour
    {
        [SerializeField] private Camera sourceCamera;
        [SerializeField] private Vector2Int resolution = new(512, 512);
        [SerializeField] private RenderTextureFormat format = RenderTextureFormat.ARGB32;
        [SerializeField] private bool captureOnUpdate = true;

        private RenderTexture currentRT;
        private RenderTexture previousRT;

        public RenderTexture Current => currentRT;
        public RenderTexture Previous => previousRT;

        private void Awake()
        {
            if (sourceCamera == null)
                sourceCamera = Camera.main;
            AllocateRTs();
            if (sourceCamera != null)
                sourceCamera.targetTexture = currentRT;
        }

        private void OnDisable()
        {
            Release(ref currentRT);
            Release(ref previousRT);
            if (sourceCamera != null && sourceCamera.targetTexture == currentRT)
                sourceCamera.targetTexture = null;
        }

        private void LateUpdate()
        {
            if (sourceCamera == null || currentRT == null || previousRT == null) return;

            if (captureOnUpdate)
            {
                // Swap current into previous, then render into current.
                Graphics.Blit(currentRT, previousRT);
                sourceCamera.Render();
            }
        }

        private void AllocateRTs()
        {
            Release(ref currentRT);
            Release(ref previousRT);
            currentRT = CreateRT(resolution.x, resolution.y, format);
            previousRT = CreateRT(resolution.x, resolution.y, format);
        }

        private RenderTexture CreateRT(int w, int h, RenderTextureFormat fmt)
        {
            var rt = new RenderTexture(w, h, 0, fmt)
            {
                enableRandomWrite = false,
                useMipMap = false,
                autoGenerateMips = false
            };
            rt.Create();
            return rt;
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
