// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MakerPortfolio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MakerDomain", targets: ["MakerDomain"]),
        .library(name: "MakerApplication", targets: ["MakerApplication"]),
        .library(name: "MakerSupport", targets: ["MakerSupport"]),
        .library(name: "MakerAdapters", targets: ["MakerAdapters"]),
        .library(name: "MakerInfrastructure", targets: ["MakerInfrastructure"]),
        .executable(name: "maker", targets: ["MakerCLI"])
    ],
    targets: [
        // Core domain layer: pure models and rules.
        .target(
            name: "MakerDomain",
            path: "Sources/MakerDomain"
        ),
        // Application layer: use cases and repository protocols.
        .target(
            name: "MakerApplication",
            dependencies: ["MakerDomain", "MakerSupport"],
            path: "Sources/MakerApplication"
        ),
        // Shared utilities and cross-cutting helpers.
        .target(
            name: "MakerSupport",
            path: "Sources/MakerSupport"
        ),
        // Runtime execution adapters for local process control and future platform hooks.
        .target(
            name: "MakerAdapters",
            dependencies: ["MakerDomain", "MakerSupport"],
            path: "Sources/MakerAdapters"
        ),
        // Infrastructure implementations for persistence, security, and filesystem access.
        .target(
            name: "MakerInfrastructure",
            dependencies: ["MakerDomain", "MakerApplication", "MakerSupport", "MakerAdapters"],
            path: "Sources/MakerInfrastructure"
        ),
        .executableTarget(
            name: "MakerCLI",
            dependencies: ["MakerDomain", "MakerApplication", "MakerInfrastructure", "MakerSupport", "MakerAdapters"],
            path: "Sources/MakerCLI"
        ),
        .testTarget(
            name: "MakerDomainTests",
            dependencies: ["MakerDomain"],
            path: "Tests/MakerDomainTests"
        ),
        .testTarget(
            name: "MakerApplicationTests",
            dependencies: ["MakerApplication", "MakerDomain", "MakerSupport"],
            path: "Tests/MakerApplicationTests"
        ),
        .testTarget(
            name: "MakerAdaptersTests",
            dependencies: ["MakerAdapters", "MakerDomain", "MakerSupport"],
            path: "Tests/MakerAdaptersTests"
        ),
        .testTarget(
            name: "MakerInfrastructureTests",
            dependencies: ["MakerInfrastructure", "MakerDomain", "MakerApplication", "MakerSupport", "MakerAdapters"],
            path: "Tests/MakerInfrastructureTests"
        ),
        .testTarget(
            name: "MakerCLITests",
            dependencies: ["MakerCLI", "MakerInfrastructure"],
            path: "Tests/MakerCLITests"
        )
    ]
)
