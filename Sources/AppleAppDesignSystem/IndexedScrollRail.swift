import SwiftUI

/// A semantic destination on a fast-scroll rail. Destinations are ordered in
/// the same direction as the scrollable content.
public struct IndexedScrollRailMarker: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let majorLabel: String?
    /// Optional normalized location on the rail. Omit this value for a
    /// uniformly spaced index. Supplying it enables monotonic, non-linear
    /// scales such as a calendar-and-density blend.
    public let railPosition: Double?
    /// Optional normalized position of the destination in the scrollable
    /// content. Clients can use this for constant-time pixel jumps instead of
    /// resolving a semantic row identifier in a very large list.
    public let destinationPosition: Double?

    public init(
        id: String,
        label: String,
        majorLabel: String? = nil,
        railPosition: Double? = nil,
        destinationPosition: Double? = nil
    ) {
        self.id = id
        self.label = label
        self.majorLabel = majorLabel
        self.railPosition = railPosition
        self.destinationPosition = destinationPosition
    }
}

/// Pure geometry helpers used by `IndexedScrollRail` and available to clients
/// that need to coordinate a custom scroll container.
public enum IndexedScrollRailLayout {
    public static let contentInset: CGFloat = 26
    public static let magnificationRadius: CGFloat = 58
    public static let magnificationFactor: CGFloat = 2.35

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
        guard maximumCount > 0 else { return [] }
        let candidates = markers.indices.filter { markers[$0].majorLabel != nil }
        guard candidates.count > maximumCount else { return candidates }

        // Keep the label cadence regular. Sampling by a rounded ratio can
        // produce an alternating, visually unexplained sequence (for example
        // 9 years, then 8, then 9). A fixed stride is predictable, while the
        // final endpoint is retained when there is still room.
        let stride = Int(ceil(Double(candidates.count) / Double(maximumCount)))
        var result = Swift.stride(from: 0, to: candidates.count, by: stride)
            .map { candidates[$0] }
        if let last = candidates.last,
           result.last != last,
           result.count < maximumCount {
            result.append(last)
        }
        return result
    }

    public static func tickStride(
        markerCount: Int,
        height: CGFloat,
        minimumSpacing: CGFloat,
        candidates: [Int],
        minimumStride: Int = 1
    ) -> Int {
        guard markerCount > 1 else { return 1 }
        let usableHeight = max(1, height - contentInset * 2)
        let spacing = usableHeight / CGFloat(markerCount - 1)
        let minimumStride = max(1, minimumStride)
        let validCandidates = candidates.filter { $0 >= minimumStride }.sorted()
        return validCandidates.first { spacing * CGFloat($0) >= minimumSpacing }
            ?? max(
                validCandidates.last ?? minimumStride,
                minimumStride,
                Int(ceil(minimumSpacing / spacing))
            )
    }

    public static func tickIndices(
        markerCount: Int,
        stride: Int,
        alignment: Int
    ) -> [Int] {
        guard markerCount > 0 else { return [] }
        let stride = max(1, stride)
        let alignment = min(max(alignment, 0), markerCount - 1)
        var indices = Array(Swift.stride(from: alignment, to: markerCount, by: stride))
        var preceding = alignment - stride
        while preceding >= 0 {
            indices.append(preceding)
            preceding -= stride
        }
        indices.append(0)
        indices.append(markerCount - 1)
        return Array(Set(indices)).sorted()
    }

    /// Removes marks that would collide after a non-linear rail transform.
    /// Endpoints remain represented; if the final endpoint conflicts with the
    /// preceding mark, the endpoint replaces that mark.
    public static func spacedIndices(
        _ candidates: [Int],
        normalizedPositions: [Double],
        height: CGFloat,
        minimumSpacing: CGFloat
    ) -> [Int] {
        spacedIndices(
            candidates,
            verticalPositions: normalizedPositions.map {
                verticalPosition(forNormalizedPosition: $0, height: height)
            },
            minimumSpacing: minimumSpacing
        )
    }

    /// Removes marks that collide in their final rendered coordinates. This
    /// supports one continuous, collision-free marker sequence without
    /// compositing a separate hover-only layer.
    public static func spacedIndices(
        _ candidates: [Int],
        verticalPositions: [CGFloat],
        minimumSpacing: CGFloat
    ) -> [Int] {
        let candidates = candidates.filter { verticalPositions.indices.contains($0) }
        guard let first = candidates.first else { return [] }
        guard candidates.count > 1 else { return [first] }

        var result = [first]
        var lastY = verticalPositions[first]
        for candidate in candidates.dropFirst() {
            let y = verticalPositions[candidate]
            if y - lastY >= minimumSpacing {
                result.append(candidate)
                lastY = y
            }
        }

        if let last = candidates.last, result.last != last {
            let lastPosition = verticalPositions[last]
            if result.count > 1,
               let previous = result.last,
               lastPosition - verticalPositions[previous] < minimumSpacing {
                result.removeLast()
            }
            result.append(last)
        }
        return result
    }

    public static func verticalPosition(
        for index: Int,
        height: CGFloat,
        markerCount: Int
    ) -> CGFloat {
        guard markerCount > 1 else { return height / 2 }
        return verticalPosition(
            forNormalizedPosition: Double(index) / Double(markerCount - 1),
            height: height
        )
    }

    public static func verticalPosition(
        forNormalizedPosition position: Double,
        height: CGFloat
    ) -> CGFloat {
        let usableHeight = max(0, height - contentInset * 2)
        return contentInset
            + CGFloat(min(max(position, 0), 1)) * usableHeight
    }

    /// A monotonic local fisheye transform modelled after Dock
    /// magnification. Positions nearest the pointer spread apart while the
    /// edge of the magnification region remains fixed.
    public static func magnifiedPosition(
        _ position: CGFloat,
        around hoverPosition: CGFloat?,
        radius: CGFloat = magnificationRadius,
        factor: CGFloat = magnificationFactor
    ) -> CGFloat {
        guard let hoverPosition, radius > 0, factor > 1 else { return position }
        let delta = position - hoverPosition
        let distance = abs(delta)
        guard distance < radius, distance > 0 else { return position }
        let normalized = distance / radius
        let magnifiedDistance = radius * pow(normalized, 1 / factor)
        return hoverPosition + (delta < 0 ? -magnifiedDistance : magnifiedDistance)
    }

    public static func influence(
        at position: CGFloat,
        around hoverPosition: CGFloat?,
        radius: CGFloat = magnificationRadius
    ) -> CGFloat {
        guard let hoverPosition, radius > 0 else { return 0 }
        let normalized = min(abs(position - hoverPosition) / radius, 1)
        let cosine = cos(normalized * .pi / 2)
        return cosine * cosine
    }
}

