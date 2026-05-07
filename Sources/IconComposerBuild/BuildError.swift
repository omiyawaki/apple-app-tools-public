import Foundation

public struct BuildError: Error, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}
