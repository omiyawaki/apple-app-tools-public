import Foundation

public struct ComponentRegistry: Equatable {
    public var components: [String: ComponentDefinition]

    public init(components: [ComponentDefinition]) {
        self.components = Dictionary(uniqueKeysWithValues: components.map { ($0.id, $0) })
    }

    public func component(id: String) -> ComponentDefinition? {
        components[id]
    }

    public static func defaultRegistry() -> ComponentRegistry {
        ComponentRegistry(
            components: [
                ComponentDefinition(
                    id: "icon-composer-build",
                    purpose: "Build Apple app icon assets from Icon Composer documents and produce review sheets.",
                    owner: "IconComposerBuild",
                    importName: nil,
                    docsPath: "docs/icon-composer-build.md",
                    integrationPoints: ["scripts/generate-icons.sh", "scripts/build_laps_icon.sh"],
                    duplicatePatterns: ["ictool", "Icon Composer", "Assets.car", "CFBundleIconName"]
                ),
                ComponentDefinition(
                    id: "mac-app-packager",
                    purpose: "Package SwiftPM GUI executables into local .app bundles with metadata, signing, and LaunchServices registration.",
                    owner: "MacAppPackager",
                    importName: nil,
                    docsPath: "docs/mac-app-packager.md",
                    integrationPoints: ["build-app.sh", "scripts/deploy_laps_app.sh"],
                    duplicatePatterns: ["Contents/MacOS", "codesign", "lsregister", "LocalAppBuild.json"]
                ),
                ComponentDefinition(
                    id: "local-update-ui",
                    purpose: "Detect local source drift and expose the standard update toolbar button that redeploys and reopens the app.",
                    owner: "LocalAppUpdateKit",
                    importName: "LocalAppUpdateKit",
                    docsPath: "docs/local-macos-app-updates.md",
                    integrationPoints: ["root SwiftUI view toolbar", "installed bundle metadata"],
                    duplicatePatterns: ["AppUpdater", "UpdateButton", "redeployAndRelaunch", "LocalAppBuild.json", "arrow.down.circle"]
                ),
                ComponentDefinition(
                    id: "macos-design-system",
                    purpose: "Shared SwiftUI visual language for local macOS tools.",
                    owner: "AppleAppDesignSystem",
                    importName: "AppleAppDesignSystem",
                    docsPath: "docs/macos-design-system.md",
                    integrationPoints: ["SwiftUI root views", "toolbar controls"],
                    duplicatePatterns: ["LocalAppUpdateToolbarItem", "LocalAppUpdateToolbarButton", "AppleAppDesignSystem", "shared app toolbar"]
                )
            ]
        )
    }
}

public struct BlueprintValidator {
    public var registry: ComponentRegistry

    public init(registry: ComponentRegistry) {
        self.registry = registry
    }

    public func validate(_ blueprint: AppBlueprint) throws {
        guard blueprint.schemaVersion == 1 else {
            throw BlueprintError.validation("Unsupported schemaVersion \(blueprint.schemaVersion).")
        }
        guard blueprint.app.platform == "macOS" else {
            throw BlueprintError.validation("Only macOS app blueprints are supported in this tool version.")
        }
        for component in blueprint.components {
            guard registry.component(id: component.id) != nil else {
                throw BlueprintError.validation("Unknown universal component: \(component.id).")
            }
        }
        guard !blueprint.app.id.isEmpty else {
            throw BlueprintError.validation("app.id must not be empty.")
        }
        guard !blueprint.build.projectRoot.isEmpty else {
            throw BlueprintError.validation("build.projectRoot must not be empty.")
        }
    }
}
