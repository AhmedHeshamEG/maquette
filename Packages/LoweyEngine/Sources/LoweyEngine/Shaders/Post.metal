// Post.metal — everything after the lines: bloom, lens (blur or misregistration + chromatic aberration), the Look's
// print language and finish, the project's Finish, and tone mapping. Preview and export run exactly these kernels.

#include "LoweyCommon.h"

struct PostUniforms {
    float4 size;       // width, height, 1/width, 1/height
    float4 grade;      // x = exposure multiplier, y = contrast, z = saturation, w = temperature
    float4 bloom;      // x = intensity, y = threshold, z = scene Look bloom, w = unused
    float4 film;       // x = vignette, y = grain, z = chromatic aberration, w = retro
    float4 texture;    // x = kind (0 none, 1 paper, 2 collage, 3 old film), y = strength, z = frame, w = unused
    float4 lens;       // x = CoC pixels per unit of |1/focus − 1/d|, y = 1/focus, z = max CoC (px), w = mode (0 off, 1 blur, 2 misregistration)
    float4 pixels;     // x = pixels per point (height / 1080), y = frame index, z = boil step, w = unused
    float4 air;        // x = haze density (per metre), y = god rays, zw = the sun on the frame (0…1 from the top left)
    float4 airColor;   // haze colour (linear), w = how much the sun faces the camera
    float4 sunGlow;    // the sun's colour (linear), w = 1 for an HDR frame (highlights kept past white)
    float4 print;      // x = Ben-Day dots, y = pixel block (px, 0 = off), z = colour levels (Pixel), w = unused (L2)
};

constexpr sampler lw_postSampler(coord::normalized, address::clamp_to_edge, filter::linear);
constexpr sampler lw_pointSampler(coord::normalized, address::clamp_to_edge, filter::nearest);

// ---------------------------------------------------------------------------------------------------------------
// Bloom: soft-threshold prefilter at half size, a mip chain down, tent upsampling back up.

