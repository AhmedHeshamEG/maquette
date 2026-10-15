// swift-tools-version: 6.0
// Jolt Physics (MIT, https://github.com/jrouwe/JoltPhysics, v5.6.0) vendored as C++ with a small C face, so
// simulations run the same on iPadOS and in the Linux test container. See LICENSE-jolt.txt and VENDORED.md.

import PackageDescription

let package = Package(
    name: "Jolt",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "JoltCpp", targets: ["JoltCpp"])
    ],
    targets: [
        .target(
            name: "JoltCpp",
            path: "Sources/JoltCpp",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("jolt-src"),
                // The same steps give the same result on every processor: the iPad, the simulator, Linux.
                .define("JPH_CROSS_PLATFORM_DETERMINISTIC"),
                .unsafeFlags(["-ffp-contract=off"])
            ]
        ),
        .testTarget(
            name: "JoltTests",
            dependencies: ["JoltCpp"],
            path: "Tests/JoltTests"
        )
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
