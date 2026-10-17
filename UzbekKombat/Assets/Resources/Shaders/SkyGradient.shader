// Protsedural osmon: gradient + quyosh + bulutsimon shovqin.
Shader "UzbekKombat/SkyGradient"
{
    Properties
    {
        _TopColor ("Top", Color) = (0.22,0.33,0.62,1)
        _HorizonColor ("Horizon", Color) = (1.0,0.66,0.38,1)
        _BottomColor ("Bottom", Color) = (0.35,0.25,0.22,1)
        _SunColor ("Sun", Color) = (1,0.85,0.55,1)
        _SunDir ("Sun Direction", Vector) = (0.3,0.12,1,0)
        _SunSize ("Sun Size", Range(0.001,0.2)) = 0.04
        _Exponent ("Horizon Sharpness", Range(0.1,8)) = 1.6
        _StarStrength ("Stars", Range(0,1)) = 0
        _CloudColor ("Clouds", Color) = (1,0.8,0.7,0.35)
    }
    SubShader
    {
        Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" }
        Cull Off ZWrite Off
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            fixed4 _TopColor, _HorizonColor, _BottomColor, _SunColor, _CloudColor;
            float4 _SunDir;
            float _SunSize, _Exponent, _StarStrength;

            struct appdata { float4 vertex : POSITION; };
            struct v2f { float4 pos : SV_POSITION; float3 dir : TEXCOORD0; };

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.dir = v.vertex.xyz;
                return o;
            }

            float hash (float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
            float noise (float2 p)
            {
                float2 i = floor(p); float2 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);
                return lerp(lerp(hash(i), hash(i + float2(1,0)), f.x), lerp(hash(i + float2(0,1)), hash(i + float2(1,1)), f.x), f.y);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float3 d = normalize(i.dir);
                float y = d.y;
                float up = pow(saturate(y), 1.0 / _Exponent);
                float down = pow(saturate(-y), 0.5);
                float3 col = lerp(_HorizonColor.rgb, _TopColor.rgb, up);
                col = lerp(col, _BottomColor.rgb, down);
                float3 sd = normalize(_SunDir.xyz);
                float s = dot(d, sd);
                float sun = smoothstep(1.0 - _SunSize, 1.0 - _SunSize * 0.6, s);
                float glow = pow(saturate(s), 24.0) * 0.6 + pow(saturate(s), 4.0) * 0.18;
                col += _SunColor.rgb * (sun + glow);
                float2 cuv = d.xz / max(0.08, y + 0.15) * 1.3;
                float c = noise(cuv * 1.5) * 0.6 + noise(cuv * 3.7) * 0.3 + noise(cuv * 8.1) * 0.1;
                c = smoothstep(0.55, 0.85, c) * saturate(y * 4.0) * (1.0 - saturate(y * 1.2));
                col = lerp(col, _CloudColor.rgb, c * _CloudColor.a);
                float st = step(0.997, hash(floor(d.xz / max(0.05, y + 0.2) * 220.0))) * saturate(y * 3.0);
                col += st * _StarStrength;
                return fixed4(col, 1);
            }
            ENDCG
        }
    }
}
