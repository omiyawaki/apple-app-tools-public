import XCTest
@testable import AppleAppDesignSystem

final class DesignSystemTests: XCTestCase {
    func testLocalUpdateToolbarButtonUsesNativeGlassBezelPattern() {
        XCTAssertEqual(LocalAppUpdateToolbarButtonMetrics.iconPointSize, 18)
        XCTAssertEqual(LocalAppUpdateToolbarButtonMetrics.controlSideLength, 44)
        XCTAssertTrue(LocalAppUpdateToolbarButtonMetrics.usesNativeAppKitGlassBezel)
        XCTAssertTrue(LocalAppUpdateToolbarButtonMetrics.hidesSharedToolbarBackground)
    }

    func testLocalUpdateToolbarButtonUsesDocumentedSystemGlassChrome() throws {
        let source = try String(contentsOf: localUpdateToolbarButtonSourceURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("public struct LocalAppUpdateToolbarItem: ToolbarContent"))
        XCTAssertTrue(source.contains("NSViewRepresentable"))
        XCTAssertTrue(source.contains("button.bezelStyle = .glass"))
        XCTAssertTrue(source.contains("button.symbolConfiguration"))
        XCTAssertTrue(source.contains("hierarchicalColor: statusNSColor"))
        XCTAssertTrue(source.contains(".sharedBackgroundVisibility(.hidden)"))
        XCTAssertFalse(source.contains(".buttonStyle(.glass)"))
        XCTAssertFalse(source.contains(".buttonBorderShape(.circle)"))
        XCTAssertFalse(source.contains(".buttonStyle(.plain)"))
        XCTAssertFalse(source.contains(".overlay"))
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
