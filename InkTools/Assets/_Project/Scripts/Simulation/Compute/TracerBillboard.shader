Shader "InkTools/Simulation/TracerBillboard"
{
    Properties
    {
        _ColorGradient ("Color (speed ramp)", 2D) = "white" {}
        _BaseSize ("Base Size", Float) = 1.0
    }
    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        Cull Off
        ZWrite Off

        Pass
        {
            CGPROGRAM
            #pragma vertex Vert
            #pragma geometry Geo
            #pragma fragment Frag
            #pragma target 4.5

            #include "UnityCG.cginc"

            StructuredBuffer<float4> _Tracers; // xy pos, zw vel
            StructuredBuffer<float> _Vorticity;
            sampler2D _ColorGradient;
            float _BaseSize;
            float _SpeedRange; // optional normalization
            float _UseVorticity;
            float _VorticityBlend;

            float2 ScreenToClip(float2 uv)
            {
                return uv * 2 - 1;
            }

            struct appdata
            {
                uint vertexID : SV_VertexID;
            };

            struct v2g
            {
                float4 pos : POSITION;
                float2 vel : TEXCOORD0;
                float speed : TEXCOORD1;
                float vort : TEXCOORD2;
            };

            v2g Vert(appdata v)
            {
                v2g o;
                float4 t = _Tracers[v.vertexID];
                o.pos = float4(ScreenToClip(t.xy), 0, 1);
                o.vel = t.zw;
                o.speed = length(t.zw);
                o.vort = _Vorticity[v.vertexID];
                return o;
            }

            struct g2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float speed : TEXCOORD1;
                float vort : TEXCOORD2;
            };

            [maxvertexcount(4)]
            void Geo(point v2g IN[1], inout TriangleStream<g2f> triStream)
            {
                float size = _BaseSize;
                float2 right = float2(size, 0);
                float2 up = float2(0, size);

                float4 p = IN[0].pos;
                float2 quad[4] = {
                    p.xy - right - up,
                    p.xy + right - up,
                    p.xy + right + up,
                    p.xy - right + up
                };

                g2f o;
                o.speed = IN[0].speed;
                o.vort = IN[0].vort;

                o.pos = float4(quad[0], 0, 1); o.uv = float2(0,0); triStream.Append(o);
                o.pos = float4(quad[1], 0, 1); o.uv = float2(1,0); triStream.Append(o);
                o.pos = float4(quad[2], 0, 1); o.uv = float2(1,1); triStream.Append(o);
                o.pos = float4(quad[3], 0, 1); o.uv = float2(0,1); triStream.Append(o);
            }

            fixed4 Frag(g2f i) : SV_Target
            {
                float speedT = saturate(i.speed / max(_SpeedRange, 1e-3));
                float t = (_UseVorticity > 0.5)
                    ? saturate(lerp(speedT, abs(i.vort), _VorticityBlend))
                    : speedT;
                fixed4 col = tex2D(_ColorGradient, float2(t, 0.5));
                col.a *= col.a; // soften
                return col;
            }
            ENDCG
        }
    }
}
