import LocalAppUpdateKit
import SwiftUI

struct LocalAppUpdateToolbarButtonMetrics {
    static let iconPointSize: CGFloat = 15
    static let usesSwiftUIGlassButtonStyle = true
    static let usesCircularButtonBorderShape = true
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
        Group {
            if controller.isUpdateVisible {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(statusColor)
                } else {
                    Button {
                        controller.installUpdateAndRelaunch()
                    } label: {
                        Image(systemName: systemImage)
                            .font(.system(size: LocalAppUpdateToolbarButtonMetrics.iconPointSize, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(statusColor)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.regular)
                    .help(helpText)
                    .accessibilityLabel(accessibilityLabel)
                }
            }
        }
        .task {
            await controller.monitorForUpdates()
        }
    }

    private var isBusy: Bool {
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
