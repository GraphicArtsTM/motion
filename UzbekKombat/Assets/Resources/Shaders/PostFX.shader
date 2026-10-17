// Post-effektlar: SSAO (ambient occlusion), bloom, ACES tonemapping, rang gradatsiyasi,
// vinyetka, xromatik aberratsiya, plyonka donadorligi.
Shader "Hidden/UzbekKombat/PostFX"
{
    Properties { _MainTex ("", 2D) = "white" {} }
    CGINCLUDE
    #include "UnityCG.cginc"
    sampler2D _MainTex; float4 _MainTex_TexelSize;
    sampler2D _BloomTex; sampler2D _SourceTex; sampler2D _AOTex;
    UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);
    float4 _Threshold;     // x: threshold, y: knee, z: intensity
    float4 _Grade;         // x: contrast, y: saturation, z: exposure, w: vignette
    float4 _Tint;
    float4 _Shadows;
    float4 _Fx;            // x: aberration, y: grain, z: time, w: desaturate
    float4 _AOParams;      // x: radius (m), y: intensity, z: bias, w: enabled
    float4 _UVToView;
    float4 _BlurDir;

    struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
    v2f vert (appdata_img v) { v2f o; o.pos = UnityObjectToClipPos(v.vertex); o.uv = v.texcoord; return o; }

    half3 Sample4(float2 uv, float d)
    {
        float4 o = _MainTex_TexelSize.xyxy * float4(-d, -d, d, d);
        half3 s = tex2D(_MainTex, uv + o.xy).rgb + tex2D(_MainTex, uv + o.zy).rgb + tex2D(_MainTex, uv + o.xw).rgb + tex2D(_MainTex, uv + o.zw).rgb;
        return s * 0.25;
    }

    half4 fragPrefilter (v2f i) : SV_Target
    {
        half3 c = Sample4(i.uv, 1);
        half br = max(c.r, max(c.g, c.b));
        half soft = clamp(br - _Threshold.x + _Threshold.y, 0, 2 * _Threshold.y);
        soft = soft * soft / (4 * _Threshold.y + 1e-4);
        half contrib = max(soft, br - _Threshold.x) / max(br, 1e-4);
        return half4(min(c * contrib, 8), 1);
    }
    half4 fragDown (v2f i) : SV_Target { return half4(Sample4(i.uv, 1), 1); }
    half4 fragUp (v2f i) : SV_Target { return half4(Sample4(i.uv, 0.5), 1); }

    // ---------- SSAO ----------
    float3 ViewPos(float2 uv)
    {
        float d = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
        return float3((uv * _UVToView.xy + _UVToView.zw) * d, d);
    }

    half4 fragAO (v2f i) : SV_Target
    {
        float3 p = ViewPos(i.uv);
        if (p.z > 60) return half4(1, 1, 1, 1);
        float3 n = normalize(cross(ddy(p), ddx(p)));
        if (dot(n, p) > 0) n = -n;
        float radiusUV = _AOParams.x / max(p.z, 0.3) * 0.5 / max(abs(_UVToView.x), 1e-3);
        float occ = 0;
        float rnd = frac(sin(dot(i.uv * 1000, float2(12.9898, 78.233))) * 43758.5453) * 6.2831;
        const int N = 10;
        for (int k = 0; k < N; k++)
        {
            float a = rnd + k * 2.399963;
            float r = (k + 0.5) / N;
            float2 suv = i.uv + float2(cos(a), sin(a)) * r * radiusUV * float2(1, _MainTex_TexelSize.z * _MainTex_TexelSize.y);
            float3 s = ViewPos(suv);
            float3 v = s - p;
            float vv = dot(v, v);
            float range = saturate(_AOParams.x * _AOParams.x * 4 / (vv + 1e-4));
            occ += max(0, dot(v, n) - _AOParams.z * p.z) / (vv + 0.01) * range;
        }
        float ao = saturate(1 - occ * _AOParams.y * 2.0 / N);
        return half4(ao, ao, ao, 1);
    }

    half4 fragBlur (v2f i) : SV_Target
    {
        float2 o = _BlurDir.xy * _MainTex_TexelSize.xy;
        half a = tex2D(_MainTex, i.uv).r * 0.36;
        a += (tex2D(_MainTex, i.uv + o).r + tex2D(_MainTex, i.uv - o).r) * 0.24;
        a += (tex2D(_MainTex, i.uv + o * 2.5).r + tex2D(_MainTex, i.uv - o * 2.5).r) * 0.08;
        return half4(a, a, a, 1);
    }

    // ---------- Yakuniy ----------
    half3 ACES(half3 x)
    {
        const half a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
        return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
    }

    half4 fragFinal (v2f i) : SV_Target
    {
        float2 uv = i.uv;
        float2 dc = uv - 0.5;
        float ab = _Fx.x * dot(dc, dc);
        half3 col;
        col.r = tex2D(_SourceTex, uv - dc * ab).r;
        col.g = tex2D(_SourceTex, uv).g;
        col.b = tex2D(_SourceTex, uv + dc * ab).b;
        if (_AOParams.w > 0.5)
        {
            half ao = tex2D(_AOTex, uv).r;
            col *= lerp(1, ao, 0.85);
        }
        col += tex2D(_BloomTex, uv).rgb * _Threshold.z;
        col *= _Grade.z;
        col = ACES(col);
        // Soya/yorug' tusi (split-toning)
        half lum = dot(col, half3(0.2126, 0.7152, 0.0722));
        col *= lerp(_Shadows.rgb, _Tint.rgb, smoothstep(0.05, 0.6, lum));
        // Kontrast (o'rta kulrang atrofida) va to'yinganlik
        col = saturate((col - 0.18) * _Grade.x + 0.18);
        lum = dot(col, half3(0.2126, 0.7152, 0.0722));
        col = lerp(lum.xxx, col, _Grade.y * (1 - _Fx.w));
        half vig = 1 - dot(dc, dc) * _Grade.w * 2.0;
        col *= saturate(vig);
        float n = frac(sin(dot(uv * _Fx.z, float2(12.9898, 78.233))) * 43758.5453);
        col += (n - 0.5) * _Fx.y;
        return half4(saturate(col), 1);
    }
    ENDCG
    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        Pass { CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragPrefilter
            ENDCG }
        Pass { CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragDown
            ENDCG }
        Pass { Blend One One
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragUp
            ENDCG }
        Pass { CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragFinal
            ENDCG }
        Pass { CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragAO
            #pragma target 3.0
            ENDCG }
        Pass { CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragBlur
            ENDCG }
    }
}
