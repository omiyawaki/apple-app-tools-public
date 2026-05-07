import Foundation

public struct AppMapRenderer {
    public var registry: ComponentRegistry

    public init(registry: ComponentRegistry) {
        self.registry = registry
    }

    public func render(_ blueprint: AppBlueprint) throws -> String {
        try BlueprintValidator(registry: registry).validate(blueprint)
        var lines: [String] = []
        lines.append("# \(blueprint.app.name) App Map")
        lines.append("")
        lines.append("Generated from `AppleAppBlueprint.yaml`. Edit the blueprint first, then regenerate this map.")
        lines.append("")
        lines.append("## App")
        lines.append("")
        lines.append("- id: `\(blueprint.app.id)`")
        lines.append("- platform: `\(blueprint.app.platform)`")
        lines.append("- bundle: `\(blueprint.app.bundlePath)`")
        lines.append("- deploy: `\(blueprint.build.deployCommand)`")
        lines.append("")
        lines.append("## Universal Components")
        lines.append("")
        for use in blueprint.components {
            guard let component = registry.component(id: use.id) else { continue }
            let importText = component.importName.map { " import `\($0)`." } ?? ""
            lines.append("- `\(component.id)`: \(component.purpose)\(importText)")
        }
        lines.append("")
        lines.append("## Package Dependencies")
        lines.append("")
        for dependency in blueprint.packageDependencies {
            lines.append("- `\(dependency.name)` at `\(dependency.path)`: \(dependency.products.map { "`\($0)`" }.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("## Local App Modules")
        lines.append("")
        for module in blueprint.localModules {
            lines.append("- \(module.name): \(module.paths.map { "`\($0)`" }.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("## Custom Code Boundaries")
        lines.append("")
        for path in blueprint.customCode.allow {
            lines.append("- App-specific code is allowed under `\(path)`.")
        }
        lines.append("")
        lines.append("If a change looks reusable across local Apple apps, add it to `~/tools/apple-app-tools` and update this blueprint instead of rebuilding it locally.")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
