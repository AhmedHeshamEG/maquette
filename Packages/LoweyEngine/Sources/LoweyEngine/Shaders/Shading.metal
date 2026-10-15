// Shading.metal — the Look shader. One fragment function for every Look: toon (Ink, Comic, Sketch, Low-poly)
// and clay, chosen per object by its LookUniforms. See docs/SPEC.md §2.1 for the recipe.

#include "LoweyCommon.h"

struct ShadeOut {
    float4 color [[color(0)]];   // linear HDR, alpha = coverage
    float light [[color(1)]];    // the light term after banding (0 = shadow band), for halftone and the value view
};

constexpr sampler lw_linearSampler(coord::normalized, address::repeat, filter::linear, mip_filter::linear, max_anisotropy(4));
constexpr sampler lw_clampSampler(coord::normalized, address::clamp_to_edge, filter::linear);
constexpr sampler lw_shadowSampler(coord::normalized, address::clamp_to_edge, filter::linear, compare_func::less_equal);

// ---------------------------------------------------------------------------------------------------------------
// Sun shadows

static inline float lw_sunShadow(constant FrameUniforms &frame, depth2d_array<float> map, float3 world, float3 normal,
                                 float viewDepth, bool soft) {
    if (frame.sunColor.w < 0.5) { return 1.0; }
    uint cascade = viewDepth < frame.cascades.x ? 0u : 1u;
    if (viewDepth > frame.cascades.y) { return 1.0; }
    float texel = frame.cascades.z;
    // Normal offset: move the lookup off the surface by about a texel, scaled by the cascade's reach.
    float reach = cascade == 0u ? frame.cascades.x : frame.cascades.y;
    float3 offsetWorld = world + normal * (texel * reach * 1.5);
    float4 light = frame.shadowMatrices[cascade] * float4(offsetWorld, 1.0);
    float3 ndc = light.xyz / light.w;
    float2 uv = ndc.xy * float2(0.5, -0.5) + 0.5;
    if (any(uv < 0.0) || any(uv > 1.0) || ndc.z > 1.0) { return 1.0; }
    float reference = ndc.z - 0.0008;
    if (!soft) {
        return map.sample_compare(lw_shadowSampler, uv, cascade, reference);
    }
    float sum = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            sum += map.sample_compare(lw_shadowSampler, uv + float2(x, y) * texel * 1.5, cascade, reference);
        }
    }
    return sum / 9.0;
}

// ---------------------------------------------------------------------------------------------------------------
// Light model

struct SurfaceInput {
    float3 base;
    float alpha;
    float3 normal;
    float3 view;         // toward the camera
    float3 world;
    float viewDepth;
    float bias;
    float ao;            // 1 = open, 0 = fully occluded
    float shadow;        // sun visibility 0…1
    float smoothing;
    float rimStrength;
    bool glossy;
    float3 emissive;
    float roughness;     // painted roughness 0…1, or −1: the Look decides (unpainted surfaces)
    float metal;         // painted metal 0…1
};

/// The colour a highlight takes: white on a dielectric, the surface's own colour on metal.
static inline float3 lw_specularTint(SurfaceInput s) {
    return mix(float3(1.0), s.base, s.metal);
}

/// Hemisphere ambient: sky tint above, ground bounce below, softly quantised by the Look.
static inline float3 lw_ambient(float3 normal, constant FrameUniforms &frame, constant LookUniforms &look) {
    float t = normal.y * 0.5 + 0.5;
    float3 smooth = mix(frame.groundBounce.rgb, frame.ambient.rgb, t);
    float3 stepped = mix(frame.groundBounce.rgb, frame.ambient.rgb, smoothstep(0.42, 0.58, t));
    return mix(smooth, stepped, look.shadow.w) * frame.ambient.w;
}

/// The banded light level (0 shadow … 1 lit) of a light term x in 0…1.
static inline float lw_band(float x, constant LookUniforms &look) {
    float w = look.bands.w;
    float lit = smoothstep(look.bands.y - w, look.bands.y + w, x);
    if (look.bands.x > 2.5) {
        float top = smoothstep(look.bands.z - w, look.bands.z + w, x);
        return lit * mix(0.62, 1.0, top);
    }
    return lit;
}

static inline float lw_rim(SurfaceInput s, constant LookUniforms &look) {
    float fresnel = 1.0 - saturate(dot(s.normal, s.view));
    float strength = s.rimStrength >= 0.0 ? s.rimStrength : look.rim.x;
    return smoothstep(look.rim.y - look.rim.z, look.rim.y + look.rim.z, fresnel) * strength;
}

