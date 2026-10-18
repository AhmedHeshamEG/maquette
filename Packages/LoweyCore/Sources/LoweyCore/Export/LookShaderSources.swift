import Foundation

/// Godot 4's shading language: the surface (bands in `light()`, rim in `fragment()`), the outline (the inverted hull,
/// a constant width on screen) and the material that joins them.
enum GodotLookShader {
    private static func f(_ value: Double) -> String { LookShaderNumbers.f(value) }

    static func surface(_ look: LookShaderNumbers, name: String) -> String {
        """
        // The \(name) Look from Maquette: light and shadow in bands, shadows that lean toward the sky's colour, a rim of
        // light, stepped highlights on glossy things. Use it in anything, commercial included (LICENSE.txt).
        shader_type spatial;

        uniform vec4 albedo : source_color = vec4(0.82, 0.48, 0.32, 1.0);
        uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
        uniform int bands : hint_range(2, 3) = \(look.bands);
        uniform float threshold : hint_range(0.0, 1.0) = \(f(look.threshold));
        uniform float mid_threshold : hint_range(0.0, 1.0) = \(f(look.midThreshold));
        uniform float edge_softness : hint_range(0.001, 0.2) = \(f(max(look.edgeSoftness, 0.001)));
        uniform vec4 shadow_tint : source_color = vec4(0.55, 0.66, 0.92, 1.0);
        uniform float shadow_hue_shift : hint_range(0.0, 1.0) = \(f(look.shadowHueShift));
        uniform float shadow_value : hint_range(0.0, 1.0) = \(f(look.shadowValue));
        uniform float shadow_saturation : hint_range(0.0, 1.0) = \(f(look.shadowSaturation));
        uniform float shadow_strength : hint_range(0.0, 1.0) = 0.55;
        uniform vec4 rim_color : source_color = vec4(1.0, 0.94, 0.84, 1.0);
        uniform float rim : hint_range(0.0, 1.0) = \(f(look.rim));
        uniform float rim_threshold : hint_range(0.0, 1.0) = \(f(look.rimThreshold));
        uniform float rim_softness : hint_range(0.001, 0.2) = \(f(max(look.rimSoftness, 0.001)));
        uniform bool glossy = false;
        uniform float specular : hint_range(0.0, 2.0) = \(f(look.specular));
        uniform float specular_size : hint_range(0.0, 1.0) = \(f(look.specularSize));
        uniform float specular_softness : hint_range(0.001, 0.2) = \(f(max(look.specularSoftness, 0.001)));
        uniform bool faceted = \(look.faceted);
        uniform bool clay = \(look.clay);

        \(helpers)

        void fragment() {
            ALBEDO = albedo.rgb * texture(albedo_texture, UV).rgb * COLOR.rgb;
            if (faceted) {
                vec3 flat_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
                NORMAL = dot(flat_normal, VIEW) < 0.0 ? -flat_normal : flat_normal;
            }
            float fresnel = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
            EMISSION = rim_color.rgb * smoothstep(rim_threshold - rim_softness, rim_threshold + rim_softness, fresnel) * rim * 0.6;
        }

        void light() {
            vec3 energy = LIGHT_COLOR / PI;
            float facing = dot(NORMAL, LIGHT);
            if (clay) {
                DIFFUSE_LIGHT += energy * clamp((facing + 0.1) / 1.1, 0.0, 1.0) * ATTENUATION * 0.95;
            } else {
                float level = band(clamp(facing * 0.5 + 0.5, 0.0, 1.0) * ATTENUATION);
                vec3 shade = shadow_color(ALBEDO) / max(ALBEDO, vec3(0.001)) * shadow_strength;
                DIFFUSE_LIGHT += energy * mix(shade, vec3(0.85), level);
                if (glossy) {
                    float power = mix(256.0, 12.0, specular_size);
                    float shine = pow(clamp(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0, 1.0), power);
                    SPECULAR_LIGHT += energy * smoothstep(0.5 - specular_softness, 0.5 + specular_softness, shine) * specular * level;
                }
            }
        }

        """
    }

