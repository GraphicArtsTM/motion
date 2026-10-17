// Stilizatsiyalangan "cel" yoritish: 2 pog'onali soya, rim-yorug'lik, emissiya.
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
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 200

        CGPROGRAM
        #pragma surface surf Toon fullforwardshadows addshadow
        #pragma target 3.0

        sampler2D _MainTex;
        fixed4 _Color;
        fixed4 _ShadeColor;
        fixed4 _RimColor;
        half _RimPower;
        half _RimStrength;
        half _Specular;
        fixed4 _EmissionColor;

        struct Input
        {
            float2 uv_MainTex;
            float3 viewDir;
            float4 color : COLOR;
        };

        half4 LightingToon (SurfaceOutput s, half3 lightDir, half3 viewDir, half atten)
        {
            half ndl = dot(s.Normal, lightDir);
            half band = smoothstep(-0.02, 0.10, ndl);
            half band2 = smoothstep(0.55, 0.65, ndl) * 0.12;
            half shadow = smoothstep(0.25, 0.55, atten);
            half lit = band * shadow;
            half3 h = normalize(lightDir + viewDir);
            half spec = smoothstep(0.92, 0.95, dot(s.Normal, h)) * _Specular * lit;
            half4 c;
        #ifdef UNITY_PASS_FORWARDBASE
            c.rgb = s.Albedo * _LightColor0.rgb * (lerp(_ShadeColor.rgb, half3(1,1,1), lit) + band2 * lit) + spec * _LightColor0.rgb;
        #else
            c.rgb = s.Albedo * _LightColor0.rgb * smoothstep(0.0, 0.25, ndl) * atten;
        #endif
            c.a = s.Alpha;
            return c;
        }

        void surf (Input IN, inout SurfaceOutput o)
        {
            fixed4 tex = tex2D(_MainTex, IN.uv_MainTex) * _Color * IN.color;
            o.Albedo = tex.rgb;
            half rim = 1.0 - saturate(dot(normalize(IN.viewDir), o.Normal));
            rim = smoothstep(0.45, 1.0, pow(rim, _RimPower * 0.5));
            o.Emission = _RimColor.rgb * rim * _RimStrength * tex.rgb + _EmissionColor.rgb;
            o.Alpha = tex.a;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
