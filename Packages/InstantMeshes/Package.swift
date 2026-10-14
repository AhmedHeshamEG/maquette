// swift-tools-version: 6.0
// Instant Meshes (BSD-3-Clause, https://github.com/wjakob/instant-meshes, commit 7b31608) vendored as C++ with a small
// C face, so a sculpt becomes clean quads the same on iPadOS and in the Linux test container. Eigen 3.4.0 (MPL-2.0)
// comes with it, cut to the headers it uses. See the LICENSE files and VENDORED.md.

import PackageDescription

let package = Package(
    name: "InstantMeshes",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "InstantMeshesCpp", targets: ["InstantMeshesCpp"])
    ],
    targets: [
        .target(
            name: "InstantMeshesCpp",
            path: "Sources/InstantMeshesCpp",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("instant-meshes-src"),
                .headerSearchPath("shim"),
                .headerSearchPath("eigen"),
                // Scalar Eigen: the same mesh remeshes to the same quads on every processor (and it was no slower).
                .define("EIGEN_DONT_VECTORIZE"),
                .define("EIGEN_MPL2_ONLY")
            ]
        ),
        .testTarget(
            name: "InstantMeshesTests",
            dependencies: ["InstantMeshesCpp"],
            path: "Tests/InstantMeshesTests"
        )
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