static inline float lw_specularShape(SurfaceInput s, float3 light, constant LookUniforms &look) {
    float3 h = normalize(light + s.view);
    if (s.roughness >= 0.0) {
        // Painted roughness: a smooth surface has a small bright highlight, a rough one none (still stepped by the Look).
        float power = mix(256.0, 8.0, s.roughness);
        float value = pow(saturate(dot(s.normal, h)), power);
        float strength = (1.0 - s.roughness) * (1.0 - s.roughness) * max(look.specular.x, 0.35) * 1.4;
        return smoothstep(0.5 - look.specular.z, 0.5 + look.specular.z, value) * strength;
    }
    if (!s.glossy) { return 0.0; }
    float power = mix(256.0, 12.0, saturate(look.specular.y));
    float value = pow(saturate(dot(s.normal, h)), power);
    return smoothstep(0.5 - look.specular.z, 0.5 + look.specular.z, value) * look.specular.x;
}

/// Point and spot lights, banded like the sun (toon) or smooth (clay).
static inline float3 lw_localLights(SurfaceInput s, constant FrameUniforms &frame, constant LookUniforms &look,
                                    constant LightData *lights) {
    float3 sum = 0.0;
    uint count = uint(frame.misc.x);
    for (uint index = 0; index < count; index++) {
        LightData light = lights[index];
        float3 direction;
        float falloff = 1.0;
        if (light.color.w > 1.5) {
            // Directional: a second sun without shadows.
            direction = -normalize(light.direction.xyz);
        } else {
            float3 toLight = light.position.xyz - s.world;
            float distance = length(toLight);
            float range = max(light.position.w, 0.01);
            if (distance > range) { continue; }
            direction = toLight / max(distance, 1e-4);
            falloff = 1.0 - smoothstep(range * 0.35, range, distance);
        }
        if (light.color.w > 0.5 && light.color.w < 1.5) {
            float cosine = dot(-direction, normalize(light.direction.xyz));
            falloff *= smoothstep(light.direction.w, light.params.x, cosine);
        }
        float x = saturate(dot(s.normal, direction) * 0.5 + 0.5 + s.bias * 0.5);
        float level = look.model.x > 0.5 ? saturate(dot(s.normal, direction)) : lw_band(x, look);
        sum += s.base * (1.0 - s.metal * 0.8) * light.color.rgb * level * falloff;
        sum += light.color.rgb * lw_specularTint(s) * lw_specularShape(s, direction, look) * falloff;
    }
    return sum;
}

/// The whole recipe. Returns colour and the banded light level.
static inline float2x4 lw_shadeSurface(SurfaceInput s, constant FrameUniforms &frame, constant LookUniforms &look,
                                constant LightData *lights) {
    float3 sun = frame.sunDirection.xyz;
    float3 ambient = lw_ambient(s.normal, frame, look);
    float contact = mix(1.0, s.ao, look.rim.w);
    float3 color;
    float level;
    float3 tint = lw_specularTint(s);
    float3 body = s.base * (1.0 - s.metal * 0.8);
    if (look.model.x > 0.5) {
        // Clay: smooth wrapped diffuse, soft shadows, sky light, restrained specular.
        float diffuse = saturate((dot(s.normal, sun) + 0.1) / 1.1) * s.shadow;
        level = diffuse;
        color = body * (frame.sunColor.rgb * diffuse * 0.95 + ambient * 0.85 * contact);
        color += frame.sunColor.rgb * tint * lw_specularShape(s, sun, look) * s.shadow;
    } else {
        // Toon: light term with the painted shadow bias, cast shadow multiplied in before banding.
        float x = saturate(dot(s.normal, sun) * 0.5 + 0.5 + s.bias * 0.5) * s.shadow;
        level = lw_band(x, look);
        float3 lit = body * (frame.sunColor.rgb * 0.85 + ambient * 0.25);
        float3 shade = lw_shadowColor(body, frame.ambient.rgb, look) * (ambient * 0.9 + 0.08) * contact;
        color = mix(shade, lit, level);
        color += frame.sunColor.rgb * tint * lw_specularShape(s, sun, look) * level;
    }
    if (s.metal > 0.0) {
        // Metal mirrors the sky around it, sharp when smooth, dull when rough.
        float3 reflected = reflect(-s.view, s.normal);
        float3 sky = mix(frame.skyHorizon.rgb, frame.skyTop.rgb, saturate(reflected.y));
        sky = mix(sky, frame.groundBounce.rgb, saturate(-reflected.y * 2.0));
        color += sky * s.base * s.metal * (1.0 - s.roughness * 0.7) * 0.6 * contact;
    }
    color += lw_localLights(s, frame, look, lights);
    color += mix(frame.skyHorizon.rgb, frame.sunColor.rgb, 0.3) * lw_rim(s, look) * 0.6;
    color += s.emissive;
    if (frame.fog.w > 0.0) {
        float fog = 1.0 - exp(-length(s.world - frame.cameraPosition.xyz) * frame.fog.w);
        color = mix(color, frame.fog.rgb, fog);
    }
    return float2x4(float4(color, s.alpha), float4(level, 0, 0, 0));
}

