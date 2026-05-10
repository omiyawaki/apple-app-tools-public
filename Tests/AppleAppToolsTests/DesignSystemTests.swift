import XCTest
@testable import AppleAppDesignSystem

final class DesignSystemTests: XCTestCase {
    func testLocalUpdateToolbarButtonUsesNativeLiquidGlassToolbarPattern() {
        XCTAssertEqual(LocalAppUpdateToolbarButtonMetrics.iconPointSize, 13)
        XCTAssertFalse(LocalAppUpdateToolbarButtonMetrics.usesCircularBorderShape)
        XCTAssertTrue(LocalAppUpdateToolbarButtonMetrics.usesExplicitGlassButtonStyle)
    }

    func testLocalUpdateToolbarButtonDoesNotHandRollToolbarChrome() throws {
        let source = try String(contentsOf: localUpdateToolbarButtonSourceURL(), encoding: .utf8)

        XCTAssertTrue(source.contains(".buttonStyle(.glass)"))
        XCTAssertFalse(source.contains(".buttonStyle(.plain)"))
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
