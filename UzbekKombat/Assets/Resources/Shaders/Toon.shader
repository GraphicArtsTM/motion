// Stilizatsiyalangan "cel" yoritish: 2 pog'onali soya, rim-yorug'lik, metall (vertex alfa orqali),
// soxta muhit aksi (osmon gradienti), shamolda tebranish (daraxtlar uchun).
// Vertex rang alfasi: 1 — oddiy material, <1 — metall (qancha kichik, shuncha yaltiroq).
Shader "UzbekKombat/Toon"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo", 2D) = "white" {}
        _ShadeColor ("Shade Color", Color) = (0.62,0.55,0.68,1)
        _RimColor ("Rim Color", Color) = (1,0.86,0.62,1)
        _RimPower ("Rim Power", Range(0.5,8)) = 3.5
        _RimStrength ("Rim Strength", Range(0,1)) = 0.35
        _Specular ("Specular", Range(0,1)) = 0.0
        _EmissionColor ("Emission", Color) = (0,0,0,0)
        _WindStrength ("Wind Strength", Range(0,1)) = 0
        _WindBase ("Wind Base Height", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 200

        CGPROGRAM
        #pragma surface surf Toon fullforwardshadows addshadow vertex:vert
        #pragma target 3.0

        sampler2D _MainTex;
        fixed4 _Color;
        fixed4 _ShadeColor;
        fixed4 _RimColor;
        half _RimPower;
        half _RimStrength;
        half _Specular;
        fixed4 _EmissionColor;
        float _WindStrength;
        float _WindBase;
        fixed4 _UKEnvTop;
        fixed4 _UKEnvHorizon;
        fixed4 _UKEnvGround;

        struct Input
        {
            float2 uv_MainTex;
            float3 viewDir;
            float4 color : COLOR;
            float3 worldNormal;
        };

        void vert (inout appdata_full v)
        {
            if (_WindStrength > 0.0001)
            {
                float3 wp = mul(unity_ObjectToWorld, v.vertex).xyz;
                float h = saturate((wp.y - _WindBase) * 0.12);
                float s = sin(_Time.y * 1.6 + wp.x * 0.35 + wp.z * 0.21) + 0.45 * sin(_Time.y * 3.3 + wp.x * 1.3 + wp.y);
                float3 offs = float3(s, 0.15 * s, s * 0.45) * _WindStrength * h;
                v.vertex.xyz += mul((float3x3)unity_WorldToObject, offs);
            }
        }

        half4 LightingToon (SurfaceOutput s, half3 lightDir, half3 viewDir, half atten)
        {
            half ndl = dot(s.Normal, lightDir);
            half band = smoothstep(-0.02, 0.10, ndl);
            half band2 = smoothstep(0.55, 0.65, ndl) * 0.12;
            half shadow = smoothstep(0.25, 0.55, atten);
            half lit = band * shadow;
            half3 h = normalize(lightDir + viewDir);
            half nh = dot(s.Normal, h);
            half spec = smoothstep(0.92, 0.95, nh) * _Specular * lit;
            // Metall uchun keng va yorqin "anime" yaltirashi
            spec += (smoothstep(0.80, 0.86, nh) * 0.55 + smoothstep(0.96, 0.975, nh) * 1.4) * s.Gloss * lit;
            half4 c;
        #ifdef UNITY_PASS_FORWARDBASE
            c.rgb = s.Albedo * _LightColor0.rgb * (lerp(_ShadeColor.rgb, half3(1,1,1), lit) + band2 * lit) + spec * _LightColor0.rgb;
        #else
            c.rgb = s.Albedo * _LightColor0.rgb * smoothstep(0.0, 0.25, ndl) * atten + spec * _LightColor0.rgb * 0.5;
        #endif
            c.a = s.Alpha;
            return c;
        }

        void surf (Input IN, inout SurfaceOutput o)
        {
            fixed4 tex = tex2D(_MainTex, IN.uv_MainTex) * _Color;
            tex.rgb *= IN.color.rgb;
            half metal = saturate(1.0 - IN.color.a);
            half3 n = normalize(IN.worldNormal);
            half3 v = normalize(IN.viewDir);
            half3 r = reflect(-v, n);
            half3 env = r.y > 0 ? lerp(_UKEnvHorizon.rgb, _UKEnvTop.rgb, saturate(r.y * 1.6)) : lerp(_UKEnvHorizon.rgb, _UKEnvGround.rgb, saturate(-r.y * 2.5));
            o.Albedo = tex.rgb * (1.0 - metal * 0.55);
            o.Gloss = metal;
            half rim = 1.0 - saturate(dot(v, n));
            half rimK = smoothstep(0.45, 1.0, pow(rim, _RimPower * 0.5));
            o.Emission = _RimColor.rgb * rimK * (_RimStrength + metal * 0.4) * tex.rgb + env * tex.rgb * metal * 0.9 + _EmissionColor.rgb;
            o.Alpha = 1;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
