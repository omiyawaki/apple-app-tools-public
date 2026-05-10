import XCTest
@testable import AppleAppDesignSystem

final class DesignSystemTests: XCTestCase {
    func testLocalUpdateToolbarButtonUsesCompactToolbarMetrics() {
        XCTAssertEqual(LocalAppUpdateToolbarButtonMetrics.iconPointSize, 13)
        XCTAssertEqual(LocalAppUpdateToolbarButtonMetrics.contentSideLength, 20)
        XCTAssertEqual(LocalAppUpdateToolbarButtonMetrics.cornerRadius, 8)
        XCTAssertFalse(LocalAppUpdateToolbarButtonMetrics.usesCircularBorderShape)
        XCTAssertFalse(LocalAppUpdateToolbarButtonMetrics.usesExplicitGlassButtonStyle)
    }
}