/// A compact, native-feeling chronology/index rail that complements rather
/// than replaces the system scrollbar. It uses one Canvas for all tick marks,
/// expands on hover, and magnifies one stable tick sequence around the pointer.
/// Drag selection is coalesced to one callback per display frame.
public struct IndexedScrollRail: View {
    private let markers: [IndexedScrollRailMarker]
    private let tickStrideCandidates: [Int]
    private let minimumTickStride: Int
    private let minimumTickSpacing: CGFloat
    private let magnificationIntensity: CGFloat
    private let tickAlignment: Int
    private let onSelect: (IndexedScrollRailMarker) -> Void

    @State private var isHovering = false
    @State private var hoverLocationY: CGFloat?
    @State private var isDragging = false
    @State private var selectedIndex: Int?
    @State private var lastDispatchedIndex: Int?
    @State private var pendingIndex: Int?
    @State private var dispatchTask: Task<Void, Never>?

    public init(
        markers: [IndexedScrollRailMarker],
        tickStrideCandidates: [Int] = [1, 2, 5, 10, 20, 50, 100],
        minimumTickStride: Int = 1,
        minimumTickSpacing: CGFloat = 3,
        magnificationIntensity: CGFloat = 1,
        tickAlignment: Int = 0,
        onSelect: @escaping (IndexedScrollRailMarker) -> Void
    ) {
        self.markers = markers
        self.tickStrideCandidates = tickStrideCandidates
        self.minimumTickStride = max(1, minimumTickStride)
        self.minimumTickSpacing = max(1, minimumTickSpacing)
        self.magnificationIntensity = max(0, magnificationIntensity)
        self.tickAlignment = tickAlignment
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
        .accessibilityLabel("Publication timeline")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            adjustSelection(direction)
        }
        .onDisappear {
            dispatchTask?.cancel()
            dispatchTask = nil
        }
    }

    private var isExpanded: Bool { isHovering || isDragging }

    private var railWidth: CGFloat { isExpanded ? 104 : 22 }

    private var accessibilityValue: String {
        guard let selectedIndex, markers.indices.contains(selectedIndex) else {
            return "No date selected"
        }
        return markers[selectedIndex].label
    }

    private var focusIndex: Int? {
        if isDragging { return selectedIndex }
        guard let hoverLocationY else { return nil }
        return nearestIndex(to: hoverLocationY, height: currentHeight)
    }

    @State private var currentHeight: CGFloat = 0

    @ViewBuilder
    private func rail(height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            if isExpanded {
                Color.clear
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }

            tickCanvas(height: height)

            if isExpanded {
                majorLabels(height: height)
            }

            if isExpanded,
               let focusIndex,
               markers.indices.contains(focusIndex) {
                focusLabel(for: focusIndex, height: height)
            }
        }
        .frame(width: railWidth, height: height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                isHovering = true
                hoverLocationY = min(max(location.y, 0), height)
            case .ended:
                isHovering = false
                hoverLocationY = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let isFirstChange = !isDragging
                    isDragging = true
                    isHovering = true
                    hoverLocationY = min(max(value.location.y, 0), height)
                    select(
                        at: value.location.y,
                        height: height,
                        immediate: isFirstChange
                    )
                }
                .onEnded { value in
                    isHovering = true
                    hoverLocationY = min(max(value.location.y, 0), height)
                    select(at: value.location.y, height: height, immediate: true)
                    isDragging = false
                }
        )
        .animation(.snappy(duration: 0.14), value: isExpanded)
        .onChange(of: height, initial: true) { _, newHeight in
            currentHeight = newHeight
        }
    }

    private func tickCanvas(height: CGFloat) -> some View {
        let stride = IndexedScrollRailLayout.tickStride(
            markerCount: markers.count,
            height: height,
            minimumSpacing: minimumTickSpacing,
            candidates: tickStrideCandidates,
            minimumStride: minimumTickStride
        )
        let normalizedPositions = markerNormalizedPositions
        let basePositions = normalizedPositions.map {
            IndexedScrollRailLayout.verticalPosition(
                forNormalizedPosition: $0,
                height: height
            )
        }
        let visibleIndices = IndexedScrollRailLayout.spacedIndices(
            IndexedScrollRailLayout.tickIndices(
                markerCount: markers.count,
                stride: stride,
                alignment: tickAlignment
            ),
            verticalPositions: basePositions,
            minimumSpacing: minimumTickSpacing
        )
        let hoverLocationY = hoverLocationY
        let expanded = isExpanded
        let intensity = magnificationIntensity
        let influenceRadius = IndexedScrollRailLayout.magnificationRadius
            * (1 + max(0, intensity - 1) * 0.3)

        return Canvas { context, size in
            guard !visibleIndices.isEmpty else { return }
            let trailingX = size.width - (expanded ? 10 : 5)

            for index in visibleIndices {
                let baseY = basePositions[index]
                let influence = IndexedScrollRailLayout.influence(
                    at: baseY,
                    around: hoverLocationY,
                    radius: influenceRadius
                )
                let isMajor = markers[index].majorLabel != nil
                let y = baseY
                let baseLength: CGFloat = isMajor ? 13 : 7
                // As with Dock icons, the existing item grows under the
                // pointer. Keeping every mark at its stable vertical position
                // avoids compressed bands at the edges of the hover region.
                let expansion = (isMajor ? 5 : 6) * intensity
                let length = baseLength + influence * expansion
                let baseOpacity = isMajor ? 0.70 : 0.38
                let opacity = min(0.92, baseOpacity + influence * 0.26 * intensity)
                let thickness = 1 + influence * 0.45 * intensity
                let path = Path(
                    roundedRect: CGRect(
                        x: trailingX - length,
                        y: y - thickness / 2,
                        width: length,
                        height: thickness
                    ),
                    cornerRadius: thickness / 2
                )
                context.fill(path, with: .color(.secondary.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func majorLabels(height: CGFloat) -> some View {
        let sampledIndices = IndexedScrollRailLayout.majorLabelIndices(
            markers: markers,
            maximumCount: markers.count
        )
        let indices = IndexedScrollRailLayout.spacedIndices(
            sampledIndices,
            normalizedPositions: markerNormalizedPositions,
            height: height,
            minimumSpacing: 22
        )
        ForEach(indices, id: \.self) { index in
            if let label = markers[index].majorLabel {
                let baseY = baseVerticalPosition(for: index, height: height)
                let y = baseY
                let focusY = focusIndex.map {
                    min(
                        max(
                            baseVerticalPosition(for: $0, height: height),
                            IndexedScrollRailLayout.contentInset
                        ),
                        height - IndexedScrollRailLayout.contentInset
                    )
                }
                let isNearFocus = focusY.map { abs($0 - y) < 22 } ?? false
                Text(label)
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .opacity(isNearFocus ? 0 : 1)
                    .position(x: 27, y: y)
            }
        }
    }

    private func focusLabel(for index: Int, height: CGFloat) -> some View {
        let baseY = baseVerticalPosition(for: index, height: height)
        let y = baseY
        return Text(markers[index].label)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .position(
                x: 43,
                y: min(
                    max(y, IndexedScrollRailLayout.contentInset),
                    height - IndexedScrollRailLayout.contentInset
                )
            )
            .allowsHitTesting(false)
    }

    private func nearestIndex(to y: CGFloat, height: CGFloat) -> Int? {
        guard !markers.isEmpty else { return nil }
        var lower = 0
        var upper = markers.count - 1
        while lower < upper {
            let middle = (lower + upper) / 2
            let position = renderedPosition(for: middle, height: height)
            if position < y {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let candidate = lower
        guard candidate > 0 else { return candidate }
        let previous = candidate - 1
        return abs(renderedPosition(for: previous, height: height) - y)
            <= abs(renderedPosition(for: candidate, height: height) - y)
            ? previous
            : candidate
    }

    private func renderedPosition(for index: Int, height: CGFloat) -> CGFloat {
        baseVerticalPosition(for: index, height: height)
    }

    private func baseVerticalPosition(for index: Int, height: CGFloat) -> CGFloat {
        guard markers.indices.contains(index) else { return 0 }
        return IndexedScrollRailLayout.verticalPosition(
            forNormalizedPosition: markerNormalizedPosition(for: index),
            height: height
        )
    }

    private var markerNormalizedPositions: [Double] {
        markers.indices.map(markerNormalizedPosition)
    }

    private func markerNormalizedPosition(for index: Int) -> Double {
        markers[index].railPosition
            ?? (markers.count > 1
                ? Double(index) / Double(markers.count - 1)
                : 0.5)
    }

    private func select(at y: CGFloat, height: CGFloat, immediate: Bool) {
        guard let index = nearestIndex(to: y, height: height) else { return }
        select(index, immediate: immediate)
    }

    private func select(_ index: Int, immediate: Bool) {
        guard markers.indices.contains(index) else { return }
        selectedIndex = index
        pendingIndex = index

        if immediate {
            dispatchTask?.cancel()
            dispatchTask = nil
            dispatchPendingSelection()
            return
        }

        guard dispatchTask == nil else { return }
        dispatchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            dispatchTask = nil
            dispatchPendingSelection()
        }
    }

    private func dispatchPendingSelection() {
        guard let index = pendingIndex else { return }
        pendingIndex = nil
        guard markers.indices.contains(index),
              lastDispatchedIndex != index else { return }
        lastDispatchedIndex = index
        onSelect(markers[index])
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        guard !markers.isEmpty else { return }
        switch direction {
        case .increment:
            let current = selectedIndex ?? -1
            select(min(current + 1, markers.count - 1), immediate: true)
        case .decrement:
            let current = selectedIndex ?? 1
            select(max(current - 1, 0), immediate: true)
        @unknown default:
            break
        }
    }
}