// ---------------------------------------------------------------------------------------------------------------
// Painted maps

/// The surface's frame from screen derivatives (no tangents in the mesh): x along the texture's u, y up the picture
/// (against v), as the baked normal maps are written.
static inline float3 lw_mapNormal(float3 n, float3 p, float2 uv, float3 local) {
    float3 dp1 = dfdx(p), dp2 = dfdy(p);
    float2 duv1 = dfdx(uv), duv2 = dfdy(uv);
    float3 dp2perp = cross(dp2, n), dp1perp = cross(n, dp1);
    float3 alongU = dp2perp * duv1.x + dp1perp * duv2.x;
    float3 alongV = dp2perp * duv1.y + dp1perp * duv2.y;
    float scale = rsqrt(max(max(dot(alongU, alongU), dot(alongV, alongV)), 1e-20));
    return normalize(alongU * scale * local.x - alongV * scale * local.y + n * local.z);
}

/// Painted bumps: the height's slope across the screen tilts the normal (Mikkelsen's surface gradient). One unit of
/// height is a centimetre.
static inline float3 lw_bumpNormal(float3 n, float3 p, float height) {
    float3 dpx = dfdx(p), dpy = dfdy(p);
    float dhx = dfdx(height), dhy = dfdy(height);
    float3 r1 = cross(dpy, n), r2 = cross(n, dpx);
    float det = dot(dpx, r1);
    float3 gradient = sign(det) * (dhx * r1 + dhy * r2);
    return normalize(abs(det) * n - gradient);
}

/// The painted maps on a surface: roughness and metal over its own, glow added, bumps and baked normals tilting it.
static inline void lw_applyMaps(thread SurfaceInput &s, SurfaceVaryings in, uint flags, texture2d<float> roughness, texture2d<float> metal,
                                texture2d<float> glow, texture2d<float> bumps, texture2d<float> normals) {
    float2 uv = in.uv;
    if ((flags & LW_FLAG_NORMALS) != 0u) {
        float3 local = normals.sample(lw_linearSampler, uv).xyz * 2.0 - 1.0;
        s.normal = lw_mapNormal(s.normal, in.worldPosition, uv, local);
    }
    if ((flags & LW_FLAG_BUMPS) != 0u) {
        float4 height = bumps.sample(lw_linearSampler, uv);
        s.normal = lw_bumpNormal(s.normal, in.worldPosition, (height.r - 0.5) * height.a * 0.01);
    }
    float base = s.glossy ? 0.35 : 0.85;
    if ((flags & LW_FLAG_ROUGHNESS) != 0u) {
        float4 painted = roughness.sample(lw_linearSampler, uv);
        s.roughness = mix(base, painted.r, painted.a);
    } else if ((flags & LW_FLAG_METAL) != 0u) {
        s.roughness = base;
    }
    if ((flags & LW_FLAG_METAL) != 0u) {
        float4 painted = metal.sample(lw_linearSampler, uv);
        s.metal = painted.r * painted.a;
    }
    if ((flags & LW_FLAG_GLOW) != 0u) {
        float4 painted = glow.sample(lw_linearSampler, uv);
        s.emissive += painted.rgb * painted.a;
    }
}

// ---------------------------------------------------------------------------------------------------------------
// Objects

