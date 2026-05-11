import LocalAppUpdateKit
import SwiftUI

struct LocalAppUpdateToolbarButtonMetrics {
    static let iconPointSize: CGFloat = 13
    static let usesCircularBorderShape = false
    static let usesExplicitGlassButtonStyle = false
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
                Button {
                    controller.installUpdateAndRelaunch()
                } label: {
                    buttonContent
                }
                .controlSize(.small)
                .help(helpText)
                .accessibilityLabel(accessibilityLabel)
                .disabled(isDisabled)
            }
        }
        .task {
            await controller.monitorForUpdates()
        }
    }

    private var buttonContent: some View {
        Group {
            switch controller.status {
            case .updating, .checking:
                ProgressView()
                    .controlSize(.small)
                    .tint(statusColor)
            default:
                Label(accessibilityLabel, systemImage: systemImage)
                    .labelStyle(.iconOnly)
                    .font(.system(size: LocalAppUpdateToolbarButtonMetrics.iconPointSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(statusColor)
            }
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
