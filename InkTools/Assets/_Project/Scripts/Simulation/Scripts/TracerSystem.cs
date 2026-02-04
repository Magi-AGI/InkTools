using UnityEngine;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Lightweight tracer visualizer: advects point sprites by a velocity field for debug/polish.
    /// Lives in InkTools; consumers feed a velocity texture and toggle rendering.
    /// </summary>
    public class TracerSystem : MonoBehaviour
    {
        [Header("Simulation")]
        [SerializeField] private ComputeShader tracerCompute;
        [SerializeField] private RenderTexture velocityTexture;
        [SerializeField] private int tracerCount = 5000;
        [SerializeField, Range(0.01f, 5f)] private float velocityScale = 1f;
        [SerializeField, Range(0f, 1f)] private float drag = 0.5f;
        [SerializeField, Range(0f, 0.1f)] private float respawnJitter = 0.02f;

        [Header("Rendering")]
        [SerializeField] private Material tracerMaterial;
        [SerializeField] private float baseSize = 0.004f;
        [SerializeField] private float speedRange = 2f;
        [SerializeField] private bool render = true;

        private ComputeBuffer tracerBuffer;
        private int kernelInit;
        private int kernelAdvect;

        private void OnEnable()
        {
            if (tracerCompute == null)
            {
                Debug.LogWarning("TracerSystem: tracerCompute not set.");
                enabled = false;
                return;
            }

            kernelInit = tracerCompute.FindKernel("Init");
            kernelAdvect = tracerCompute.FindKernel("Advect");

            AllocateBuffer();
            DispatchInit();
        }

        private void OnDisable()
        {
            ReleaseBuffer();
        }

        private void Update()
        {
            if (tracerBuffer == null || velocityTexture == null) return;

            tracerCompute.SetBuffer(kernelAdvect, "_Tracers", tracerBuffer);
            tracerCompute.SetTexture(kernelAdvect, "_Velocity", velocityTexture);
            tracerCompute.SetFloat("_DeltaTime", Time.deltaTime);
            tracerCompute.SetFloat("_VelocityScale", velocityScale);
            tracerCompute.SetFloat("_Drag", drag);
            tracerCompute.SetFloat("_RespawnJitter", respawnJitter);
            tracerCompute.SetInt("_TracerCount", tracerCount);

            Dispatch(kernelAdvect);
        }

        private void OnRenderObject()
        {
            if (!render || tracerBuffer == null || tracerMaterial == null) return;

            tracerMaterial.SetBuffer("_Tracers", tracerBuffer);
            tracerMaterial.SetFloat("_BaseSize", baseSize);
            tracerMaterial.SetFloat("_SpeedRange", speedRange);
            tracerMaterial.SetPass(0);

            Graphics.DrawProceduralNow(MeshTopology.Points, tracerCount, 1);
        }

        public void SetVelocityTexture(RenderTexture velocity) => velocityTexture = velocity;

        private void AllocateBuffer()
        {
            ReleaseBuffer();
            tracerBuffer = new ComputeBuffer(tracerCount, sizeof(float) * 4, ComputeBufferType.Default);
        }

        private void DispatchInit()
        {
            tracerCompute.SetBuffer(kernelInit, "_Tracers", tracerBuffer);
            tracerCompute.SetInt("_TracerCount", tracerCount);
            Dispatch(kernelInit);
        }

        private void Dispatch(int kernel)
        {
            const int THREADS = 256;
            int groups = (tracerCount + THREADS - 1) / THREADS;
            tracerCompute.Dispatch(kernel, groups, 1, 1);
        }

        private void ReleaseBuffer()
        {
            tracerBuffer?.Release();
            tracerBuffer = null;
        }
    }
}