static inline SurfaceInput lw_surfaceInput(SurfaceVaryings in, constant ObjectUniforms &object, constant FrameUniforms &frame,
                                           constant LookUniforms &look, texture2d<float> albedo, texture2d<float> ao,
                                           depth2d_array<float> shadowMap, bool frontFacing) {
    SurfaceInput s;
    float4 base = object.baseColor;
    if ((object.ids.z & LW_FLAG_TEXTURED) != 0u) {
        float4 texel = albedo.sample(lw_linearSampler, in.uv);
        if (look.model.y > 0.5) { texel.rgb = floor(texel.rgb * 6.0 + 0.5) / 6.0; }
        // Painted: the paint lies over the object's own colour; a model's texture multiplies it.
        if ((object.ids.z & LW_FLAG_PAINTED) != 0u) {
            base.rgb = mix(base.rgb, texel.rgb, texel.a);
        } else {
            base *= texel;
        }
    }
    s.base = base.rgb;
    s.alpha = base.a;
    float3 smoothNormal = normalize(in.worldNormal) * (frontFacing ? 1.0 : -1.0);
    float3 geometric = normalize(cross(dfdx(in.worldPosition), dfdy(in.worldPosition)));
    geometric = dot(geometric, smoothNormal) < 0.0 ? -geometric : geometric;
    s.smoothing = object.params.x >= 0.0 ? object.params.x : look.specular.w;
    s.normal = normalize(mix(geometric, smoothNormal, saturate(s.smoothing)));
    s.view = normalize(frame.cameraPosition.xyz - in.worldPosition);
    s.world = in.worldPosition;
    s.viewDepth = -in.viewPosition.z;
    s.bias = in.shadowBias;
    s.ao = ao.sample(lw_clampSampler, in.position.xy * frame.viewport.zw).r;
    s.shadow = lw_sunShadow(frame, shadowMap, in.worldPosition, s.normal, s.viewDepth, look.model.z > 0.5);
    s.rimStrength = object.params.y;
    s.glossy = object.params.z > 0.5;
    s.emissive = object.emissive.rgb;
    s.roughness = -1.0;
    s.metal = 0.0;
    return s;
}

fragment ShadeOut lw_shade(SurfaceVaryings in [[stage_in]], bool frontFacing [[front_facing]],
                           constant ObjectUniforms *objects [[buffer(LW_OBJECTS)]],
                           constant FrameUniforms &frame [[buffer(LW_FRAME)]],
                           constant LookUniforms *looks [[buffer(LW_LOOKS)]],
                           constant LightData *lights [[buffer(LW_LIGHTS)]],
                           texture2d<float> albedo [[texture(0)]],
                           texture2d<float> ao [[texture(1)]],
                           depth2d_array<float> shadowMap [[texture(2)]],
                           texture2d<float> roughness [[texture(3)]],
                           texture2d<float> metal [[texture(4)]],
                           texture2d<float> glow [[texture(5)]],
                           texture2d<float> bumps [[texture(6)]],
                           texture2d<float> normals [[texture(7)]]) {
    constant ObjectUniforms &object = objects[in.objectIndex];
    constant LookUniforms &look = looks[object.ids.y];
    ShadeOut out;
    if ((object.ids.z & LW_FLAG_UNLIT) != 0u) {
        float4 base = object.baseColor;
        if ((object.ids.z & LW_FLAG_TEXTURED) != 0u) {
            float4 texel = albedo.sample(lw_linearSampler, in.uv);
            if ((object.ids.z & LW_FLAG_PAINTED) != 0u) { base.rgb = mix(base.rgb, texel.rgb, texel.a); } else { base *= texel; }
        }
        out.color = float4(base.rgb + object.emissive.rgb, base.a);
        out.light = 1.0;
        return out;
    }
    if (!frontFacing && lw_sectionOn(frame)) {
        // Inside a cut solid: the cut face, flat, in the object's own colour a little darker, so it reads as solid.
        out.color = float4(object.baseColor.rgb * 0.62, 1.0);
        out.light = 1.0;
        return out;
    }
    SurfaceInput s = lw_surfaceInput(in, object, frame, look, albedo, ao, shadowMap, frontFacing);
    if ((object.ids.z & LW_FLAG_MAPS) != 0u) {
        lw_applyMaps(s, in, object.ids.z, roughness, metal, glow, bumps, normals);
    }
    float2x4 shaded = lw_shadeSurface(s, frame, look, lights);
    out.color = shaded[0];
    out.light = shaded[1].x;
    return out;
}

// ---------------------------------------------------------------------------------------------------------------
// Fur (U7)

