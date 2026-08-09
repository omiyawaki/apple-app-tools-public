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

    func testIndexedScrollRailMapsVerticalLocationsToMarkers() {
        XCTAssertNil(IndexedScrollRailLayout.markerIndex(
            at: 40,
            height: 100,
            markerCount: 0
        ))
        XCTAssertEqual(IndexedScrollRailLayout.markerIndex(
            at: -20,
            height: 100,
            markerCount: 5
        ), 0)
        XCTAssertEqual(IndexedScrollRailLayout.markerIndex(
            at: 50,
            height: 100,
            markerCount: 5
        ), 2)
        XCTAssertEqual(IndexedScrollRailLayout.markerIndex(
            at: 150,
            height: 100,
            markerCount: 5
        ), 4)
    }

    func testIndexedScrollRailSamplingIncludesBothEnds() {
        XCTAssertEqual(
            IndexedScrollRailLayout.sampledIndices(markerCount: 10, maximumCount: 4),
            [0, 3, 6, 9]
        )
    }

    func testIndexedScrollRailMajorLabelsAreSampledFromMajorMarkersOnly() {
        let markers = (0..<8).map { index in
            IndexedScrollRailMarker(
                id: String(index),
                label: "Month \(index)",
                majorLabel: index.isMultiple(of: 2) ? "Year \(index)" : nil
            )
        }
        XCTAssertEqual(
            IndexedScrollRailLayout.majorLabelIndices(markers: markers, maximumCount: 3),
            [0, 4, 6]
        )
    }

    private func localUpdateToolbarButtonSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/AppleAppDesignSystem/LocalAppUpdateToolbarButton.swift")
    }
}