    /// Colour turned in HSV, the shadow's colour and the bands (the Look's own recipe, as in the app's shader).
    static let helpers = """
    vec3 rgb_to_hsv(vec3 c) {
        vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
        vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
        vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
        float d = q.x - min(q.w, q.y);
        return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
    }

    vec3 hsv_to_rgb(vec3 c) {
        vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
        return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
    }

    // The shadow's colour: the same hue turned toward the sky's, darker and a little richer.
    vec3 shadow_color(vec3 base) {
        vec3 hsv = rgb_to_hsv(max(base, vec3(0.0)));
        vec3 sky = rgb_to_hsv(max(shadow_tint.rgb, vec3(0.0001)));
        float delta = sky.x - hsv.x;
        delta -= round(delta);
        hsv.x = fract(hsv.x + delta * shadow_hue_shift * clamp(sky.y * 1.5, 0.0, 1.0));
        hsv.y = clamp(hsv.y + shadow_saturation * (1.0 - hsv.y), 0.0, 1.0);
        hsv.z = hsv.z * (1.0 - shadow_value);
        return hsv_to_rgb(hsv);
    }

    float band(float x) {
        float lit = smoothstep(threshold - edge_softness, threshold + edge_softness, x);
        if (bands > 2) {
            return lit * mix(0.62, 1.0, smoothstep(mid_threshold - edge_softness, mid_threshold + edge_softness, x));
        }
        return lit;
    }
    """

    static func outline(_ look: LookShaderNumbers, name: String) -> String {
        let color = look.lineColor
        return """
        // The \(name) Look's lines from Maquette: the shape drawn again a little larger, inside out, so its edge shows
        // as a line of the same width at any distance. Use it in anything, commercial included (LICENSE.txt).
        shader_type spatial;
        render_mode unshaded, cull_front, shadows_disabled;

        uniform vec4 line_color : source_color = vec4(\(f(color.r)), \(f(color.g)), \(f(color.b)), 1.0);
        // Pixels at 1080p; wider on a larger screen.
        uniform float line_width : hint_range(0.0, 8.0) = \(f(look.lines ? look.lineWidth : 0));
        // A darkened line takes the thing's own colour, this much darker.
        uniform bool darkened = \(look.darkenedLines);
        uniform vec4 albedo : source_color = vec4(0.82, 0.48, 0.32, 1.0);
        uniform float darken : hint_range(0.0, 1.0) = \(f(look.darken));

        void vertex() {
            vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
            vec3 turned = mat3(PROJECTION_MATRIX) * (mat3(MODELVIEW_MATRIX) * NORMAL);
            vec2 outward = length(turned.xy) > 0.0001 ? normalize(turned.xy) : vec2(0.0);
            clip.xy += outward * line_width * 2.0 / 1080.0 * clip.w * vec2(VIEWPORT_SIZE.y / VIEWPORT_SIZE.x, 1.0);
            POSITION = clip;
        }

        void fragment() {
            ALBEDO = darkened ? albedo.rgb * (1.0 - darken) : line_color.rgb;
        }

        """
    }

    static func material(_ look: LookShaderNumbers, stem: String) -> String {
        """
        [gd_resource type="ShaderMaterial" load_steps=4 format=3]

        [ext_resource type="Shader" path="\(stem).gdshader" id="1_surface"]
        [ext_resource type="Shader" path="\(stem)_outline.gdshader" id="2_outline"]

        [sub_resource type="ShaderMaterial" id="ShaderMaterial_outline"]
        render_priority = 0
        shader = ExtResource("2_outline")

        [resource]
        render_priority = 0
        next_pass = SubResource("ShaderMaterial_outline")
        shader = ExtResource("1_surface")

        """
    }
}

/// Unity's Universal Render Pipeline: one shader with the lit pass (the main light, its shadows and the extra lights,
/// banded) and the outline pass.
enum UnityLookShader {
    private static func f(_ value: Double) -> String { LookShaderNumbers.f(value) }

