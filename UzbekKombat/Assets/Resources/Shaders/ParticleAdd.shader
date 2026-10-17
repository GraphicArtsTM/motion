Shader "UzbekKombat/ParticleAdd"
{
    Properties { _MainTex ("Texture", 2D) = "white" {} _TintColor ("Tint", Color) = (1,1,1,1) }
    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" "IgnoreProjector"="True" }
        Blend SrcAlpha One
        ZWrite Off Cull Off
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            sampler2D _MainTex; float4 _MainTex_ST; fixed4 _TintColor;
            struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; fixed4 color : COLOR; };
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; fixed4 color : COLOR; };
            v2f vert (appdata v) { v2f o; o.pos = UnityObjectToClipPos(v.vertex); o.uv = TRANSFORM_TEX(v.uv, _MainTex); o.color = v.color * _TintColor; return o; }
            fixed4 frag (v2f i) : SV_Target { fixed4 c = tex2D(_MainTex, i.uv) * i.color; c.rgb *= c.a * 2.0; return c; }
            ENDCG
        }
    }
}
