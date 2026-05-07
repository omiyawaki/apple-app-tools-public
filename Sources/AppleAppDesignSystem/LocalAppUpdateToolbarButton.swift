import LocalAppUpdateKit
import SwiftUI

public struct LocalAppUpdateToolbarButton: View {
    @ObservedObject private var controller: LocalAppUpdateController

    public init(controller: LocalAppUpdateController) {
        self.controller = controller
    }

    public var body: some View {
        if controller.isUpdateVisible {
            Button {
                controller.installUpdateAndRelaunch()
            } label: {
                switch controller.status {
                case .updating, .checking:
                    ProgressView()
                        .controlSize(.small)
                case .failed:
                    Label("Update", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                default:
                    Label("Update", systemImage: "arrow.down.circle.fill")
                }
            }
            .help(helpText)
            .disabled(isDisabled)
            .tint(.accentColor)
        }
    }

    private var isDisabled: Bool {
        if case .updating = controller.status { return true }
        if case .checking = controller.status { return true }
        return false
    }

    private var helpText: String {
        if case .failed(let message) = controller.status {
            return "Update failed: \(message)"
        }
        return "Install local update and reopen"
    }
}
