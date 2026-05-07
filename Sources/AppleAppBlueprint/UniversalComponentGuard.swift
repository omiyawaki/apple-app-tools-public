import Foundation

public enum GuardSeverity: String, Codable, Equatable {
    case allow
    case warn
    case block
}

public struct GuardResult: Codable, Equatable {
    public var severity: GuardSeverity
    public var componentID: String?
    public var message: String
}

public struct UniversalComponentGuard {
    public var registry: ComponentRegistry

    public init(registry: ComponentRegistry) {
        self.registry = registry
    }

    public func evaluate(blueprint: AppBlueprint, path: String, proposedContent: String) -> GuardResult {
        let activeComponents = Set(blueprint.components.map(\.id))
        for componentID in activeComponents {
            guard let component = registry.component(id: componentID) else { continue }
            let matches = component.duplicatePatterns.filter { pattern in
                proposedContent.localizedCaseInsensitiveContains(pattern)
                    || path.localizedCaseInsensitiveContains(pattern)
            }
            if matches.count >= 2 || highConfidenceSingleMatch(componentID: componentID, matches: matches) {
                return GuardResult(
                    severity: .block,
                    componentID: componentID,
                    message: "This app declares `\(componentID)` in AppleAppBlueprint.yaml. Update the universal component in apple-app-tools or the blueprint before rebuilding it locally."
                )
            }
            if matches.count == 1 {
                return GuardResult(
                    severity: .warn,
                    componentID: componentID,
                    message: "This edit resembles universal component `\(componentID)`. Check apple-app-tools before adding app-local code."
                )
            }
        }
        return GuardResult(severity: .allow, componentID: nil, message: "No universal component duplication detected.")
    }

    private func highConfidenceSingleMatch(componentID: String, matches: [String]) -> Bool {
        guard componentID == "local-update-ui" else { return false }
        return matches.contains { $0 == "AppUpdater" || $0 == "redeployAndRelaunch" }
    }
}