    static func shader(_ look: LookShaderNumbers, name: String) -> String {
        let color = look.lineColor
        return """
        // The \(name) Look from Maquette for Unity's Universal Render Pipeline: light and shadow in bands, shadows that lean
        // toward the sky's colour, a rim of light, stepped highlights and the lines as an outline pass.
        // Use it in anything, commercial included (LICENSE.txt).
        Shader "Maquette/\(name)"
        {
            Properties
            {
                _BaseColor ("Colour", Color) = (0.82, 0.48, 0.32, 1)
                _BaseMap ("Texture", 2D) = "white" {}
                _Bands ("Bands", Range(2, 3)) = \(look.bands)
                _Threshold ("Threshold", Range(0, 1)) = \(f(look.threshold))
                _MidThreshold ("Mid threshold", Range(0, 1)) = \(f(look.midThreshold))
                _EdgeSoftness ("Edge softness", Range(0.001, 0.2)) = \(f(max(look.edgeSoftness, 0.001)))
                _ShadowTint ("Shadow tint (the sky)", Color) = (0.55, 0.66, 0.92, 1)
                _ShadowHueShift ("Shadow hue shift", Range(0, 1)) = \(f(look.shadowHueShift))
                _ShadowValue ("Shadow darkness", Range(0, 1)) = \(f(look.shadowValue))
                _ShadowSaturation ("Shadow richness", Range(0, 1)) = \(f(look.shadowSaturation))
                _ShadowStrength ("Shadow strength", Range(0, 1)) = 0.55
                _RimColor ("Rim colour", Color) = (1, 0.94, 0.84, 1)
                _Rim ("Rim", Range(0, 1)) = \(f(look.rim))
                _RimThreshold ("Rim threshold", Range(0, 1)) = \(f(look.rimThreshold))
                _RimSoftness ("Rim softness", Range(0.001, 0.2)) = \(f(max(look.rimSoftness, 0.001)))
                [Toggle] _Glossy ("Glossy", Float) = 0
                _Specular ("Highlight", Range(0, 2)) = \(f(look.specular))
                _SpecularSize ("Highlight size", Range(0, 1)) = \(f(look.specularSize))
                _SpecularSoftness ("Highlight softness", Range(0.001, 0.2)) = \(f(max(look.specularSoftness, 0.001)))
                [Toggle] _Clay ("Clay (smooth light)", Float) = \(look.clay ? 1 : 0)
                _LineColor ("Line colour", Color) = (\(f(color.r)), \(f(color.g)), \(f(color.b)), 1)
                _LineWidth ("Line width (pixels at 1080p)", Range(0, 8)) = \(f(look.lines ? look.lineWidth : 0))
                [Toggle] _Darkened ("Darkened lines", Float) = \(look.darkenedLines ? 1 : 0)
                _Darken ("Darken", Range(0, 1)) = \(f(look.darken))
            }

            SubShader
            {
                Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" }

                HLSLINCLUDE
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

                CBUFFER_START(UnityPerMaterial)
                    float4 _BaseColor; float4 _BaseMap_ST; float _Bands; float _Threshold; float _MidThreshold; float _EdgeSoftness;
                    float4 _ShadowTint; float _ShadowHueShift; float _ShadowValue; float _ShadowSaturation; float _ShadowStrength;
                    float4 _RimColor; float _Rim; float _RimThreshold; float _RimSoftness; float _Glossy; float _Specular;
                    float _SpecularSize; float _SpecularSoftness; float _Clay; float4 _LineColor; float _LineWidth; float _Darkened;
                    float _Darken;
                CBUFFER_END
                TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
                ENDHLSL
        \(UnityLookShader.litPass)
        \(UnityLookShader.outlinePass)
            }
            FallBack "Universal Render Pipeline/Unlit"
        }

        """
    }

