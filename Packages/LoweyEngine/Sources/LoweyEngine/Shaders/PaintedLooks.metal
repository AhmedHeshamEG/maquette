// PaintedLooks.metal — the paint pass of the painted Looks (L2, D-477: Painterly, Watercolour, Gouache). After the
// lines, at full resolution, so the lines are painted with everything else. Two kernels:
//   lw_paintTensor  the picture's local direction (a structure tensor of its brightness) and how sharply it changes;
//   lw_paintFilter  an anisotropic Kuwahara filter along that direction (strokes that follow the forms), bristle
//                   streaks along the strokes, then watercolour's wet edges, granulation and paper showing through.
// Each pixel takes its own Look's amounts (from the ID buffer), so a painted thing can stand in an Ink world.

#include "LoweyCommon.h"

struct PaintUniforms {
    float4 size;     // width, height, 1/width, 1/height
    float4 params;   // x = pixels per point (height / 1080), y = rings per sector (2 or 3), z = frame index, w = unused
};

constexpr sampler lw_paintSampler(coord::normalized, address::clamp_to_edge, filter::linear);

/// The Look a pixel is drawn in (the scene's for the sky and the ground).
static inline uint lw_paintLook(texture2d<uint, access::read> ids, uint2 gid) {
    uint id = ids.read(gid).r;
    return lw_idObject(id) == 0u ? 0u : lw_idLook(id);
}

kernel void lw_paintTensor(texture2d<float, access::sample> source [[texture(0)]],
                           texture2d<uint, access::read> ids [[texture(1)]],
                           texture2d<float, access::write> tensor [[texture(2)]],
                           constant PaintUniforms &u [[buffer(0)]],
                           constant LookUniforms *looks [[buffer(1)]],
                           uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uint(u.size.x) || gid.y >= uint(u.size.y)) { return; }
    constant LookUniforms &look = looks[lw_paintLook(ids, gid)];
    // Measured over a quarter of the stroke, so the direction is the form's, not the noise's.
    float step = max(look.paint.y * u.params.x * 0.25, 1.0);
    float2 uv = (float2(gid) + 0.5) * u.size.zw;
    float2 texel = u.size.zw * step;
    float l[9];
    int index = 0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            l[index++] = lw_luminance(source.sample(lw_paintSampler, uv + float2(x, y) * texel).rgb);
        }
    }
    float gx = (l[2] + 2.0 * l[5] + l[8]) - (l[0] + 2.0 * l[3] + l[6]);
    float gy = (l[6] + 2.0 * l[7] + l[8]) - (l[0] + 2.0 * l[1] + l[2]);
    tensor.write(float4(gx * gx, gy * gy, gx * gy, sqrt(gx * gx + gy * gy)), gid);
}

