import XCTest
@testable import AppleAppDesignSystem

final class DesignSystemTests: XCTestCase {
    func testLocalUpdateToolbarButtonUsesStandaloneCircularGlassPattern() {
        XCTAssertEqual(LocalAppUpdateToolbarButtonMetrics.iconPointSize, 15)
        XCTAssertTrue(LocalAppUpdateToolbarButtonMetrics.usesCircularBorderShape)
        XCTAssertTrue(LocalAppUpdateToolbarButtonMetrics.usesExplicitGlassButtonStyle)
        XCTAssertTrue(LocalAppUpdateToolbarButtonMetrics.hidesSharedToolbarBackground)
    }

    func testLocalUpdateToolbarButtonDoesNotHandRollToolbarChrome() throws {
        let source = try String(contentsOf: localUpdateToolbarButtonSourceURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("public struct LocalAppUpdateToolbarItem: ToolbarContent"))
        XCTAssertTrue(source.contains(".sharedBackgroundVisibility(.hidden)"))
        XCTAssertTrue(source.contains(".buttonStyle(.glass)"))
        XCTAssertTrue(source.contains(".buttonBorderShape(.circle)"))
        XCTAssertTrue(source.contains(".controlSize(.regular)"))
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