    static let litPass = """
            Pass
            {
                Name "MaquetteLit"
                Tags { "LightMode" = "UniversalForward" }
                HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment Frag
                #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
                #pragma multi_compile _ _ADDITIONAL_LIGHTS
                #pragma multi_compile_fragment _ _SHADOWS_SOFT

                struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; float4 color : COLOR; };
                struct Varyings { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; float3 normalWS : TEXCOORD1;
                                  float2 uv : TEXCOORD2; float4 color : COLOR; };

                Varyings Vert(Attributes input)
                {
                    Varyings output;
                    VertexPositionInputs position = GetVertexPositionInputs(input.positionOS.xyz);
                    output.positionCS = position.positionCS;
                    output.positionWS = position.positionWS;
                    output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                    output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                    output.color = input.color;
                    return output;
                }

                float3 RgbToHsv(float3 c)
                {
                    float4 k = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
                    float4 p = lerp(float4(c.bg, k.wz), float4(c.gb, k.xy), step(c.b, c.g));
                    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
                    float d = q.x - min(q.w, q.y);
                    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
                }

                float3 HsvToRgb(float3 c)
                {
                    float3 p = abs(frac(c.xxx + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
                    return c.z * lerp(float3(1.0, 1.0, 1.0), saturate(p - 1.0), c.y);
                }

                float3 ShadowColor(float3 base)
                {
                    float3 hsv = RgbToHsv(max(base, 0.0));
                    float3 sky = RgbToHsv(max(_ShadowTint.rgb, 0.0001));
                    float delta = sky.x - hsv.x;
                    delta -= round(delta);
                    hsv.x = frac(hsv.x + delta * _ShadowHueShift * saturate(sky.y * 1.5));
                    hsv.y = saturate(hsv.y + _ShadowSaturation * (1.0 - hsv.y));
                    hsv.z = hsv.z * (1.0 - _ShadowValue);
                    return HsvToRgb(hsv);
                }

                float Band(float x)
                {
                    float lit = smoothstep(_Threshold - _EdgeSoftness, _Threshold + _EdgeSoftness, x);
                    if (_Bands > 2.5) { return lit * lerp(0.62, 1.0, smoothstep(_MidThreshold - _EdgeSoftness, _MidThreshold + _EdgeSoftness, x)); }
                    return lit;
                }

                float3 Shade(float3 base, float3 normal, float3 view, Light light)
                {
                    float facing = dot(normal, light.direction);
                    float visible = light.shadowAttenuation * light.distanceAttenuation;
                    if (_Clay > 0.5) { return base * light.color * saturate((facing + 0.1) / 1.1) * visible * 0.95; }
                    float level = Band(saturate(facing * 0.5 + 0.5) * visible);
                    float3 color = lerp(ShadowColor(base) * _ShadowStrength, base * 0.85, level) * light.color;
                    if (_Glossy > 0.5)
                    {
                        float shine = pow(saturate(dot(normal, normalize(light.direction + view))), lerp(256.0, 12.0, _SpecularSize));
                        color += light.color * smoothstep(0.5 - _SpecularSoftness, 0.5 + _SpecularSoftness, shine) * _Specular * level;
                    }
                    return color;
                }

                half4 Frag(Varyings input) : SV_Target
                {
                    float3 base = _BaseColor.rgb * SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * input.color.rgb;
                    float3 normal = normalize(input.normalWS);
                    float3 view = normalize(GetWorldSpaceViewDir(input.positionWS));
                    float3 color = Shade(base, normal, view, GetMainLight(TransformWorldToShadowCoord(input.positionWS)));
                    #ifdef _ADDITIONAL_LIGHTS
                    uint count = GetAdditionalLightsCount();
                    for (uint index = 0u; index < count; index++) { color += Shade(base, normal, view, GetAdditionalLight(index, input.positionWS)); }
                    #endif
                    color += base * SampleSH(normal) * 0.25;
                    float fresnel = 1.0 - saturate(dot(normal, view));
                    color += _RimColor.rgb * smoothstep(_RimThreshold - _RimSoftness, _RimThreshold + _RimSoftness, fresnel) * _Rim * 0.6;
                    return half4(color, 1.0);
                }
                ENDHLSL
            }
    """

    static let outlinePass = """
            Pass
            {
                Name "MaquetteOutline"
                Tags { "LightMode" = "SRPDefaultUnlit" }
                Cull Front
                HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment Frag

                struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
                struct Varyings { float4 positionCS : SV_POSITION; };

                Varyings Vert(Attributes input)
                {
                    Varyings output;
                    float4 clip = TransformObjectToHClip(input.positionOS.xyz);
                    float3 normalCS = mul((float3x3)UNITY_MATRIX_VP, TransformObjectToWorldNormal(input.normalOS));
                    float2 outward = length(normalCS.xy) > 0.0001 ? normalize(normalCS.xy) : float2(0.0, 0.0);
                    clip.xy += outward * _LineWidth * 2.0 / 1080.0 * clip.w * float2(_ScreenParams.y / _ScreenParams.x, 1.0);
                    output.positionCS = clip;
                    return output;
                }

                half4 Frag(Varyings input) : SV_Target
                {
                    float3 color = _Darkened > 0.5 ? _BaseColor.rgb * (1.0 - _Darken) : _LineColor.rgb;
                    return half4(color, 1.0);
                }
                ENDHLSL
            }
    """
}
