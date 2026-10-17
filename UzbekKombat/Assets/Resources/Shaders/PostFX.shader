// Post-effektlar: bloom (yorqinlik nuri), rang gradatsiyasi, vinyetka, xromatik aberratsiya, plyonka donadorligi.
Shader "Hidden/UzbekKombat/PostFX"
{
    Properties { _MainTex ("", 2D) = "white" {} }
    CGINCLUDE
    #include "UnityCG.cginc"
    sampler2D _MainTex; float4 _MainTex_TexelSize;
    sampler2D _BloomTex; sampler2D _SourceTex;
    float4 _Threshold;     // x: threshold, y: knee, z: intensity
    float4 _Grade;         // x: contrast, y: saturation, z: exposure, w: vignette
    float4 _Tint;          // rgb tint
    float4 _Shadows;       // rgb shadow tint
    float4 _Fx;            // x: aberration, y: grain, z: time, w: desaturate (KO)
    float4 _Flash;         // rgb + a

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
        return half4(c * contrib, 1);
    }
    half4 fragDown (v2f i) : SV_Target { return half4(Sample4(i.uv, 1), 1); }
    half4 fragUp (v2f i) : SV_Target { return half4(Sample4(i.uv, 0.5), 1); }

    half4 fragFinal (v2f i) : SV_Target
    {
        float2 uv = i.uv;
        float2 dc = uv - 0.5;
        float ab = _Fx.x * dot(dc, dc);
        half3 col;
        col.r = tex2D(_SourceTex, uv - dc * ab).r;
        col.g = tex2D(_SourceTex, uv).g;
        col.b = tex2D(_SourceTex, uv + dc * ab).b;
        half3 bloom = tex2D(_BloomTex, uv).rgb;
        col += bloom * _Threshold.z;
        col *= _Grade.z;
        // Yumshoq tonemap (Reinhard + yelka)
        col = col / (1 + col * 0.22);
        col *= 1.18;
        // Soya/yorug' tusi
        half lum = dot(col, half3(0.299, 0.587, 0.114));
        col = lerp(col * _Shadows.rgb * 1.6, col * _Tint.rgb, smoothstep(0.0, 0.6, lum));
        // Kontrast va to'yinganlik
        col = (col - 0.5) * _Grade.x + 0.5;
        lum = dot(col, half3(0.299, 0.587, 0.114));
        col = lerp(lum.xxx, col, _Grade.y * (1 - _Fx.w));
        // Vinyetka
        half vig = 1 - dot(dc, dc) * _Grade.w * 2.2;
        col *= saturate(vig);
        // Donadorlik
        float n = frac(sin(dot(uv * _Fx.z, float2(12.9898, 78.233))) * 43758.5453);
        col += (n - 0.5) * _Fx.y;
        col = lerp(col, _Flash.rgb, _Flash.a);
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
    }
}
