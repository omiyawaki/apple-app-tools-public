import XCTest
@testable import AppleAppDesignSystem

final class DesignSystemTests: XCTestCase {
    func testLocalUpdateToolbarButtonUsesToolbarProvidedLiquidGlassPattern() {
        XCTAssertEqual(LocalAppUpdateToolbarButtonMetrics.iconPointSize, 13)
        XCTAssertFalse(LocalAppUpdateToolbarButtonMetrics.usesCircularBorderShape)
        XCTAssertFalse(LocalAppUpdateToolbarButtonMetrics.usesExplicitGlassButtonStyle)
    }

    func testLocalUpdateToolbarButtonDoesNotHandRollToolbarChrome() throws {
        let source = try String(contentsOf: localUpdateToolbarButtonSourceURL(), encoding: .utf8)

        XCTAssertFalse(source.contains(".buttonStyle(.glass)"))
        XCTAssertFalse(source.contains(".buttonStyle(.plain)"))
        XCTAssertFalse(source.contains(".buttonStyle("))
        XCTAssertFalse(source.contains("contentSideLength"))
        XCTAssertFalse(source.contains("cornerRadius"))
    }

    private func localUpdateToolbarButtonSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/AppleAppDesignSystem/LocalAppUpdateToolbarButton.swift")
    }
}
