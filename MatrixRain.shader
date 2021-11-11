Shader "Unlit/MatrixRain"
{
    Properties
    {
        [PerRendererData]_MainTex ("Texture", 2D) = "white" {}
        _Speed ("Speed", float) = 0.25
        _RainColor ("RainColor", Color) = ( 0.0, 1.0, 0.0, 1.0 )
        _HeightMult ("HeightMult", float) = 35.0
        _WidthMult ("WidthMult", float) = 35.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "UnityCG.cginc"

            UNITY_INSTANCING_BUFFER_START(Props)
                UNITY_DEFINE_INSTANCED_PROP(float, _Speed)
                UNITY_DEFINE_INSTANCED_PROP(float, _HeightMult)
                UNITY_DEFINE_INSTANCED_PROP(float, _WidthMult)
                UNITY_DEFINE_INSTANCED_PROP(float4, _RainColor)
            UNITY_INSTANCING_BUFFER_END(Props)

            sampler2D _MainTex;
            float4 _MainTex_ST;
            half4 _MainTex_TexelSize;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                fixed2 texelSize : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(o);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.texelSize = fixed2(_MainTex_TexelSize.z, _MainTex_TexelSize.w);
                return o;
            }

            #define iResolution _ScreenParams
            #define mod(x, y) (x-y*floor(x/y) )
            
            float random(float2 v) {
                return frac(sin(v.x * 32.1231 - v.y * 2.334 + 13399.2312) * 2412.32312);
            }
            float random(float x, float y) {
                return frac(sin(x * 32.1231 - y * 2.334 + 13399.2312) * 2412.32312);
            }
            float random(float x) {
                return frac(sin(x * 32.1231 + 13399.2312) * 2412.32312);
            }
            
            float hue2rgb(float f1, float f2, float hue) {
                if (hue < 0.0)
                    hue += 1.0;
                else if (hue > 1.0)
                    hue -= 1.0;
                float res;
                if ((6.0 * hue) < 1.0)
                    res = f1 + (f2 - f1) * 6.0 * hue;
                else if ((2.0 * hue) < 1.0)
                    res = f2;
                else if ((3.0 * hue) < 2.0)
                    res = f1 + (f2 - f1) * ((2.0 / 3.0) - hue) * 6.0;
                else
                    res = f1;
                return res;
            }
            
            float character(float i) {    
                 return i<15.01? floor(random(i)*20000.) : 0.; // 32768
            }
            
            #define iResolution _ScreenParams
            fixed4 frag(v2f i) : SV_Target {
//                _MainTex.
                    // _MainTex_TexelSize.z //contains width
                    // _MainTex_TexelSize.w //contains height
                float2 S = (i.texelSize.x * UNITY_ACCESS_INSTANCED_PROP(Props, _WidthMult)) * float2(3., 2.);
                float2 coord = float2( i.uv.x, i.uv.y );
                float2 c = floor(coord * S);
            
                float offset = random(c.x) * S.x;
                float speed = random(c.x * 10.0) + 0.2; speed *= UNITY_ACCESS_INSTANCED_PROP(Props, _Speed);
                float len = random(c.x) * (i.texelSize.y * UNITY_ACCESS_INSTANCED_PROP(Props, _HeightMult) ) + 10.;
                float u = 1. - frac((c.y / len ) + (_Time.y * speed ) + offset) * 2.;
            
                float padding = 4.;
                float2 smS = float2(3., 5.);
                float2 sm = floor(frac(coord * S) * (smS + float2(padding,padding))) - float2(padding,padding);
                float symbol = character(floor(random(c + floor(_Time.y * speed)) * 15.));
                bool s = sm.x < 0. || sm.x > smS.x || sm.y < 0. || sm.y > smS.y ? false
                         : mod(floor(symbol / pow(2., sm.x + sm.y * smS.x)), 2.) == 1.;
            
                float3 curRGB = UNITY_ACCESS_INSTANCED_PROP(Props, _RainColor);
                if( s )
                {
                    if( u > 0.9 )
                        {
                        curRGB.r = 1.0;
                        curRGB.g = 1.0;
                        curRGB.b = 1.0;
                        }
                    else
                        curRGB = curRGB * u * 0.4;
                }
                else
                    curRGB = float4( 0.0, 0.0, 0.0, 0.0 );
            
                return  float4(curRGB.x, curRGB.y, curRGB.z, 1.0);
            }
            
            ENDCG
        }
    }
}