/// A fur shell: each texture cell holds one strand at a jittered spot, as long as its own share of the length (and the
/// Fur map); a shell keeps the strand's cross-section at its height, thinning toward the tip. Roots are darker.
fragment ShadeOut lw_shadeFur(SurfaceVaryings in [[stage_in]],
                              constant ObjectUniforms *objects [[buffer(LW_OBJECTS)]],
                              constant FrameUniforms &frame [[buffer(LW_FRAME)]],
                              constant LookUniforms *looks [[buffer(LW_LOOKS)]],
                              constant LightData *lights [[buffer(LW_LIGHTS)]],
                              constant float4 &fur [[buffer(LW_CASCADE)]],
                              texture2d<float> albedo [[texture(0)]],
                              texture2d<float> ao [[texture(1)]],
                              depth2d_array<float> shadowMap [[texture(2)]],
                              texture2d<float> furMap [[texture(8)]]) {
    constant ObjectUniforms &object = objects[in.objectIndex];
    constant LookUniforms &look = looks[object.ids.y];
    float t = fur.w;
    float2 cell = in.uv * fur.z;
    float2 id = floor(cell);
    float2 jitter = float2(lw_hash(id), lw_hash(id + 17.0)) - 0.5;
    float2 local = fract(cell) - 0.5 - jitter * 0.4;
    float reach = (0.55 + 0.45 * lw_hash(id + 3.0)) * furMap.sample(lw_linearSampler, in.uv).r;
    if (t > reach) { discard_fragment(); }
    float radius = 0.42 * (1.0 - t / max(reach, 1e-3)) + 0.05;
    if (length(local) > radius) { discard_fragment(); }
    SurfaceInput s = lw_surfaceInput(in, object, frame, look, albedo, ao, shadowMap, true);
    s.base *= mix(0.45, 1.05, t);
    s.roughness = 0.9;
    float2x4 shaded = lw_shadeSurface(s, frame, look, lights);
    ShadeOut out;
    out.color = float4(shaded[0].rgb, 1.0);
    out.light = shaded[1].x;
    return out;
}

/// A hair card: strands as stripes across the strip, thinning toward the tip (v = 0), darker at the root (v = 1).
fragment ShadeOut lw_shadeFurCard(SurfaceVaryings in [[stage_in]], bool frontFacing [[front_facing]],
                                  constant ObjectUniforms *objects [[buffer(LW_OBJECTS)]],
                                  constant FrameUniforms &frame [[buffer(LW_FRAME)]],
                                  constant LookUniforms *looks [[buffer(LW_LOOKS)]],
                                  constant LightData *lights [[buffer(LW_LIGHTS)]],
                                  texture2d<float> albedo [[texture(0)]],
                                  texture2d<float> ao [[texture(1)]],
                                  depth2d_array<float> shadowMap [[texture(2)]]) {
    constant ObjectUniforms &object = objects[in.objectIndex];
    constant LookUniforms &look = looks[object.ids.y];
    float t = 1.0 - in.uv.y;
    float strands = in.uv.x * 7.0;
    float strand = floor(strands);
    float reach = 0.6 + 0.4 * lw_hash(float2(strand, 5.0));
    if (t > reach) { discard_fragment(); }
    float width = 0.36 * (1.0 - t / reach) + 0.04;
    if (abs(fract(strands) - 0.5) > width) { discard_fragment(); }
    SurfaceInput s = lw_surfaceInput(in, object, frame, look, albedo, ao, shadowMap, frontFacing);
    s.base *= mix(0.45, 1.05, t);
    s.roughness = 0.9;
    float2x4 shaded = lw_shadeSurface(s, frame, look, lights);
    ShadeOut out;
    out.color = float4(shaded[0].rgb, 1.0);
    out.light = shaded[1].x;
    return out;
}

/// A character outline: the Look's ink, or the part's own colour darkened (as the Look draws its lines).
fragment ShadeOut lw_shadeHull(SurfaceVaryings in [[stage_in]],
                               constant ObjectUniforms *objects [[buffer(LW_OBJECTS)]],
                               constant LookUniforms *looks [[buffer(LW_LOOKS)]]) {
    constant ObjectUniforms &object = objects[in.objectIndex];
    constant LookUniforms &look = looks[object.ids.y];
    float3 ink = look.lineInk.rgb;
    if (look.lines.w < 0.5) {
        float3 hsv = lw_rgbToHsv(max(object.baseColor.rgb, 0.0));
        hsv.y = saturate(hsv.y * 1.25 + 0.05);
        hsv.z *= (1.0 - look.lines.z);
        ink = lw_hsvToRgb(hsv);
    }
    ShadeOut out;
    out.color = float4(ink, 1.0);
    out.light = 1.0;
    return out;
}