kernel void lw_bloomPrefilter(texture2d<float, access::sample> source [[texture(0)]],
                              texture2d<float, access::write> output [[texture(1)]],
                              constant PostUniforms &u [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
    float2 texel = 1.0 / float2(output.get_width(), output.get_height());
    float2 uv = (float2(gid) + 0.5) * texel;
    float3 sum = 0.0;
    for (int y = -1; y <= 1; y += 2) {
        for (int x = -1; x <= 1; x += 2) {
            sum += source.sample(lw_postSampler, uv + float2(x, y) * texel * 0.25).rgb;
        }
    }
    float3 color = sum * 0.25;
    float brightness = max(color.r, max(color.g, color.b));
    float knee = u.bloom.y * 0.5;
    float soft = clamp(brightness - u.bloom.y + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 1e-4);
    float contribution = max(soft, brightness - u.bloom.y) / max(brightness, 1e-4);
    output.write(float4(color * contribution, 1.0), gid);
}

kernel void lw_bloomDown(texture2d<float, access::sample> source [[texture(0)]],
                         texture2d<float, access::write> output [[texture(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
    float2 texel = 1.0 / float2(source.get_width(), source.get_height());
    float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
    float3 a = source.sample(lw_postSampler, uv + texel * float2(-1, -1)).rgb;
    float3 b = source.sample(lw_postSampler, uv + texel * float2(1, -1)).rgb;
    float3 c = source.sample(lw_postSampler, uv + texel * float2(-1, 1)).rgb;
    float3 d = source.sample(lw_postSampler, uv + texel * float2(1, 1)).rgb;
    float3 e = source.sample(lw_postSampler, uv).rgb;
    output.write(float4((a + b + c + d) * 0.125 + e * 0.5, 1.0), gid);
}

kernel void lw_bloomUp(texture2d<float, access::sample> smaller [[texture(0)]],
                       texture2d<float, access::read> current [[texture(1)]],
                       texture2d<float, access::write> output [[texture(2)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
    float2 texel = 1.0 / float2(smaller.get_width(), smaller.get_height());
    float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
    float3 sum = smaller.sample(lw_postSampler, uv).rgb * 4.0;
    sum += (smaller.sample(lw_postSampler, uv + float2(texel.x, 0)).rgb + smaller.sample(lw_postSampler, uv - float2(texel.x, 0)).rgb
        + smaller.sample(lw_postSampler, uv + float2(0, texel.y)).rgb + smaller.sample(lw_postSampler, uv - float2(0, texel.y)).rgb) * 2.0;
    sum += smaller.sample(lw_postSampler, uv + texel).rgb + smaller.sample(lw_postSampler, uv - texel).rgb
        + smaller.sample(lw_postSampler, uv + float2(texel.x, -texel.y)).rgb + smaller.sample(lw_postSampler, uv + float2(-texel.x, texel.y)).rgb;
    output.write(float4(current.read(gid).rgb + sum / 16.0, 1.0), gid);
}

// ---------------------------------------------------------------------------------------------------------------
// Lens: depth of field as blur (most Looks) or as colour misregistration (Comic), plus chromatic aberration.

kernel void lw_lens(texture2d<float, access::sample> source [[texture(0)]],
                    texture2d<float, access::read> normalDepth [[texture(1)]],
                    texture2d<float, access::write> output [[texture(2)]],
                    constant PostUniforms &u [[buffer(0)]],
                    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uint(u.size.x) || gid.y >= uint(u.size.y)) { return; }
    float2 uv = (float2(gid) + 0.5) * u.size.zw;
    float4 center = source.sample(lw_pointSampler, uv);
    float depth = normalDepth.read(gid).w;
    float coc = 0.0;
    if (u.lens.w > 0.5) {
        float inverse = depth > 0.0 && depth < 1e5 ? 1.0 / depth : 0.0;
        coc = min(abs(u.lens.y - inverse) * u.lens.x, u.lens.z);
    }
    float3 color = center.rgb;
    if (u.lens.w > 1.5 && coc > 0.3) {
        // Misregistration: the colour plates slip apart where the lens would blur.
        float2 offset = float2(coc, coc * 0.35) * u.size.zw;
        color.r = source.sample(lw_postSampler, uv + offset).r;
        color.b = source.sample(lw_postSampler, uv - offset).b;
    } else if (u.lens.w > 0.5 && coc > 0.5) {
        float3 sum = color;
        float weight = 1.0;
        for (int tap = 0; tap < 16; tap++) {
            float t = (float(tap) + 0.5) / 16.0;
            float angle = float(tap) * 2.399963;
            float2 offset = float2(cos(angle), sin(angle)) * sqrt(t) * coc * u.size.zw;
            sum += source.sample(lw_postSampler, uv + offset).rgb;
            weight += 1.0;
        }
        color = sum / weight;
    }
    if (u.film.z > 0.0) {
        float2 fromCenter = uv - 0.5;
        float spread = u.film.z * 0.008;
        color.r = mix(color.r, source.sample(lw_postSampler, 0.5 + fromCenter * (1.0 + spread)).r, 1.0);
        color.b = mix(color.b, source.sample(lw_postSampler, 0.5 + fromCenter * (1.0 - spread)).b, 1.0);
    }
    output.write(float4(color, center.a), gid);
}

// ---------------------------------------------------------------------------------------------------------------
// Look & finish: halftone in the shadow band, bloom, tone mapping, grade, Sketch's desaturation (accents keep
// their colour), paper, the project's Finish (retro, paper / collage / film textures, vignette, grain).

static inline float lw_halftone(float2 pixel, float darkness, float spacing, float amount) {
    float2x2 rotation = float2x2(float2(0.7071, 0.7071), float2(-0.7071, 0.7071));
    float2 cell = rotation * pixel / spacing;
    float2 local = fract(cell) - 0.5;
    float radius = sqrt(saturate(darkness)) * 0.62 * amount;
    return 1.0 - smoothstep(radius - 0.08, radius + 0.08, length(local));
}

/// Hatched lines in the shadow band: one direction as it darkens, crossed where it's darkest; each line thickens with
/// the darkness, as a pen presses harder.
static inline float lw_hatch(float2 pixel, float darkness, float spacing, float amount) {
    float along = (pixel.x + pixel.y) / spacing;
    float width = saturate(darkness) * 0.42 * amount;
    float first = 1.0 - smoothstep(width - 0.06, width + 0.06, abs(fract(along) - 0.5));
    float crossed = (pixel.x - pixel.y) / spacing;
    float deep = smoothstep(0.55, 0.85, darkness);
    float second = (1.0 - smoothstep(width * deep - 0.06, width * deep + 0.06, abs(fract(crossed) - 0.5))) * deep;
    return max(first, second);
}

static inline float3 lw_grade(float3 color, constant PostUniforms &u, constant LookUniforms &look, bool accent) {
    // Contrast around mid grey, saturation, temperature.
    color = (color - 0.5) * (1.0 + u.grade.y * 0.5) + 0.5;
    float luma = lw_luminance(color);
    float saturation = 1.0 + u.grade.z;
    if (!(accent && look.grade.w > 0.5)) { saturation += look.finish.w; }
    color = mix(float3(luma), color, max(saturation, 0.0));
    color *= float3(1.0 + u.grade.w * 0.1, 1.0, 1.0 - u.grade.w * 0.12);
    // Lift / gamma / gain.
    color = color * (1.0 + look.grade.z) + look.grade.x * (1.0 - color);
    color = pow(max(color, 0.0), float3(1.0 / max(1.0 + look.grade.y, 0.1)));
    return color;
}

/// Haze and god rays (F1): far things fade into the haze, which glows on the sun's side of the frame; shafts stream from
/// the sun past whatever stands in front of the sky (screen space: rays from the sun's place on the frame).
static inline float3 lw_air(float3 color, float2 uv, texture2d<float, access::sample> normalDepth, constant PostUniforms &u) {
    float depth = normalDepth.sample(lw_pointSampler, uv).w;
    bool sky = !(depth < 1e5);
    float2 sun = u.air.zw;
    float2 toSun = (sun - uv) * float2(u.size.x * u.size.w, 1.0);
    float glow = exp(-dot(toSun, toSun) / 0.09) * u.airColor.w;
    if (u.air.x > 0.0) {
        float thickness = (1.0 - exp(-(sky ? 300.0 : depth) * u.air.x)) * (sky ? 0.55 : 1.0);
        color = mix(color, u.airColor.rgb + u.sunGlow.rgb * glow * 0.6, thickness);
    }
    if (u.air.y > 0.0 && u.airColor.w > 0.0) {
        float2 step = (sun - uv) / 24.0;
        float2 p = uv;
        float lit = 0.0;
        float decay = 1.0;
        for (int tap = 0; tap < 24; tap++) {
            p += step;
            if (any(p < 0.0) || any(p > 1.0)) { break; }
            lit += (normalDepth.sample(lw_pointSampler, p).w < 1e5 ? 0.0 : 1.0) * decay;
            decay *= 0.94;
        }
        color += u.sunGlow.rgb * (lit / 12.0) * u.air.y * u.airColor.w * (0.35 + glow) * 0.6;
    }
    return color;
}

/// Ben-Day dots (L2): flat colour printed as dots of ink on paper, bigger where the colour is darker.
static inline float3 lw_benDay(float3 color, float2 pixel, constant LookUniforms &look, constant PostUniforms &u) {
    float spacing = max(look.comic.y, 4.0) * 1.15 * u.pixels.x;
    float2x2 rotation = float2x2(float2(0.9659, 0.2588), float2(-0.2588, 0.9659));
    float2 local = fract(rotation * pixel / spacing) - 0.5;
    float coverage = saturate(1.25 - lw_luminance(color) * 0.9);
    float radius = sqrt(coverage) * 0.6;
    float inked = 1.0 - smoothstep(radius - 0.06, radius + 0.06, length(local));
    float3 printed = mix(float3(1.0, 0.97, 0.9), color, inked);
    return mix(color, printed, u.print.x);
}

/// Print textures (L2): 4 newsprint (yellowed, fibrous, blacks lifted), 5 risograph (grain, few levels, warm paper),
/// 6 canvas (a woven tooth).
static inline float3 lw_printTexture(float3 color, uint2 gid, float kind, constant PostUniforms &u) {
    float strength = u.texture.y;
    float2 p = float2(gid);
    if (kind < 4.5) {
        float blotch = lw_noise(p / (u.size.y / 120.0) + 11.0);
        color *= (1.0 - strength * (0.14 - 0.2 * blotch)) * float3(0.98, 0.95, 0.84);
        color *= 1.0 - strength * 0.08 * lw_noise(p * float2(0.08, 1.6));
        color = color * (1.0 - 0.08 * strength) + 0.04 * strength;
        return mix(float3(lw_luminance(color)), color, 1.0 - 0.2 * strength);
    }
    if (kind < 5.5) {
        float grain = lw_hash(p * 0.5);
        color *= 1.0 - strength * 0.22 * (grain - 0.3);
        float3 stepped = floor(pow(max(color, 0.0), 1.0 / 2.2) * 5.0 + 0.5) / 5.0;
        color = mix(color, pow(stepped, 2.2), strength * 0.7);
        return color * mix(float3(1.0), float3(1.0, 0.97, 0.93), strength);
    }
    float spacing = max(3.0 * u.pixels.x, 2.0);
    float weave = sin(p.x * M_PI_F / spacing) * sin(p.y * M_PI_F / spacing);
    color *= 1.0 - strength * 0.1 * (0.5 + 0.5 * weave);
    return color * (1.0 - strength * 0.05 * lw_noise(p * 0.9));
}

kernel void lw_finish(texture2d<float, access::sample> source [[texture(0)]],
                      texture2d<float, access::sample> light [[texture(1)]],
                      texture2d<uint, access::read> ids [[texture(2)]],
                      texture2d<float, access::sample> bloom [[texture(3)]],
                      texture2d<float, access::write> output [[texture(4)]],
                      texture2d<float, access::sample> normalDepth [[texture(5)]],
                      constant PostUniforms &u [[buffer(0)]],
                      constant LookUniforms *looks [[buffer(1)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uint(u.size.x) || gid.y >= uint(u.size.y)) { return; }
    float2 uv = (float2(gid) + 0.5) * u.size.zw;
    float2 pixel = float2(gid);
    // Under the Pixel Look every mark (grain, dots, paper, vignette) is one per block, so a block stays one colour.
    float2 spot = u.print.y > 1.0 ? floor(pixel / u.print.y) * u.print.y : pixel;
    // Retro's chunky pixels, and the Pixel Look's blocks (L2): read at the block's centre, fewer colours below.
    float block = u.film.w > 0.0 ? max(2.0, u.size.y / 540.0 * (2.0 + u.film.w * 6.0)) : 0.0;
    block = max(block, u.print.y);
    if (block > 1.0) {
        pixel = (floor(pixel / block) + 0.5) * block;
        uv = pixel * u.size.zw;
    }
    float4 sampled = source.sample(lw_pointSampler, uv);
    uint id = ids.read(uint2(clamp(pixel, float2(0), u.size.xy - 1.0))).r;
    constant LookUniforms &look = looks[lw_idObject(id) == 0u ? 0u : lw_idLook(id)];
    bool accent = (lw_idFlags(id) & LW_FLAG_ACCENT) != 0u;
    float3 color = sampled.rgb;
    // Halftone dots in the shadow band.
    if (look.comic.x > 0.0 && lw_idObject(id) != 0u) {
        float level = light.sample(lw_postSampler, uv).r;
        float darkness = 1.0 - smoothstep(0.0, 0.5, level);
        float dots = lw_halftone(spot, darkness, look.comic.y * u.pixels.x, look.comic.x);
        color = mix(color, color * 0.55, dots * darkness);
    }
    // Hatched lines in the shadow band.
    if (look.lineShape.w > 0.0 && lw_idObject(id) != 0u) {
        float level = light.sample(lw_postSampler, uv).r;
        float darkness = 1.0 - smoothstep(0.0, 0.5, level);
        float strokes = lw_hatch(spot, darkness, max(look.comic.y, 3.0) * u.pixels.x, look.lineShape.w);
        color = mix(color, color * 0.45, strokes * darkness);
    }
    if (u.air.x > 0.0 || u.air.y > 0.0) { color = lw_air(color, uv, normalDepth, u); }
    color += bloom.sample(lw_postSampler, uv).rgb * (u.bloom.x + u.bloom.z);
    // An HDR frame keeps its highlights past white (the encoder's HLG holds them); SDR rolls them off.
    bool hdr = u.sunGlow.w > 0.5;
    color = hdr ? clamp(color * u.grade.x, 0.0, 3.78) : lw_softClip(color * u.grade.x);
    color = lw_grade(color, u, look, accent);
    if (u.print.x > 0.0 && normalDepth.sample(lw_pointSampler, uv).w < 1e5) { color = lw_benDay(color, pixel, look, u); }
    if (u.print.z > 1.0) {
        // The Pixel Look's few colours, stepped as the eye sees them and ordered-dithered block by block, as pixel artists
        // do, so dark and in-between colours keep their hue instead of falling to the nearest step.
        const float bayer[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
        uint2 cell = uint2(spot / max(u.print.y, 1.0)) & 3u;
        float threshold = (bayer[cell.y * 4u + cell.x] + 0.5) / 16.0 - 0.5;
        float levels = u.print.z - 1.0;
        float3 display = saturate(floor(pow(max(color, 0.0), 1.0 / 2.2) * levels + 0.5 + threshold) / levels);
        color = pow(display, 2.2);
    }
    // Paper: faint grain and a warm tint (Comic's print, Sketch's sheet).
    if (look.finish.x > 0.0 || look.finish.y > 0.0) {
        float fibre = lw_noise(spot * 0.9) * 0.5 + lw_noise(spot * 0.11) * 0.5;
        color *= 1.0 - look.finish.x * 0.08 * fibre;
        color = mix(color, color * float3(1.0, 0.95, 0.82), look.finish.y * 0.6);
    }
    float kind = u.texture.x;
    if (kind > 3.5 && u.texture.y > 0.0) { color = lw_printTexture(color, uint2(spot), kind, u); }
    if (kind > 0.5 && kind < 3.5 && u.texture.y > 0.0) {
        float seed = kind > 2.5 ? u.texture.z : 7.0;
        float blotch = lw_noise(spot / (u.size.y / 90.0) + seed * 3.1);
        float tone = 1.0 - u.texture.y * (0.3 - 0.35 * blotch);
        color *= tone * float3(1.0, 0.97, 0.9);
        if (kind > 1.5 && kind < 2.5) { color = floor(color * max(5.0, 12.0 - u.texture.y * 6.0) + 0.5) / max(5.0, 12.0 - u.texture.y * 6.0); }
        if (kind > 2.5) {
            color *= 1.0 + (lw_hash(float2(u.texture.z, 1.0)) - 0.5) * 0.24 * u.texture.y;
            float scratchX = lw_hash(float2(u.texture.z, 3.0)) * u.size.x;
            if (abs(float(gid.x) - scratchX) < max(u.size.x / 900.0, 1.0) && lw_hash(float2(u.texture.z, 5.0)) < 0.6) {
                color = mix(color, float3(1.0, 1.0, 0.95), 0.35 * u.texture.y);
            }
        }
    }
    if (u.film.w > 0.0) {
        float levels = max(4.0, 24.0 - u.film.w * 18.0);
        color = floor(color * levels + 0.5) / levels;
    }
    float vignette = max(u.film.x, look.finish.z);
    if (vignette > 0.0) {
        float2 fromCenter = (spot * u.size.zw - 0.5) * float2(u.size.x * u.size.w, 1.0);
        color *= 1.0 - vignette * smoothstep(0.35, 1.05, length(fromCenter) * 1.2);
    }
    if (u.film.y > 0.0) {
        float noise = lw_hash(spot + u.pixels.y * 17.0) - 0.5;
        color = saturate(color + noise * u.film.y * 0.12);
    }
    output.write(float4(hdr ? clamp(color, 0.0, 3.78) : saturate(color), sampled.a), gid);
}
