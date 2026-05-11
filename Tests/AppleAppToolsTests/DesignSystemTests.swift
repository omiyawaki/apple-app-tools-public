import XCTest
@testable import AppleAppDesignSystem

final class DesignSystemTests: XCTestCase {
    func testLocalUpdateToolbarButtonUsesSwiftUIGlassBezelPattern() {
        XCTAssertEqual(LocalAppUpdateToolbarButtonMetrics.iconPointSize, 15)
        XCTAssertTrue(LocalAppUpdateToolbarButtonMetrics.usesSwiftUIGlassButtonStyle)
        XCTAssertTrue(LocalAppUpdateToolbarButtonMetrics.usesCircularButtonBorderShape)
        XCTAssertTrue(LocalAppUpdateToolbarButtonMetrics.hidesSharedToolbarBackground)
    }

    func testLocalUpdateToolbarButtonUsesDocumentedSystemGlassChrome() throws {
        let source = try String(contentsOf: localUpdateToolbarButtonSourceURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("public struct LocalAppUpdateToolbarItem: ToolbarContent"))
        XCTAssertTrue(source.contains(".buttonStyle(.glass)"))
        XCTAssertTrue(source.contains(".buttonBorderShape(.circle)"))
        XCTAssertTrue(source.contains(".controlSize(.regular)"))
        XCTAssertTrue(source.contains(".sharedBackgroundVisibility(.hidden)"))
        XCTAssertFalse(source.contains("NSViewRepresentable"))
        XCTAssertFalse(source.contains("bezelStyle = .glass"))
        XCTAssertFalse(source.contains(".buttonStyle(.plain)"))
        XCTAssertFalse(source.contains(".overlay"))
        XCTAssertFalse(source.contains("cornerRadius"))
        XCTAssertFalse(source.contains("controlSideLength"))
    }

    private func localUpdateToolbarButtonSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/AppleAppDesignSystem/LocalAppUpdateToolbarButton.swift")
    }
}
