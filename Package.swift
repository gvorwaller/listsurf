// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Listsurf",
    // Deployment targets set to v18/v15 for SPM compatibility with command-line tools.
    // Actual deployment targets (iOS 26 / macOS 26) will be set in the Xcode project.
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Features", targets: ["Features"]),
    ],
    targets: [
        // Domain: pure Swift value models, tree engine, validation.
        // Imports Foundation only — no SwiftUI, no Core Data.
        .target(
            name: "Domain",
            path: "Sources/Domain"
        ),

        // Persistence: Core Data stack, repositories, migrations.
        // Imports Domain to implement repository protocols.
        .target(
            name: "Persistence",
            dependencies: ["Domain"],
            path: "Sources/Persistence"
        ),

        // Features: SwiftUI views and view models for all screens.
        // Imports Domain directly; uses Persistence via Domain protocols.
        .target(
            name: "Features",
            dependencies: ["Domain", "Persistence", "Platform"],
            path: "Sources/Features"
        ),

        // Platform: narrow UIKit/AppKit integrations.
        .target(
            name: "Platform",
            path: "Sources/Platform"
        ),

        // Tests
        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain"],
            path: "Tests/DomainTests"
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Domain", "Persistence"],
            path: "Tests/PersistenceTests"
        ),
        .testTarget(
            name: "FeaturesTests",
            dependencies: ["Domain", "Features"],
            path: "Tests/FeaturesTests"
        ),
    ]
)
