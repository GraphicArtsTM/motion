// "Inverted hull" kontur chiziq — personajlar uchun.
Shader "UzbekKombat/Outline"
{
    Properties
    {
        _OutlineColor ("Outline Color", Color) = (0.08,0.05,0.04,1)
        _OutlineWidth ("Outline Width", Range(0,0.05)) = 0.012
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry+1" }
        Pass
        {
            Name "OUTLINE"
            Cull Front
            ZWrite On
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #include "UnityCG.cginc"

            fixed4 _OutlineColor;
            float _OutlineWidth;

            struct appdata { float4 vertex : POSITION; float3 normal : NORMAL; };
            struct v2f { float4 pos : SV_POSITION; UNITY_FOG_COORDS(0) };

            v2f vert (appdata v)
            {
                v2f o;
                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                float3 worldNormal = normalize(UnityObjectToWorldNormal(v.normal));
                float dist = distance(_WorldSpaceCameraPos, worldPos);
                worldPos += worldNormal * _OutlineWidth * clamp(dist * 0.12, 0.6, 2.0);
                o.pos = UnityWorldToClipPos(worldPos);
                UNITY_TRANSFER_FOG(o, o.pos);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 c = _OutlineColor;
                UNITY_APPLY_FOG(i.fogCoord, c);
                return c;
            }
            ENDCG
        }
    }
}
