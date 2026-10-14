# Vendored: Instant Meshes

- Upstream: https://github.com/wjakob/instant-meshes, `master` at commit `7b31608` (2019-11-03; no tags).
- Licence: BSD-3-Clause (`LICENSE-instant-meshes.txt`), credited in the app's LICENSES.md.
- Copied: `src/{adjacency,bvh,cleanup,dedge,extract,field,hierarchy,meshstats,normal,reorder,smoothcurve,subdivide}.{cpp,h}`,
  `common.h`, `aabb.h` → `Sources/InstantMeshesCpp/instant-meshes-src/`. The viewer, its GUI, file reading and writing and
  the command line are left out.
- One change upstream: `common.h` sends its progress text nowhere (`static std::ostream cout(nullptr)`, the same for
  `cerr`) instead of to the console.
- Its own dependencies:
  - Eigen 3.4.0 (MPL-2.0, `LICENSE-eigen-MPL2.txt`), only the 164 headers the files above include, unchanged, under
    `eigen/`. Built with `EIGEN_MPL2_ONLY` and `EIGEN_DONT_VECTORIZE` (scalar: the same input gives the same quads on
    every processor, and on a 500 000 triangle ball it was no slower).
  - `pcg32.h` (Apache-2.0, its licence is in the file; wjakob/pcg32 `70099ea`) and `dset.h` (zlib-style,
    `LICENSE-dset.txt`; wjakob/dset `7967ef0`) in `shim/`, unchanged.
- Ours, in `shim/`: `tbb/tbb.h` and `tbb/concurrent_vector.h` (the part of Threading Building Blocks it uses: loops
  fanned out over up to eight threads, everything else on the calling thread), `parallel_stable_sort.h` (`std::stable_sort`)
  and `serializer.h` (its save and load of interactive state, which we never use). `InstantMeshesBridge.cpp` and
  `include/InstantMeshesBridge.h` are the C face Swift imports without C++ interop: upstream's `batch.cpp` pipeline on
  arrays.

To update: copy the files above from a newer commit, keep the `common.h` change, recompute the Eigen headers with
`clang++ -MM` over the sources (with the two defines), run this package's tests and LoweyCore's `QuadRemeshTests`,
change the commits above.
