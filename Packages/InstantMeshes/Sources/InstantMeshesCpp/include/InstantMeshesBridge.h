// Instant Meshes behind a plain C face: a triangle surface in, a quad-dominant (or pure quad) surface out.
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct IMSurface {
    float *positions;       // x, y, z per vertex
    uint32_t vertexCount;
    uint32_t *indices;      // four per face; a triangle repeats its last corner
    uint32_t faceCount;
} IMSurface;

typedef struct IMOptions {
    uint32_t targetFaces;   // about how many faces the result has
    float creaseDegrees;    // sharp edges kept above this angle; 0 = none
    int pureQuads;          // 1 = only quads (each made of quarters), 0 = mostly quads
    int alignToBoundaries;  // 1 = open edges guide the flow
    int smoothIterations;   // passes that pull the result back onto the input
} IMOptions;

// 0 on success, then `out` owns memory freed with IMFree. Nonzero: the input couldn't be remeshed.
int IMRemesh(const float *positions, uint32_t vertexCount, const uint32_t *triangles, uint32_t triangleCount, IMOptions options,
             IMSurface *out);

void IMFree(IMSurface *surface);

#ifdef __cplusplus
}
#endif
