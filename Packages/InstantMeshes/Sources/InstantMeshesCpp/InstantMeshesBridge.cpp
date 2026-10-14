// Instant Meshes' batch pipeline (batch.cpp) on arrays instead of files.
#include "InstantMeshesBridge.h"

#include "bvh.h"
#include "dedge.h"
#include "extract.h"
#include "field.h"
#include "hierarchy.h"
#include "meshstats.h"
#include "normal.h"
#include "subdivide.h"

#include <cstdlib>
#include <cstring>
#include <map>
#include <set>

// The thread count upstream reads from its command line (main.cpp); -1 lets the loops choose.
int nprocs = -1;

extern "C" int IMRemesh(const float *positions, uint32_t vertexCount, const uint32_t *triangles, uint32_t triangleCount,
                        IMOptions options, IMSurface *out) {
    if (!out || vertexCount < 3 || triangleCount < 1 || options.targetFaces < 4) return 1;
    try {
        const int rosy = 4, posy = 4;
        const bool deterministic = true, extrinsic = true;
        MatrixXu F(3, triangleCount);
        MatrixXf V(3, vertexCount), N;
        VectorXf A;
        for (uint32_t i = 0; i < triangleCount * 3; ++i) {
            if (triangles[i] >= vertexCount) return 2;
            F(i % 3, i / 3) = triangles[i];
        }
        for (uint32_t i = 0; i < vertexCount * 3; ++i) V(i % 3, i / 3) = positions[i];

        MeshStats stats = compute_mesh_stats(F, V, deterministic);
        uint32_t faceCount = options.targetFaces;
        Float scale = std::sqrt(stats.mSurfaceArea / faceCount);

        VectorXu V2E, E2E;
        VectorXb boundary, nonManifold;
        if (stats.mMaximumEdgeLength * 2 > scale || stats.mMaximumEdgeLength > stats.mAverageEdgeLength * 2) {
            build_dedge(F, V, V2E, E2E, boundary, nonManifold);
            subdivide(F, V, V2E, E2E, boundary, nonManifold, std::min(scale / 2, (Float)stats.mAverageEdgeLength * 2), deterministic);
        }
        build_dedge(F, V, V2E, E2E, boundary, nonManifold);
        AdjacencyMatrix adj = generate_adjacency_matrix_uniform(F, V2E, E2E, nonManifold);
        std::set<uint32_t> creaseIn, creaseOut;
        if (options.creaseDegrees > 0)
            generate_crease_normals(F, V, V2E, E2E, boundary, nonManifold, options.creaseDegrees, N, creaseIn);
        else
            generate_smooth_normals(F, V, V2E, E2E, nonManifold, N);
        compute_dual_vertex_areas(F, V, V2E, E2E, nonManifold, A);

        MultiResolutionHierarchy mRes;
        mRes.setE2E(std::move(E2E));
        mRes.setAdj(std::move(adj));
        mRes.setF(std::move(F));
        mRes.setV(std::move(V));
        mRes.setA(std::move(A));
        mRes.setN(std::move(N));
        mRes.setScale(scale);
        mRes.build(deterministic);
        mRes.resetSolution();

        if (options.alignToBoundaries) {
            mRes.clearConstraints();
            for (uint32_t i = 0; i < 3 * mRes.F().cols(); ++i) {
                if (mRes.E2E()[i] != INVALID) continue;
                uint32_t i0 = mRes.F()(i % 3, i / 3), i1 = mRes.F()((i + 1) % 3, i / 3);
                Vector3f p0 = mRes.V().col(i0), p1 = mRes.V().col(i1), edge = p1 - p0;
                if (edge.squaredNorm() <= 0) continue;
                edge.normalize();
                mRes.CO().col(i0) = p0;
                mRes.CO().col(i1) = p1;
                mRes.CQ().col(i0) = mRes.CQ().col(i1) = edge;
                mRes.CQw()[i0] = mRes.CQw()[i1] = mRes.COw()[i0] = mRes.COw()[i1] = 1.0f;
            }
            mRes.propagateConstraints(rosy, posy);
        }

        BVH *bvh = nullptr;
        if (options.smoothIterations > 0) {
            bvh = new BVH(&mRes.F(), &mRes.V(), &mRes.N(), stats.mAABB);
            bvh->build();
        }

        Optimizer optimizer(mRes, false);
        optimizer.setRoSy(rosy);
        optimizer.setPoSy(posy);
        optimizer.setExtrinsic(extrinsic);
        optimizer.optimizeOrientations(-1);
        optimizer.notify();
        optimizer.wait();
        optimizer.optimizePositions(-1);
        optimizer.notify();
        optimizer.wait();
        optimizer.shutdown();

        MatrixXf O, Nx, Nf;
        std::vector<std::vector<TaggedLink>> graph;
        extract_graph(mRes, extrinsic, rosy, posy, graph, O, Nx, creaseIn, creaseOut, deterministic);
        MatrixXu Fx;
        extract_faces(graph, O, Nx, Nf, Fx, posy, mRes.scale(), creaseOut, true, options.pureQuads != 0, bvh, options.smoothIterations);
        delete bvh;

        out->vertexCount = (uint32_t)O.cols();
        out->faceCount = (uint32_t)Fx.cols();
        out->positions = (float *)std::malloc(sizeof(float) * 3 * O.cols());
        out->indices = (uint32_t *)std::malloc(sizeof(uint32_t) * 4 * Fx.cols());
        if (!out->positions || !out->indices) {
            IMFree(out);
            return 3;
        }
        for (uint32_t i = 0; i < out->vertexCount; ++i)
            for (int k = 0; k < 3; ++k) out->positions[i * 3 + k] = O(k, i);
        for (uint32_t f = 0; f < out->faceCount; ++f)
            for (int k = 0; k < 4; ++k) out->indices[f * 4 + k] = Fx(Fx.rows() == 4 ? k : std::min(k, 2), f);
        return 0;
    } catch (...) {
        return 4;
    }
}

extern "C" void IMFree(IMSurface *surface) {
    if (!surface) return;
    std::free(surface->positions);
    std::free(surface->indices);
    surface->positions = nullptr;
    surface->indices = nullptr;
    surface->vertexCount = surface->faceCount = 0;
}