// ---------------------------------------------------------------------------------------------------------------
// Ground: lit like every surface, faintly uneven, melting into the sky at its rim.

static inline float3 lw_skyColor(float3 direction, constant FrameUniforms &frame) {
    float elevation = asin(clamp(direction.y, -1.0, 1.0)) / (M_PI_F / 2.0);
    float3 color = elevation >= 0.0
        ? mix(frame.skyHorizon.rgb, frame.skyTop.rgb, pow(elevation, 0.55))
        : mix(frame.skyHorizon.rgb, frame.skyBottom.rgb, pow(-elevation, 0.35));
    return color;
}

fragment ShadeOut lw_shadeGround(SurfaceVaryings in [[stage_in]],
                                 constant FrameUniforms &frame [[buffer(LW_FRAME)]],
                                 constant LookUniforms *looks [[buffer(LW_LOOKS)]],
                                 constant LightData *lights [[buffer(LW_LIGHTS)]],
                                 constant float4 &groundColor [[buffer(LW_OBJECTS)]],
                                 texture2d<float> ao [[texture(1)]],
                                 depth2d_array<float> shadowMap [[texture(2)]]) {
    constant LookUniforms &look = looks[0];
    float2 p = in.worldPosition.xz;
    float grain = lw_noise(p * 0.16) * 0.65 + lw_noise(p * 0.53 + 17.0) * 0.35;
    SurfaceInput s;
    s.base = groundColor.rgb * (1.0 + (grain - 0.5) * 0.08);
    s.alpha = 1.0;
    s.normal = float3(0, 1, 0);
    s.view = normalize(frame.cameraPosition.xyz - in.worldPosition);
    s.world = in.worldPosition;
    s.viewDepth = -in.viewPosition.z;
    s.bias = 0.0;
    s.ao = ao.sample(lw_clampSampler, in.position.xy * frame.viewport.zw).r;
    s.shadow = lw_sunShadow(frame, shadowMap, in.worldPosition, s.normal, s.viewDepth, look.model.z > 0.5);
    s.smoothing = 1.0;
    s.rimStrength = 0.0;
    s.glossy = false;
    s.emissive = 0.0;
    s.roughness = -1.0;
    s.metal = 0.0;
    float2x4 shaded = lw_shadeSurface(s, frame, look, lights);
    float radius = max(frame.groundBounce.w, 1.0);
    float edge = smoothstep(radius * 0.45, radius * 0.97, length(p));
    float3 sky = lw_skyColor(normalize(in.worldPosition - frame.cameraPosition.xyz), frame);
    ShadeOut out;
    out.color = float4(mix(shaded[0].rgb, sky, edge), 1.0 - edge * frame.skyBottom.w);
    out.light = shaded[1].x;
    return out;
}

// ---------------------------------------------------------------------------------------------------------------
// Sky: a full-screen triangle behind everything (gradient, fog at the horizon, stars).

struct SkyVaryings {
    float4 position [[position]];
    float2 ndc;
};

vertex SkyVaryings lw_vertexSky(uint vertexID [[vertex_id]]) {
    float2 corner = float2((vertexID << 1) & 2, vertexID & 2);
    SkyVaryings out;
    out.ndc = corner * 2.0 - 1.0;
    out.position = float4(out.ndc, 0.0, 1.0);
    return out;
}

fragment ShadeOut lw_shadeSky(SkyVaryings in [[stage_in]], constant FrameUniforms &frame [[buffer(LW_FRAME)]]) {
    float4 far = frame.inverseViewProjection * float4(in.ndc, 0.0, 1.0);
    float4 near = frame.inverseViewProjection * float4(in.ndc, 1.0, 1.0);
    float3 direction = normalize(far.xyz / far.w - near.xyz / near.w);
    float3 color = lw_skyColor(direction, frame);
    float density = frame.skyTop.w;
    if (density > 0.0 && direction.y > 0.0) {
        float3 cell = floor(direction * 420.0);
        float star = lw_hash3(cell);
        float threshold = 1.0 - 0.004 * density * (0.4 + direction.y);
        if (star > threshold) {
            float brightness = 0.45 + 0.55 * lw_hash3(cell + 7.0);
            color = max(color, float3(brightness, brightness, brightness * 1.05));
        }
    }
    ShadeOut out;
    out.color = float4(color, 1.0 - frame.skyBottom.w);
    out.light = 1.0;
    return out;
}
