Shader "InkTools/Simulation/VelocityArrows"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _Scale ("Arrow Scale", Float) = 0.05
        _GridStep ("Grid Step (pixels)", Float) = 16
        _VelTex ("Velocity", 2D) = "black" {}
    }
    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        Cull Off

        Pass
        {
            CGPROGRAM
            #pragma vertex Vert
            #pragma geometry Geo
            #pragma fragment Frag
            #pragma target 4.5

            #include "UnityCG.cginc"

            sampler2D _VelTex;
            float4 _VelTex_TexelSize;
            float4 _Color;
            float _Scale;
            float _GridStep;

            struct appdata { uint vertexID : SV_VertexID; };
            struct v2g
            {
                float2 uv : TEXCOORD0;
            };
            struct g2f
            {
                float4 pos : SV_POSITION;
                float4 col : COLOR0;
            };

            v2g Vert(appdata v)
            {
                v2g o;
                // Map vertexID to grid position
                uint cols = (uint)max(1, floor(_VelTex_TexelSize.z / _GridStep));
                uint x = v.vertexID % cols;
                uint y = v.vertexID / cols;
                float2 uv = (float2(x, y) + 0.5) * _GridStep * _VelTex_TexelSize.xy;
                o.uv = uv;
                return o;
            }

            [maxvertexcount(4)]
            void Geo(point v2g IN[1], inout TriangleStream<g2f> triStream)
            {
                float2 uv = IN[0].uv;
                float2 vel = tex2Dlod(_VelTex, float4(uv, 0, 0)).xy;
                float len = length(vel);
                float2 dir = len > 1e-5 ? normalize(vel) : float2(0, 0);
                float2 offset = dir * _Scale;
                float2 normal = float2(-dir.y, dir.x) * _Scale * 0.3;

                float2 p0 = uv - offset * 0.5 - normal;
                float2 p1 = uv + offset * 0.5 - normal;
                float2 p2 = uv + offset * 0.5 + normal;
                float2 p3 = uv - offset * 0.5 + normal;

                float4 col = _Color;
                col.a *= saturate(len * 2);

                g2f o;
                o.col = col;

                o.pos = UnityObjectToClipPos(float4(p0 * 2 - 1, 0, 1)); triStream.Append(o);
                o.pos = UnityObjectToClipPos(float4(p1 * 2 - 1, 0, 1)); triStream.Append(o);
                o.pos = UnityObjectToClipPos(float4(p2 * 2 - 1, 0, 1)); triStream.Append(o);
                o.pos = UnityObjectToClipPos(float4(p3 * 2 - 1, 0, 1)); triStream.Append(o);
            }

            fixed4 Frag(g2f i) : SV_Target { return i.col; }
            ENDCG
        }
    }
}
