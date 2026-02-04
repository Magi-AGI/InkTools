using System;
using System.Collections;
using UnityEngine;
using UnityEngine.Rendering;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// GPU reduction of velocity field to average velocity/speed. Avoids per-frame CPU readbacks.
    /// </summary>
    public class VelocityStatsSystem : MonoBehaviour
    {
        [SerializeField] private ComputeShader statsCompute;
        [SerializeField] private RenderTexture velocityTexture;
        [SerializeField] private Vector2Int reduceSize = new(16, 16);

        public Vector2 AverageVelocity { get; private set; }
        public float AverageSpeed { get; private set; }

        private RenderTexture tempReduce;
        private RenderTexture tempFinal;
        private int kernelDownsample;
        private AsyncGPUReadbackRequest pending;

        private void OnEnable()
        {
            if (statsCompute == null)
            {
                Debug.LogWarning("VelocityStatsSystem: statsCompute not set.");
                enabled = false;
                return;
            }
            kernelDownsample = statsCompute.FindKernel("Downsample");
            AllocateRTs();
        }

        private void OnDisable()
        {
            ReleaseRT(ref tempReduce);
            ReleaseRT(ref tempFinal);
        }

        private void LateUpdate()
        {
            if (velocityTexture == null) return;
            if (pending.valid && !pending.done) return; // keep one in flight

            EnsureRTs();
            // Pass 1: velocity -> tempReduce
            DispatchDownsample(velocityTexture, tempReduce);
            // Pass 2: tempReduce -> tempFinal (1x1)
            DispatchDownsample(tempReduce, tempFinal);

            pending = AsyncGPUReadback.Request(tempFinal, 0, OnReadback);
        }

        private void OnReadback(AsyncGPUReadbackRequest req)
        {
            if (req.hasError) return;
            var data = req.GetData<Vector4>();
            if (data.Length == 0) return;
            var v = data[0];
            AverageVelocity = new Vector2(v.x, v.y);
            AverageSpeed = new Vector2(v.x, v.y).magnitude;
        }

        private void DispatchDownsample(RenderTexture src, RenderTexture dst)
        {
            statsCompute.SetTexture(kernelDownsample, "_Source", src);
            statsCompute.SetTexture(kernelDownsample, "_Dest", dst);
            statsCompute.SetInts("_SourceSize", src.width, src.height);
            statsCompute.SetInts("_DestSize", dst.width, dst.height);

            int gx = Mathf.CeilToInt(dst.width / 8f);
            int gy = Mathf.CeilToInt(dst.height / 8f);
            statsCompute.Dispatch(kernelDownsample, gx, gy, 1);
        }

        private void EnsureRTs()
        {
            if (tempReduce == null || tempReduce.width != reduceSize.x || tempReduce.height != reduceSize.y)
            {
                ReleaseRT(ref tempReduce);
                tempReduce = CreateRT(reduceSize.x, reduceSize.y);
            }
            if (tempFinal == null || tempFinal.width != 1 || tempFinal.height != 1)
            {
                ReleaseRT(ref tempFinal);
                tempFinal = CreateRT(1, 1);
            }
        }

        private void AllocateRTs() => EnsureRTs();

        private RenderTexture CreateRT(int w, int h)
        {
            var rt = new RenderTexture(w, h, 0, RenderTextureFormat.ARGBFloat)
            {
                enableRandomWrite = true,
                useMipMap = false,
                autoGenerateMips = false
            };
            rt.Create();
            return rt;
        }

        private void ReleaseRT(ref RenderTexture rt)
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