kernel void lw_paintFilter(texture2d<float, access::sample> source [[texture(0)]],
                           texture2d<float, access::sample> tensorTexture [[texture(1)]],
                           texture2d<uint, access::read> ids [[texture(2)]],
                           texture2d<float, access::write> output [[texture(3)]],
                           constant PaintUniforms &u [[buffer(0)]],
                           constant LookUniforms *looks [[buffer(1)]],
                           uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uint(u.size.x) || gid.y >= uint(u.size.y)) { return; }
    float2 uv = (float2(gid) + 0.5) * u.size.zw;
    float4 center = source.sample(lw_paintSampler, uv);
    constant LookUniforms &look = looks[lw_paintLook(ids, gid)];
    float strokes = look.paint.x, wet = look.paint.z, granulation = look.paint.w, paper = look.paper.x;
    if (strokes <= 0.0 && wet <= 0.0 && granulation <= 0.0 && paper <= 0.0) {
        output.write(center, gid);
        return;
    }
    // A blurred tensor (five taps) gives the strokes one direction over a whole form.
    float2 near = u.size.zw * max(look.paint.y * u.params.x * 0.5, 1.0);
    float4 t = tensorTexture.sample(lw_paintSampler, uv) * 2.0;
    t += tensorTexture.sample(lw_paintSampler, uv + float2(near.x, 0)) + tensorTexture.sample(lw_paintSampler, uv - float2(near.x, 0));
    t += tensorTexture.sample(lw_paintSampler, uv + float2(0, near.y)) + tensorTexture.sample(lw_paintSampler, uv - float2(0, near.y));
    t /= 6.0;
    float e = t.x, f = t.y, g = t.z;
    float root = sqrt(max((e - f) * (e - f) + 4.0 * g * g, 0.0));
    float l1 = (e + f + root) * 0.5, l2 = (e + f - root) * 0.5;
    // The direction the brush travels: across the brightness change, along the form.
    float2 along = float2(l1 - e, -g);
    along = dot(along, along) > 1e-10 ? normalize(along) : float2(1.0, 0.0);
    float anisotropy = (l1 + l2) > 1e-6 ? (l1 - l2) / (l1 + l2) : 0.0;
    float radius = max(look.paint.y * u.params.x, 1.0);
    float stretch = 1.0 + anisotropy;
    float2 axisA = along * radius * stretch, axisB = float2(-along.y, along.x) * radius / stretch;
    // Watercolour's edges wander a little (the paint bled while wet).
    float2 bleed = (float2(lw_noise(float2(gid) * 0.045), lw_noise(float2(gid) * 0.045 + 19.0)) - 0.5) * wet * 2.5 * u.size.zw;
    int rings = int(u.params.y + 0.5);
    float3 numerator = 0.0;
    float denominator = 0.0;
    for (int sector = 0; sector < 8; sector++) {
        float3 sum = 0.0, squares = 0.0;
        float count = 0.0;
        for (int ring = 1; ring <= rings; ring++) {
            float r = float(ring) / float(rings);
            for (int side = 0; side < 2; side++) {
                float angle = (float(sector) + 0.25 + 0.5 * float(side)) * (M_PI_F / 4.0);
                float2 offset = (axisA * cos(angle) + axisB * sin(angle)) * r * u.size.zw;
                float3 c = source.sample(lw_paintSampler, uv + bleed + offset).rgb;
                sum += c;
                squares += c * c;
                count += 1.0;
            }
        }
        float3 mean = sum / count;
        float3 variance = max(squares / count - mean * mean, 0.0);
        float spread = sqrt(variance.r + variance.g + variance.b) * 255.0;
        float weight = 1.0 / (1.0 + pow(spread, 8.0) * 1e-8);
        numerator += mean * weight;
        denominator += weight;
    }
    float3 painted = denominator > 0.0 ? numerator / denominator : center.rgb;
    // Bristles: faint streaks along the stroke, fixed to the picture so a still frame stays still.
    float2 bristleSpace = float2(dot(float2(gid), along), dot(float2(gid), float2(-along.y, along.x))) / max(radius, 1.0);
    float bristle = lw_noise(float2(bristleSpace.x * 0.25, bristleSpace.y * 3.0));
    painted *= 1.0 + (bristle - 0.5) * 0.12 * strokes;
    float3 color = mix(center.rgb, painted, saturate(strokes));
    float lum = lw_luminance(color);
    if (wet > 0.0) {
        // Pigment pools where a wash meets another.
        float edge = smoothstep(0.03, 0.2, t.w);
        color *= 1.0 - wet * 0.28 * edge;
    }
    if (granulation > 0.0) {
        // The pigment settles into the paper's grain, more where the paint is dark.
        float grain = lw_noise(float2(gid) * 0.4) * 0.6 + lw_noise(float2(gid) * 1.3) * 0.4;
        color *= 1.0 - granulation * 0.3 * (1.0 - saturate(lum)) * grain;
    }
    if (paper > 0.0) {
        // Light washes are thin: the paper shows through.
        color = mix(color, float3(1.0, 0.985, 0.95), paper * smoothstep(0.25, 1.0, lum) * 0.6);
    }
    output.write(float4(color, center.a), gid);
}
