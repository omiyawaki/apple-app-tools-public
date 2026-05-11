import LocalAppUpdateKit
import AppKit
import SwiftUI

struct LocalAppUpdateToolbarButtonMetrics {
    static let iconPointSize: CGFloat = 18
    static let controlSideLength: CGFloat = 44
    static let usesNativeAppKitGlassBezel = true
    static let hidesSharedToolbarBackground = true
}

public struct LocalAppUpdateToolbarItem: ToolbarContent {
    @ObservedObject private var controller: LocalAppUpdateController
    private let placement: ToolbarItemPlacement

    public init(
        placement: ToolbarItemPlacement = .primaryAction,
        controller: LocalAppUpdateController
    ) {
        self.placement = placement
        self.controller = controller
    }

    public var body: some ToolbarContent {
        ToolbarItem(placement: placement) {
            LocalAppUpdateToolbarButton(controller: controller)
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

public struct LocalAppUpdateToolbarButton: View {
    @ObservedObject private var controller: LocalAppUpdateController

    public init(controller: LocalAppUpdateController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            if controller.isUpdateVisible {
                Group {
                    if isDisabled {
                        ProgressView()
                            .controlSize(.small)
                            .tint(statusColor)
                    } else {
                        LocalAppUpdateNativeGlassButton(
                            systemImage: systemImage,
                            statusNSColor: statusNSColor,
                            helpText: helpText,
                            accessibilityLabel: accessibilityLabel
                        ) {
                            controller.installUpdateAndRelaunch()
                        }
                        .frame(
                            width: LocalAppUpdateToolbarButtonMetrics.controlSideLength,
                            height: LocalAppUpdateToolbarButtonMetrics.controlSideLength
                        )
                    }
                }
                .help(helpText)
                .accessibilityLabel(accessibilityLabel)
            }
        }
        .task {
            await controller.monitorForUpdates()
        }
    }

    private var isDisabled: Bool {
        if case .updating = controller.status { return true }
        if case .checking = controller.status { return true }
        return false
    }

    private var statusColor: Color {
        if case .failed = controller.status {
            return .red
        }
        return .orange
    }

    private var statusNSColor: NSColor {
        if case .failed = controller.status {
            return .systemRed
        }
        return .systemOrange
    }

    private var systemImage: String {
        if case .failed = controller.status {
            return "exclamationmark.arrow.triangle.2.circlepath"
        }
        return "arrow.down"
    }

    private var helpText: String {
        if case .failed(let message) = controller.status {
            return "Update failed: \(message)"
        }
        return "Install local update and reopen"
    }

    private var accessibilityLabel: String {
        if case .failed = controller.status {
            return "Update failed"
        }
        return "Update"
    }
}

private struct LocalAppUpdateNativeGlassButton: NSViewRepresentable {
    let systemImage: String
    let statusNSColor: NSColor
    let helpText: String
    let accessibilityLabel: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            image: image,
            target: context.coordinator,
            action: #selector(Coordinator.performAction)
        )
        button.bezelStyle = .glass
        button.controlSize = .extraLarge
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = true
        configure(button, context: context)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.image = image
        configure(button, context: context)
    }

    private var image: NSImage {
        NSImage(systemSymbolName: systemImage, accessibilityDescription: accessibilityLabel) ?? NSImage()
    }

    private func configure(_ button: NSButton, context: Context) {
        let sizeConfiguration = NSImage.SymbolConfiguration(
            pointSize: LocalAppUpdateToolbarButtonMetrics.iconPointSize,
            weight: .semibold
        )
        let colorConfiguration = NSImage.SymbolConfiguration(hierarchicalColor: statusNSColor)
        button.symbolConfiguration = sizeConfiguration.applying(colorConfiguration)
        button.contentTintColor = statusNSColor
        button.toolTip = helpText
        button.setAccessibilityLabel(accessibilityLabel)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}
