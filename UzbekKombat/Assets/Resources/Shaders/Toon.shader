// Stilizatsiyalangan-realistik yoritish (nomi tarixiy: "Toon").
// Yumshoq "wrap" diffuz, teri uchun yorug'lik sochilishi (subsurface), Blinn-Phong yaltirash,
// metall uchun muhit aksi, mato/teri/metall detal teksturasi, shamol (daraxtlar).
// Vertex rang: RGB — asosiy rang. UV2: x — metall (0..1), y — teri (0/1).
Shader "UzbekKombat/Toon"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo", 2D) = "white" {}
        _ShadeColor ("Shade Color", Color) = (0.62,0.58,0.68,1)
        _RimColor ("Rim Color", Color) = (1,0.9,0.75,1)
        _RimPower ("Rim Power", Range(0.5,8)) = 4
        _RimStrength ("Rim Strength", Range(0,1)) = 0.2
        _Specular ("Specular", Range(0,1)) = 0.0
        _EmissionColor ("Emission", Color) = (0,0,0,0)
        _DetailStrength ("Detail Strength", Range(0,1)) = 0.6
        _DetailTiling ("Detail Tiling", Vector) = (6,4,0,0)
        _Toonness ("Toonness", Range(0,1)) = 0.15
        _WindStrength ("Wind Strength", Range(0,2)) = 0
        _WindBase ("Wind Base Height", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 300

        CGPROGRAM
        #pragma surface surf Realish fullforwardshadows addshadow vertex:vert
        #pragma target 3.0

        sampler2D _MainTex;
        sampler2D _UKDetailTex;
        fixed4 _Color, _ShadeColor, _RimColor, _EmissionColor;
        half _RimPower, _RimStrength, _Specular, _DetailStrength, _Toonness;
        float4 _DetailTiling;
        float _WindStrength, _WindBase;
        fixed4 _UKEnvTop, _UKEnvHorizon, _UKEnvGround;

        struct Input
        {
            float2 uv_MainTex;
            float3 viewDir;
            float4 color : COLOR;
            float3 worldNormal;
            float2 matp;
            float2 duv;
        };

        void vert (inout appdata_full v, out Input o)
        {
            UNITY_INITIALIZE_OUTPUT(Input, o);
            o.matp = v.texcoord1.xy;
            o.duv = v.texcoord.xy * _DetailTiling.xy;
            if (_WindStrength > 0.0001)
            {
                float3 wp = mul(unity_ObjectToWorld, v.vertex).xyz;
                float h = saturate((wp.y - _WindBase) * 0.12);
                float s = sin(_Time.y * 1.6 + wp.x * 0.35 + wp.z * 0.21) + 0.45 * sin(_Time.y * 3.3 + wp.x * 1.3 + wp.y);
                float3 offs = float3(s, 0.15 * s, s * 0.45) * _WindStrength * h;
                v.vertex.xyz += mul((float3x3)unity_WorldToObject, offs);
            }
        }

        // s.Gloss — metall, s.Specular — silliqlik, s.Alpha — teri
        half4 LightingRealish (SurfaceOutput s, half3 lightDir, half3 viewDir, half atten)
        {
            half ndl = dot(s.Normal, lightDir);
            half wrap = saturate((ndl + 0.35) / 1.35);
            half soft = wrap * wrap;
            half cel = smoothstep(0.0, 0.12, ndl);
            half diff = lerp(soft, cel, _Toonness);
            half shadow = smoothstep(0.15, 0.6, atten);
            half lit = diff * shadow;
            // Teri: terminatorda qizg'ish sochilish
            half scatter = saturate(wrap - saturate(ndl)) * s.Alpha;
            half3 h = normalize(lightDir + viewDir);
            half nh = saturate(dot(s.Normal, h));
            half smooth = s.Specular;
            half expo = exp2(10.0 * smooth + 1.0);
            half spec = pow(nh, expo) * (expo + 8.0) / 25.0 * smooth * smooth * shadow * saturate(ndl * 4.0);
            half3 specCol = lerp(half3(0.04, 0.04, 0.04) * 6.0, s.Albedo * 1.4 + 0.15, s.Gloss);
            half4 c;
        #ifdef UNITY_PASS_FORWARDBASE
            c.rgb = s.Albedo * _LightColor0.rgb * lit
                  + scatter * half3(0.55, 0.12, 0.06) * _LightColor0.rgb * shadow
                  + spec * specCol * _LightColor0.rgb;
        #else
            c.rgb = (s.Albedo * lit + spec * specCol) * _LightColor0.rgb * atten;
        #endif
            c.a = 1;
            return c;
        }

        void surf (Input IN, inout SurfaceOutput o)
        {
            fixed4 tex = tex2D(_MainTex, IN.uv_MainTex) * _Color;
            half3 baseCol = tex.rgb * IN.color.rgb;
            half metal = saturate(IN.matp.x);
            half skin = saturate(IN.matp.y);
            // Detal: R — mato to'qimasi, G — mayda shovqin (teri g'ovaklari / metall chiziqlari)
            half4 det = tex2D(_UKDetailTex, IN.duv);
            half detail = lerp(det.r, det.g, saturate(skin + metal));
            baseCol *= lerp(1.0, detail * 2.0, _DetailStrength * (skin > 0.5 ? 0.35 : 1.0));
            half3 n = normalize(IN.worldNormal);
            half3 v = normalize(IN.viewDir);
            half nv = saturate(dot(v, n));
            half3 r = reflect(-v, n);
            half3 env = r.y > 0 ? lerp(_UKEnvHorizon.rgb, _UKEnvTop.rgb, saturate(r.y * 1.6)) : lerp(_UKEnvHorizon.rgb, _UKEnvGround.rgb, saturate(-r.y * 2.5));
            half fres = pow(1.0 - nv, 5.0);
            half smooth = lerp(skin > 0.5 ? 0.42 : 0.18 + det.b * 0.12, 0.72 + det.g * 0.15, metal);
            o.Albedo = baseCol * (1.0 - metal * 0.65);
            o.Gloss = metal;
            o.Specular = smooth;
            o.Alpha = skin;
            half rimK = pow(1.0 - nv, _RimPower);
            o.Emission = _RimColor.rgb * rimK * _RimStrength * baseCol
                       + env * baseCol * metal * (0.55 + fres)
                       + env * fres * smooth * 0.18 * (1 - metal)
                       + _EmissionColor.rgb;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
