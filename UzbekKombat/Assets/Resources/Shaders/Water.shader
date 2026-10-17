// Ariq suvi: oqayotgan ikki qatlamli tekstura, fresnel osmon aksi, quyosh yaltirashi.
Shader "UzbekKombat/Water"
{
    Properties
    {
        _MainTex ("Ripples", 2D) = "white" {}
        _Deep ("Deep Color", Color) = (0.08,0.28,0.35,1)
        _Shallow ("Shallow Color", Color) = (0.35,0.65,0.7,1)
        _Flow ("Flow (xy speed1, zw speed2)", Vector) = (0.25,0.02,-0.12,0.05)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry+10" }
        Pass
        {
            Tags { "LightMode"="ForwardBase" }
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            sampler2D _MainTex; float4 _MainTex_ST; fixed4 _Deep, _Shallow; float4 _Flow;
            fixed4 _UKEnvTop, _UKEnvHorizon;
            struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; float3 normal : NORMAL; };
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; float3 wp : TEXCOORD1; UNITY_FOG_COORDS(2) };
            v2f vert (appdata v)
            {
                v2f o;
                float3 wp = mul(unity_ObjectToWorld, v.vertex).xyz;
                wp.y += sin(_Time.y * 2.0 + wp.x * 3.0) * 0.008;
                o.pos = UnityWorldToClipPos(wp);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.wp = wp;
                UNITY_TRANSFER_FOG(o, o.pos);
                return o;
            }
            fixed4 frag (v2f i) : SV_Target
            {
                float2 uv1 = i.wp.xz * 0.6 + _Time.y * _Flow.xy;
                float2 uv2 = i.wp.xz * 1.1 + _Time.y * _Flow.zw;
                float a = tex2D(_MainTex, uv1).r, b = tex2D(_MainTex, uv2).g;
                float3 n = normalize(float3((a - 0.5) * 0.6, 1, (b - 0.5) * 0.6));
                float3 v = normalize(_WorldSpaceCameraPos - i.wp);
                float fres = pow(1 - saturate(dot(n, v)), 3);
                float3 r = reflect(-v, n);
                float3 sky = lerp(_UKEnvHorizon.rgb, _UKEnvTop.rgb, saturate(r.y * 2));
                float3 col = lerp(_Deep.rgb, _Shallow.rgb, a * b * 1.4);
                col = lerp(col, sky, saturate(fres * 0.8 + 0.15));
                float3 h = normalize(_WorldSpaceLightPos0.xyz + v);
                float spec = pow(saturate(dot(n, h)), 120) * 3;
                col += spec * _LightColor0.rgb;
                fixed4 c = fixed4(col, 1);
                UNITY_APPLY_FOG(i.fogCoord, c);
                return c;
            }
            ENDCG
        }
    }
    FallBack "Diffuse"
}
