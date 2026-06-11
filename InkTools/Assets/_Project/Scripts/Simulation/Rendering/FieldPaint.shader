Shader "InkTools/Simulation/FieldPaint"
{
    Properties
    {
        _Center ("Center (UV)", Vector) = (0.5,0.5,0,0)
        _Radius ("Radius", Float) = 0.05
        _Strength ("Strength", Float) = 1.0
        _Falloff ("Falloff", Float) = 2.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Cull Off ZWrite Off
        Blend One One

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            float4 _Center;
            float _Radius;
            float _Strength;
            float _Falloff;

            struct appdata { float4 vertex : POSITION; };
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.vertex.xy * 0.5 + 0.5;
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float2 d = i.uv - _Center.xy;
                float r = length(d);
                if (r > _Radius) discard;
                float t = 1.0 - saturate(r / max(_Radius, 1e-5));
                float w = pow(t, _Falloff);
                return float4(_Strength * w, 0, 0, 1);
            }
            ENDCG
        }
    }
}
