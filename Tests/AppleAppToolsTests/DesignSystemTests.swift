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

    func testIndexedScrollRailUsesExplicitRegularTickCadence() {
        XCTAssertEqual(
            IndexedScrollRailLayout.tickStride(
                markerCount: 2_000,
                height: 800,
                minimumSpacing: 7,
                candidates: [1, 3, 6, 12, 24, 60]
            ),
            24
        )
        XCTAssertEqual(
            IndexedScrollRailLayout.tickIndices(
                markerCount: 30,
                stride: 12,
                alignment: 7
            ),
            [0, 7, 19, 29]
        )
        XCTAssertEqual(
            IndexedScrollRailLayout.tickStride(
                markerCount: 2_000,
                height: 2_000,
                minimumSpacing: 3,
                candidates: [1, 3, 6, 12, 24, 60],
                minimumStride: 12
            ),
            12
        )
        XCTAssertEqual(
            IndexedScrollRailLayout.tickStride(
                markerCount: 2_000,
                height: 800,
                minimumSpacing: 2,
                candidates: [1, 3, 6, 12, 24, 60],
                minimumStride: 3
            ),
            6
        )
    }

    func testIndexedScrollRailThinsCollisionsAndPreservesEndpoints() {
        XCTAssertEqual(
            IndexedScrollRailLayout.spacedIndices(
                [0, 1, 2, 3, 4, 5],
                normalizedPositions: [0, 0.02, 0.1, 0.5, 0.96, 1],
                height: 400,
                minimumSpacing: 20
            ),
            [0, 2, 3, 5]
        )
    }

    func testIndexedScrollRailThinsFinalRenderedCoordinates() {
        let renderedPositions: [CGFloat] = [0, 2, 7, 13, 15, 24]

        XCTAssertEqual(
            IndexedScrollRailLayout.spacedIndices(
                Array(renderedPositions.indices),
                verticalPositions: renderedPositions,
                minimumSpacing: 5
            ),
            [0, 2, 3, 5]
        )
    }

    func testIndexedScrollRailHoverGeometryIsWellBelowOneFrame() {
        let markerCount = 2_000
        let height: CGFloat = 1_200
        let normalizedPositions = (0..<markerCount).map {
            Double($0) / Double(markerCount - 1)
        }
        let started = ContinuousClock.now
        var checksum: CGFloat = 0

        for sample in 0..<200 {
            let hoverPosition = CGFloat(sample % 100) / 99 * height
            let positions = normalizedPositions.map {
                IndexedScrollRailLayout.verticalPosition(
                    forNormalizedPosition: $0,
                    height: height
                )
            }
            let stride = IndexedScrollRailLayout.tickStride(
                markerCount: markerCount,
                height: height,
                minimumSpacing: 2,
                candidates: [1, 3, 6, 12, 24, 60, 120, 240, 600],
                minimumStride: 3
            )
            let indices = IndexedScrollRailLayout.spacedIndices(
                IndexedScrollRailLayout.tickIndices(
                    markerCount: markerCount,
                    stride: stride,
                    alignment: 7
                ),
                verticalPositions: positions,
                minimumSpacing: 2
            )
            for index in indices {
                checksum += IndexedScrollRailLayout.influence(
                    at: positions[index],
                    around: hoverPosition
                )
            }
        }

        let elapsed = (ContinuousClock.now - started) / .milliseconds(1)
        XCTAssertGreaterThan(checksum, 0)
        XCTAssertLessThan(elapsed / 200, 1)
    }

    func testIndexedScrollRailKeepsContentOutOfRoundedEndCaps() {
        XCTAssertEqual(
            IndexedScrollRailLayout.verticalPosition(
                for: 0,
                height: 400,
                markerCount: 5
            ),
            IndexedScrollRailLayout.contentInset
        )
        XCTAssertEqual(
            IndexedScrollRailLayout.verticalPosition(
                for: 4,
                height: 400,
                markerCount: 5
            ),
            400 - IndexedScrollRailLayout.contentInset
        )
        XCTAssertEqual(
            IndexedScrollRailLayout.verticalPosition(
                forNormalizedPosition: 0.25,
                height: 400
            ),
            113
        )
    }

    func testIndexedScrollRailMagnificationIsMonotonicAndPinnedAtRadius() {
        let hover: CGFloat = 100
        let positions: [CGFloat] = [42, 55, 75, 95, 100, 105, 125, 145, 158]
        let magnified = positions.map {
            IndexedScrollRailLayout.magnifiedPosition($0, around: hover)
        }

        XCTAssertEqual(magnified, magnified.sorted())
        XCTAssertEqual(magnified.first, positions.first)
        XCTAssertEqual(magnified.last, positions.last)
        XCTAssertLessThan(magnified[3], positions[3])
        XCTAssertGreaterThan(magnified[5], positions[5])
    }

    func testIndexedNativeScrollMapsContentFractionToNativeOrigin() {
        let document = CGRect(x: 0, y: 0, width: 500, height: 10_000)
        let viewport = CGRect(x: 0, y: 0, width: 500, height: 1_000)

        XCTAssertEqual(
            IndexedNativeScrollLayout.targetOrigin(
                contentPosition: 0.4,
                documentBounds: document,
                viewportBounds: viewport,
                documentIsFlipped: true
            ).y,
            4_000
        )
        XCTAssertEqual(
            IndexedNativeScrollLayout.targetOrigin(
                contentPosition: 1,
                documentBounds: document,
                viewportBounds: viewport,
                documentIsFlipped: true
            ).y,
            9_000
        )
    }

    func testIndexedNativeScrollGeometryHotPathIsWellBelowOneFrame() {
        let document = CGRect(x: 0, y: 0, width: 500, height: 530_000)
        let viewport = CGRect(x: 0, y: 0, width: 500, height: 1_200)
        let started = ContinuousClock.now
        var checksum: CGFloat = 0

        for index in 0..<100_000 {
            checksum += IndexedNativeScrollLayout.targetOrigin(
                contentPosition: Double(index % 1_000) / 999,
                documentBounds: document,
                viewportBounds: viewport,
                documentIsFlipped: true
            ).y
        }

        let elapsed = (ContinuousClock.now - started) / .milliseconds(1)
        XCTAssertGreaterThan(checksum, 0)
        XCTAssertLessThan(elapsed, 50)
    }

    private func localUpdateToolbarButtonSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/AppleAppDesignSystem/LocalAppUpdateToolbarButton.swift")
    }
}
