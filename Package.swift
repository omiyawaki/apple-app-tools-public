// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "apple-app-tools",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "AppleAppBlueprint", targets: ["AppleAppBlueprint"]),
        .library(name: "AppleAppDesignSystem", targets: ["AppleAppDesignSystem"]),
        .library(name: "LocalAppUpdateKit", targets: ["LocalAppUpdateKit"]),
        .library(name: "MacAppPackager", targets: ["MacAppPackager"]),
        .library(name: "IconComposerBuild", targets: ["IconComposerBuild"]),
        .executable(name: "apple-app-tools", targets: ["AppleAppToolsCLI"]),
        .executable(name: "icon-composer-build", targets: ["IconComposerBuildCLI"])
    ],
    targets: [
        .target(name: "AppleAppBlueprint"),
        .target(name: "LocalAppUpdateKit"),
        .target(
            name: "AppleAppDesignSystem",
            dependencies: ["LocalAppUpdateKit"]
        ),
        .target(
            name: "MacAppPackager",
            dependencies: ["AppleAppBlueprint"]
        ),
        .target(name: "IconComposerBuild"),
        .executableTarget(
            name: "AppleAppToolsCLI",
            dependencies: [
                "AppleAppBlueprint",
                "MacAppPackager",
                "IconComposerBuild"
            ]
        ),
        .executableTarget(
            name: "IconComposerBuildCLI",
            dependencies: ["IconComposerBuild"]
        ),
        .testTarget(
            name: "AppleAppToolsTests",
            dependencies: [
                "AppleAppBlueprint",
                "AppleAppDesignSystem",
                "LocalAppUpdateKit",
                "MacAppPackager"
            ]
        )
    ]
)
