Shader "Unlit/MatrixRainV2"
{
    Properties
    {
        _MainTex("Texture", 2D) = "white" {}

        // Custom Properties
        _Speed("Speed", float) = 1.0
        _RainColor("RainColor", Color) = (0.0, 1.0, 0.0, 1.0)
        _CharHeight("CharHeight", float) = 0.15
        _CharWidth("CharWidth", float) = 0.10
    }
    
    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            // Upgrade NOTE: excluded shader from OpenGL ES 2.0 because it uses non-square matrices
            #pragma exclude_renderers gles
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            UNITY_INSTANCING_BUFFER_START(Props)
                UNITY_DEFINE_INSTANCED_PROP(float, _CharWidth)
                UNITY_DEFINE_INSTANCED_PROP(float, _CharHeight)
                UNITY_DEFINE_INSTANCED_PROP(float, _Speed)
                UNITY_DEFINE_INSTANCED_PROP(float4, _RainColor)
            UNITY_INSTANCING_BUFFER_END(Props)

            sampler2D _MainTex;
            float4 _MainTex_ST;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_FOG_COORDS(1)
            };

            v2f vert(appdata v)
            {
                v2f o;
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o, o.vertex);
                UNITY_SETUP_INSTANCE_ID(o);
                return o;
            }

            #define iResolution _ScreenParams
            #define mod(x, y) (x-y*floor(x/y) )

            static int ITERATIONS = 40;   //use less value if you need more performance
            static float SPEED = UNITY_ACCESS_INSTANCED_PROP(Props, _Speed);

            static float STRIP_CHARS_MIN = 7.;
            static float STRIP_CHARS_MAX = 40.;
            static float STRIP_CHAR_HEIGHT = UNITY_ACCESS_INSTANCED_PROP(Props, _CharHeight);
            static float STRIP_CHAR_WIDTH = UNITY_ACCESS_INSTANCED_PROP(Props, _CharWidth);
            static float ZCELL_SIZE = 1. * (STRIP_CHAR_HEIGHT * STRIP_CHARS_MAX);  //the multiplier can't be less than 1.
            static float XYCELL_SIZE = 12. * STRIP_CHAR_WIDTH;  //the multiplier can't be less than 1.
            static float3 rainColor = UNITY_ACCESS_INSTANCED_PROP(Props, _RainColor);

            static int BLOCK_SIZE = 10;  //in cells
            static int BLOCK_GAP = 0;    //in cells

            static float PI = 3.14159265359;

            float hash(float v) {
                return frac(sin(v) * 43758.5453123);
            }

            float hash(float2 v) {
                return hash(dot(v, float2(5.3983, 5.4427)));
            }

            float2 hash2(float2 v)
            {
                return frac(sin(mul(float2x2(127.1, 311.7, 269.5, 183.3), v)) * 43758.5453123);
            }

            float4 hash4(float2 v)
            {
                float2 p1 = mul(float4x2(127.1, 311.7,
                    269.5, 183.3,
                    113.5, 271.9,
                    246.1, 124.6), v );
                float4 p = float4(p1.x, 1.0, p1.y, 0.5 );
                return frac(sin(p) * 43758.5453123);
            }

            float4 hash4(float3 v)
            {
                float3 p1 = mul(float4x3(127.1, 311.7, 74.7,
                    269.5, 183.3, 246.1,
                    113.5, 271.9, 124.6,
                    271.9, 269.5, 311.7), v);
                float4 p = float4(p1.x, p1.y, p1.z, 0.4 ) ;
                return frac(sin(p) * 43758.5453123);
            }

            float rune_line(float2 p, float2 a, float2 b) 
            {
                p -= a, b -= a;
                float h = clamp(dot(p, b) / dot(b, b), 0., 1.);   // proj coord on line
                return length(p - ( b * h ));                         // dist to segment
            }

            float rune(float2 U, float2 seed, float highlight)
            {
                float d = 100000.0;
                for (int i = 0; i < 4; i++)	// number of strokes
                {
                    float4 pos = hash4(seed);
                    seed += 1.;

                    // each rune touches the edge of its box on all 4 sides
                    if (i == 0) pos.y = .0;
                    if (i == 1) pos.x = .999;
                    if (i == 2) pos.x = .0;
                    if (i == 3) pos.y = .999;
                    // snap the random line endpoints to a grid 2x3
                    float4 snaps = float4(2, 3, 2, 3);
                    pos = (floor(pos * snaps) + .5) / snaps;

                    // if (pos.xy != pos.zw)  //filter out single points (when start and end are the same)
                    if( (pos.x != pos.z && pos.y != pos.w ))  //filter out single points (when start and end are the same)
                        d = min(d, rune_line(U, pos.xy, pos.zw + .001)); // closest line
                }
                return smoothstep(0.1, 0., d) + highlight * smoothstep(0.4, 0., d);
            }

            float random_char(float2 outer, float2 inner, float highlight) {
                float2 seed = float2(dot(outer, float2(269.5, 183.3)), dot(outer, float2(113.5, 271.9)));
                return rune(inner, seed, highlight);
            }

            // xy - horizontal, z - vertical
            float3 rain(float3 ro3, float3 rd3, float time) {
                float4 result = float4(0.0, 0.0, 0.0, 0.0);

                // normalized 2d projection
                float2 ro2 = ro3.xy;
                float2 rd2 = normalize( rd3.xy );

                // we use formulas `ro3 + rd3 * t3` and `ro2 + rd2 * t2`, `t3_to_t2` is a multiplier to convert t3 to t2
                bool prefer_dx = abs(rd2.x) > abs(rd2.y);
                float t3_to_t2 = prefer_dx ? rd3.x / rd2.x : rd3.y / rd2.y;

                // at first, horizontal space (xy) is divided into cells (which are columns in 3D)
                // then each xy-cell is divided into vertical cells (along z) - each of these cells contains one raindrop

                int3 cell_side = int3(step(0., rd3));      //for positive rd.x use cell side with higher x (1) as the next side, for negative - with lower x (0), the same for y and z
                int3 cell_shift = int3(sign(rd3));         //shift to move to the next cell

                //  move through xy-cells in the ray direction
                float t2 = 0.;  // the ray formula is: ro2 + rd2 * t2, where t2 is positive as the ray has a direction.
                int2 next_cell = int2(floor(ro2 / XYCELL_SIZE));  //first cell index where ray origin is located
                for (int i = 0; i < ITERATIONS; i++)
                {
                    //result = float4(0.3, 0.0, 0.0, 1.0);
                    int2 cell = next_cell;  //save cell value before changing
                    float t2s = t2;          //and t

                    //  find the intersection with the nearest side of the current xy-cell (since we know the direction, we only need to check one vertical side and one horizontal side)
                    float2 side = float2(next_cell + cell_side.xy) * XYCELL_SIZE;  //side.x is x coord of the y-axis side, side.y - y of the x-axis side
                    float2 t2_side = (side - ro2) / rd2;  // t2_side.x and t2_side.y are two candidates for the next value of t2, we need the nearest
                    if (t2_side.x < t2_side.y) {
                        t2 = t2_side.x;
                        next_cell.x += cell_shift.x;  //cross through the y-axis side
                    }
                     else 
                    {
                      t2 = t2_side.y;
                      next_cell.y += cell_shift.y;  //cross through the x-axis side
                    }
                    //now t2 is the value of the end point in the current cell (and the same point is the start value in the next cell)

                    //  gap cells
                    float2 cell_in_block = frac(float2(cell) / float(BLOCK_SIZE));
                    float gap = float(BLOCK_GAP) / float(BLOCK_SIZE);
                    if (cell_in_block.x < gap || cell_in_block.y < gap || (cell_in_block.x < (gap + 0.1) && cell_in_block.y < (gap + 0.1))) {
                        continue;
                    }
                    //result = float4(0.0, 0.0, 0.3, 1.0);
                    //  return to 3d - we have start and end points of the ray segment inside the column (t3s and t3e)
                    float t3s = t2s / t3_to_t2;

                    //  move through z-cells of the current column in the ray direction (don't need much to check, two nearest cells are enough)
                    float pos_z = ro3.z + rd3.z * t3s;
                    float xycell_hash = hash(float2(cell));
                    float z_shift = xycell_hash * 11. - time * (0.5 + xycell_hash * 1.0 + xycell_hash * xycell_hash * 1.0 + pow(xycell_hash, 16.) * 3.0);  //a different z shift for each xy column
                    float char_z_shift = floor(z_shift / STRIP_CHAR_HEIGHT);
                    z_shift = char_z_shift * STRIP_CHAR_HEIGHT;
                    int zcell = int(floor((pos_z - z_shift) / ZCELL_SIZE));  //z-cell index
                    for (int j = 0; j < 2; j++) {  //2 iterations is enough if camera doesn't look much up or down
                        //result = float4(0.0, 0.3, 0.3, 1.0);
                        //  calculate coordinates of the target (raindrop)
                        float4 cell_hash = hash4(float3(int3(cell, zcell)));
                        float4 cell_hash2 = frac(cell_hash * float4(127.1, 311.7, 271.9, 124.6));

                        float chars_count = cell_hash.w * (STRIP_CHARS_MAX - STRIP_CHARS_MIN) + STRIP_CHARS_MIN;
                        float target_length = chars_count * STRIP_CHAR_HEIGHT;
                        float target_rad = STRIP_CHAR_WIDTH / 2.;
                        float target_z = (float(zcell) * ZCELL_SIZE + z_shift) + cell_hash.z * (ZCELL_SIZE - target_length);
                        float2 target = float2(cell)*XYCELL_SIZE + target_rad + cell_hash.xy * (XYCELL_SIZE - target_rad * 2.);

                        //  We have a line segment (t0,t). Now calculate the distance between line segment and cell target (it's easier in 2d)
                        float2 s = target - ro2;
                        float tmin = dot(s, rd2);  //tmin - point with minimal distance to target
                        if (tmin >= t2s && tmin <= t2) {
                            float u = s.x * rd2.y - s.y * rd2.x;  //horizontal coord in the matrix strip
                            if (abs(u) < target_rad) {
                                u = (u / target_rad + 1.) / 2.;
                                float z = ro3.z + rd3.z * tmin / t3_to_t2;
                                float v = (z - target_z) / target_length;  //vertical coord in the matrix strip
                                if (v >= 0.0 && v < 1.0) {
                                    float c = floor(v * chars_count);  //symbol index relative to the start of the strip, with addition of char_z_shift it becomes an index relative to the whole cell
                                    float q = frac(v * chars_count);
                                    float2 char_hash = hash2(float2(c + char_z_shift, cell_hash2.x));
                                    if (char_hash.x >= 0.1 || c == 0.) {  //10% of missed symbols
                                        float time_factor = floor(c == 0. ? time * 5.0 :  //first symbol is changed fast
                                                time * (1.0 * cell_hash2.z +   //strips are changed sometime with different speed
                                                        cell_hash2.w * cell_hash2.w * 4. * pow(char_hash.y, 4.)));  //some symbols in some strips are changed relatively often
                                        float a = random_char(float2(char_hash.x, time_factor), float2(u,q), max(1., 3. - c / 2.) * 0.2);  //alpha
                                        a *= clamp((chars_count - 0.5 - c) / 2., 0., 1.);  //tail fade
                                        if (a > 0.) {
                                            float attenuation = 1. + pow(0.06 * tmin / t3_to_t2, 2.);
                                            float3 col = (c == 0. ? float3(0.67, 1.0, 0.82) : float3(0.25, 0.80, 0.40)) / attenuation;
                                            float a1 = result.a;
                                            result.a = a1 + (1. - a1) * a;
                                            result.xyz = (result.xyz * a1 + col * (1. - a1) * a) / result.a;
                                            if (result.a > 0.98)
                                            {
                                                result.x = rainColor.x; result.y = rainColor.y; result.z = rainColor.z;//  yz;
                                                return result.xyz;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // not found in this cell - go to next vertical cell
                        zcell += cell_shift.z;
                    }
                    // go to next horizontal cell
                }

                return mul( result.xyz, result.a );
            }

            fixed4 frag(v2f i) : SV_Target
            {
                if (STRIP_CHAR_WIDTH > XYCELL_SIZE || STRIP_CHAR_HEIGHT * STRIP_CHARS_MAX > ZCELL_SIZE) {
                    return  float4(1., 1., 0., 1.);
                }
                //float2 uv = i.uv; // (i.uv.xy * 2. - iResolution.xy) / iResolution.y;
                float2 uv = i.uv; //  (i.uv.xy * 2. - iResolution.xy) / iResolution.y;

                float time = _Time.y * SPEED;

                float level1_size = float(BLOCK_SIZE) * XYCELL_SIZE;
                float level2_size = 4. * level1_size;
                float gap_size = float(BLOCK_GAP) * XYCELL_SIZE;

                float3 ro = float3(gap_size / 2., gap_size / 2., 0.);
                float3 rd = float3(uv.x, 2.0, uv.y);
                float3 p = float3(1.0, 1.0, 1.0 );
                ro.xy += level1_size * p;

                ro += rd * 0.2;
                rd = normalize(rd);

                float3 col = rain(ro, rd, time);

                return float4(col.r, col.g, col.b, 1.);
            }
ENDCG
}
    }
}
