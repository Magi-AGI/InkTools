Shader "InkTools/Simulation/DrawForce2D"
{
    Properties
    {
        _Center ("Center (UV)", Vector) = (0.5,0.5,0,0)
        _Radius ("Radius", Float) = 0.05
        _Strength ("Strength", Float) = 1.0
        _Force ("Force XY", Vector) = (1,0,0,0)
        _Falloff ("Falloff", Float) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Blend One One
        ZWrite Off
        Cull Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            float4 _Center;
            float _Radius;
            float _Strength;
            float4 _Force;
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
                float falloff = exp(-pow(r / max(_Radius, 1e-3), _Falloff));
                float2 force = _Force.xy * _Strength * falloff;
                return float4(force, 0, 0);
            }
            ENDCG
        }
    }
}
