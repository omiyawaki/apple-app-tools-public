import SwiftUI

/// A semantic destination on a fast-scroll rail. Destinations are ordered in
/// the same direction as the scrollable content.
public struct IndexedScrollRailMarker: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let majorLabel: String?

    public init(id: String, label: String, majorLabel: String? = nil) {
        self.id = id
        self.label = label
        self.majorLabel = majorLabel
    }
}

/// Pure geometry helpers used by `IndexedScrollRail` and available to clients
/// that need to coordinate a custom scroll container.
public enum IndexedScrollRailLayout {
    public static func markerIndex(
        at verticalLocation: CGFloat,
        height: CGFloat,
        markerCount: Int
    ) -> Int? {
        guard markerCount > 0 else { return nil }
        guard markerCount > 1, height > 0 else { return 0 }
        let progress = min(max(verticalLocation / height, 0), 1)
        return min(Int((progress * CGFloat(markerCount - 1)).rounded()), markerCount - 1)
    }

    public static func sampledIndices(markerCount: Int, maximumCount: Int) -> [Int] {
        guard markerCount > 0, maximumCount > 0 else { return [] }
        guard markerCount > maximumCount, maximumCount > 1 else {
            return Array(0..<markerCount)
        }
        return (0..<maximumCount).map { sample in
            Int(
                (CGFloat(sample) * CGFloat(markerCount - 1)
                    / CGFloat(maximumCount - 1)).rounded()
            )
        }
    }

    public static func majorLabelIndices(
        markers: [IndexedScrollRailMarker],
        maximumCount: Int
    ) -> [Int] {
        let candidates = markers.indices.filter { markers[$0].majorLabel != nil }
        guard candidates.count > maximumCount else { return candidates }
        return sampledIndices(
            markerCount: candidates.count,
            maximumCount: maximumCount
        ).map { candidates[$0] }
    }
}

/// A compact, native-feeling chronology/index rail that complements rather
/// than replaces the system scrollbar. Hovering or dragging expands the rail;
/// a drag selects semantic destinations instead of estimating row offsets.
public struct IndexedScrollRail: View {
    private let markers: [IndexedScrollRailMarker]
    private let onSelect: (IndexedScrollRailMarker) -> Void

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var selectedIndex: Int?

    public init(
        markers: [IndexedScrollRailMarker],
        onSelect: @escaping (IndexedScrollRailMarker) -> Void
    ) {
        self.markers = markers
        self.onSelect = onSelect
    }

    public var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                rail(height: geometry.size.height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            adjustSelection(direction)
        }
    }

    private var isExpanded: Bool { isHovering || isDragging }

    private var railWidth: CGFloat { isExpanded ? 82 : 22 }

    private var accessibilityValue: String {
        guard let selectedIndex, markers.indices.contains(selectedIndex) else {
            return "No date selected"
        }
        return markers[selectedIndex].label
    }

    @ViewBuilder
    private func rail(height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            if isExpanded {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
            }

            tickMarks(height: height)

            if isExpanded {
                majorLabels(height: height)
            }

            if isDragging,
               let selectedIndex,
               markers.indices.contains(selectedIndex) {
                selectionLabel(for: selectedIndex, height: height)
            }
        }
        .frame(width: railWidth, height: height)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    select(at: value.location.y, height: height)
                }
                .onEnded { value in
                    select(at: value.location.y, height: height)
                    isDragging = false
                }
        )
        .animation(.snappy(duration: 0.16), value: isExpanded)
    }

    @ViewBuilder
    private func tickMarks(height: CGFloat) -> some View {
        let sampled = IndexedScrollRailLayout.sampledIndices(
            markerCount: markers.count,
            maximumCount: max(12, Int(height / 5))
        )
        ForEach(sampled, id: \.self) { index in
            let marker = markers[index]
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(marker.majorLabel == nil ? 0.38 : 0.72))
                .frame(width: marker.majorLabel == nil ? 4 : (isExpanded ? 12 : 8), height: 1)
                .position(
                    x: railWidth - (isExpanded ? 10 : 6),
                    y: verticalPosition(for: index, height: height)
                )
        }
    }

    @ViewBuilder
    private func majorLabels(height: CGFloat) -> some View {
        let indices = IndexedScrollRailLayout.majorLabelIndices(
            markers: markers,
            maximumCount: max(2, min(12, Int(height / 38)))
        )
        ForEach(indices, id: \.self) { index in
            if let label = markers[index].majorLabel {
                Text(label)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .position(
                        x: 25,
                        y: verticalPosition(for: index, height: height)
                    )
            }
        }
    }

    private func selectionLabel(for index: Int, height: CGFloat) -> some View {
        Text(markers[index].label)
            .font(.caption.weight(.medium).monospacedDigit())
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 4, y: 1)
            .position(
                x: 34,
                y: min(max(verticalPosition(for: index, height: height), 16), height - 16)
            )
    }

    private func verticalPosition(for index: Int, height: CGFloat) -> CGFloat {
        guard markers.count > 1 else { return height / 2 }
        let inset: CGFloat = 10
        let usableHeight = max(0, height - (inset * 2))
        return inset + CGFloat(index) / CGFloat(markers.count - 1) * usableHeight
    }

    private func select(at y: CGFloat, height: CGFloat) {
        guard let index = IndexedScrollRailLayout.markerIndex(
            at: y - 10,
            height: max(0, height - 20),
            markerCount: markers.count
        ) else { return }
        select(index)
    }

    private func select(_ index: Int) {
        guard markers.indices.contains(index), selectedIndex != index else { return }
        selectedIndex = index
        onSelect(markers[index])
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        guard !markers.isEmpty else { return }
        switch direction {
        case .increment:
            let current = selectedIndex ?? -1
            select(min(current + 1, markers.count - 1))
        case .decrement:
            let current = selectedIndex ?? 1
            select(max(current - 1, 0))
        @unknown default:
            break
        }
    }
}
