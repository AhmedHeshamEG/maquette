// GroundSurfaces.h — real grounds (L2, D-489): what the floor is made of, drawn from where each point is, so a ground
// has no texture to load, no seam and no repeat to spot, and takes the Look's light and bands like everything on it.
// Kinds follow Core's GroundSurface: 1 desert, 2 grass, 3 snow, 4 rock, 5 sand, 6 pavement, 7 water's edge,
// 8 room floor (0 is the plain floor).

#pragma once
#include "LoweyCommon.h"

struct GroundSample {
    float3 color;
    float3 normal;
    float roughness;   // −1: the Look decides
};

/// Value noise with its slope (for tilting the normal along a pattern).
static inline float2 lw_noiseSlope(float2 p) {
    float e = 0.05;
    return float2(lw_noise(p + float2(e, 0)) - lw_noise(p - float2(e, 0)), lw_noise(p + float2(0, e)) - lw_noise(p - float2(0, e))) / (2.0 * e);
}

/// A normal tilted by a height field's slope (in the ground's x and z).
static inline float3 lw_tilted(float2 slope, float amount) {
    return normalize(float3(-slope.x * amount, 1.0, -slope.y * amount));
}

static inline GroundSample lw_groundSurface(float2 p, int kind, float3 base, float time) {
    GroundSample g;
    g.color = base;
    g.normal = float3(0, 1, 0);
    g.roughness = -1.0;
    if (kind == 1) {
        // Desert: long dunes, wind ripples across them, sand a shade lighter on the crests.
        float dune = sin(p.x * 0.18 + lw_noise(p * 0.05) * 4.0) * 0.5 + 0.5;
        float ripple = sin(dot(p, float2(0.9, 0.45)) * 7.0 + lw_noise(p * 0.6) * 3.0);
        g.color = base * mix(0.86, 1.08, dune) * (1.0 + ripple * 0.02);
        g.normal = lw_tilted(float2(cos(p.x * 0.18) * 0.18, 0.0) + float2(0.9, 0.45) * ripple * 0.02, 1.6);
    } else if (kind == 2) {
        // Grass: clumps of two greens, fine blades, the odd darker patch.
        float clump = lw_noise(p * 0.7) * 0.6 + lw_noise(p * 2.3) * 0.4;
        float blades = lw_hash(floor(p * 18.0));
        g.color = base * mix(0.78, 1.14, clump) * mix(0.93, 1.05, blades);
        g.color = mix(g.color, base * float3(0.86, 0.95, 0.7), smoothstep(0.62, 0.8, lw_noise(p * 0.15)));
        g.normal = lw_tilted(lw_noiseSlope(p * 2.3), 0.12);
    } else if (kind == 3) {
        // Snow: soft drifts and a glint here and there.
        float drift = lw_noise(p * 0.12) * 0.7 + lw_noise(p * 0.5) * 0.3;
        g.color = base * mix(0.93, 1.02, drift);
        if (lw_hash(floor(p * 40.0)) > 0.995) { g.color = min(g.color * 1.25, float3(1.4)); }
        g.normal = lw_tilted(lw_noiseSlope(p * 0.12), 0.5);
        g.roughness = 0.75;
    } else if (kind == 4) {
        // Rock: slabs of different greys cut by dark cracks.
        float2 cell = floor(p * 0.6 + lw_noise(p * 0.4) * 1.2);
        float crack = abs(fract(p.x * 0.6 + lw_noise(p * 0.4) * 1.2) - 0.5) * abs(fract(p.y * 0.6 + lw_noise(p * 0.4 + 9.0) * 1.2) - 0.5);
        g.color = base * mix(0.82, 1.12, lw_hash(cell)) * mix(0.55, 1.0, smoothstep(0.0, 0.012, crack));
        g.color *= 0.92 + lw_noise(p * 3.0) * 0.16;
        g.normal = lw_tilted(lw_noiseSlope(p * 1.5), 0.25);
    } else if (kind == 5) {
        // Sand: a fine grain and low ripples.
        float grain = lw_hash(floor(p * 60.0)) * 0.5 + lw_noise(p * 8.0) * 0.5;
        float ripple = sin(p.x * 4.0 + lw_noise(p * 0.8) * 4.0);
        g.color = base * (0.94 + grain * 0.1) * (1.0 + ripple * 0.015);
        g.normal = lw_tilted(float2(cos(p.x * 4.0) * 0.03, 0.0), 1.0);
    } else if (kind == 6) {
        // Pavement: one-metre slabs, each its own tone, with darker joints.
        float2 slab = floor(p);
        float2 inSlab = abs(fract(p) - 0.5);
        float joint = smoothstep(0.47, 0.495, max(inSlab.x, inSlab.y));
        g.color = base * mix(0.9, 1.08, lw_hash(slab)) * (0.96 + lw_noise(p * 5.0) * 0.08);
        g.color = mix(g.color, base * 0.55, joint);
    } else if (kind == 7) {
        // Water's edge: sand, a dark wet band, then water that moves and shines.
        float shore = p.x - 2.0 + lw_noise(float2(p.y * 0.25, 3.0)) * 3.0;
        float3 sand = base * (0.95 + lw_hash(floor(p * 50.0)) * 0.08);
        float3 wet = sand * 0.68;
        float swell = sin(p.x * 1.2 + time * 1.4 + lw_noise(p * 0.3) * 4.0) * 0.5 + sin(p.y * 1.7 - time * 1.1) * 0.5;
        float3 water = mix(float3(0.07, 0.24, 0.32), float3(0.12, 0.36, 0.42), smoothstep(-4.0, 0.0, -shore));
        g.color = shore < -0.6 ? sand : (shore < 0.0 ? wet : water);
        if (shore >= 0.0) {
            g.normal = lw_tilted(float2(cos(p.x * 1.2 + time * 1.4) * 0.6, cos(p.y * 1.7 - time * 1.1) * 0.85) * 0.05, 1.0);
            g.roughness = 0.08;
            g.color *= 1.0 + swell * 0.04;
            // Foam where the water meets the sand.
            g.color = mix(g.color, float3(0.9, 0.93, 0.92), (1.0 - smoothstep(0.0, 0.25, shore)) * 0.7);
        }
    } else if (kind == 8) {
        // Room floor: boards along x, ends staggered, grain running with them.
        float row = floor(p.y / 0.18);
        float along = p.x + lw_hash(float2(row, 1.0)) * 2.4;
        float board = floor(along / 2.4);
        float seam = smoothstep(0.42, 0.48, abs(fract(p.y / 0.18) - 0.5)) + smoothstep(0.494, 0.5, abs(fract(along / 2.4) - 0.5));
        float grain = lw_noise(float2(along * 3.0, p.y * 60.0)) * 0.6 + lw_noise(float2(along * 0.6, p.y * 14.0)) * 0.4;
        g.color = base * mix(0.85, 1.1, lw_hash(float2(row, board))) * mix(0.9, 1.06, grain);
        g.color = mix(g.color, base * 0.5, saturate(seam));
        g.roughness = 0.45;
    }
    return g;
}
