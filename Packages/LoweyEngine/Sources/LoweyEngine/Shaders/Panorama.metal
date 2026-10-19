// Panorama.metal — 360° frames (F1): six square views around the camera laid flat as one equirectangular picture.
// The face maths is Core's `Panorama.faceCoordinate` (tested there): each face is a camera looking along its axis with
// its up, so a face's right is forward × up and its rows run down.

#include "LoweyCommon.h"

constexpr sampler lw_faceSampler(coord::normalized, address::clamp_to_edge, filter::linear);

kernel void lw_equirect(texture2d_array<float, access::sample> faces [[texture(0)]],
                        texture2d<float, access::write> output [[texture(1)]],
                        uint2 gid [[thread_position_in_grid]]) {
    uint width = output.get_width();
    uint height = output.get_height();
    if (gid.x >= width || gid.y >= height) { return; }
    float2 uv = (float2(gid) + 0.5) / float2(width, height);
    float azimuth = (uv.x - 0.5) * 2.0 * M_PI_F;
    float polar = uv.y * M_PI_F;
    float3 d = float3(sin(polar) * sin(azimuth), cos(polar), -sin(polar) * cos(azimuth));
    float3 a = abs(d);
    uint face;
    float3 forward;
    float3 up;
    if (a.x >= a.y && a.x >= a.z) {
        face = d.x > 0.0 ? 0u : 1u;
        forward = float3(sign(d.x), 0.0, 0.0);
        up = float3(0.0, 1.0, 0.0);
    } else if (a.y >= a.z) {
        face = d.y > 0.0 ? 2u : 3u;
        forward = float3(0.0, sign(d.y), 0.0);
        up = float3(0.0, 0.0, sign(d.y));
    } else {
        face = d.z > 0.0 ? 4u : 5u;
        forward = float3(0.0, 0.0, sign(d.z));
        up = float3(0.0, 1.0, 0.0);
    }
    float3 right = cross(forward, up);
    float depth = dot(d, forward);
    float2 st = float2((dot(d, right) / depth + 1.0) * 0.5, (1.0 - dot(d, up) / depth) * 0.5);
    output.write(faces.sample(lw_faceSampler, st, face), gid);
}
