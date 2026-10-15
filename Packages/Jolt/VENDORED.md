# Vendored: Jolt Physics

- Upstream: https://github.com/jrouwe/JoltPhysics, tag `v5.6.0`.
- Licence: MIT (`LICENSE-jolt.txt`), credited in the app's LICENSES.md.
- Copied unchanged: `Jolt/` → `Sources/JoltCpp/jolt-src/Jolt/`, minus the GPU compute back ends (`Compute/DX12`,
  `Compute/VK`, `Compute/MTL`, `Compute/CPU`), the compute shaders and their wrappers (`Shaders/*.hlsl`,
  `Shaders/*.cpp`), `Jolt.cmake` and `Jolt.natvis`. Hair keeps compiling (it only needs the compute headers) and isn't
  used.
- Built single-threaded (`JobSystemSingleThreaded`) with `JPH_CROSS_PLATFORM_DETERMINISTIC` and `-ffp-contract=off`,
  so the same scene simulates to the same numbers on the iPad, the simulator and Linux. No object streams, no debug
  renderer, no profiler.
- Ours: `Sources/JoltCpp/JoltBridge.cpp` and `include/JoltBridge.h`, a C face Swift imports without C++ interop: rigid
  bodies (box, sphere, capsule, cylinder, convex hull, triangle mesh, glued hulls), joints (fixed, ball, hinge, slider,
  spring, swing-twist, gear; motors on hinges and sliders) and soft bodies (cloth, jelly by pressure).

To update: copy `Jolt/` from a newer tag, delete the same folders and files, run the package's tests (release and
debug) and LoweyCore's physics tests, change the tag above.
