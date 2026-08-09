import AppKit
import SwiftUI

/// Constant-time native scrolling for large SwiftUI scroll documents. Place
/// `IndexedNativeScrollTargetReader` inside the scroll content so the reader
/// can bind this controller to its exact enclosing `NSScrollView`.
@MainActor
public final class IndexedNativeScrollController {
    private weak var scrollView: NSScrollView?

    public init() {}

    public var isConnected: Bool { scrollView != nil }

    @discardableResult
    public func scroll(toContentPosition position: Double) -> Bool {
        guard let scrollView,
              let documentView = scrollView.documentView else { return false }
        let clipView = scrollView.contentView
        let origin = IndexedNativeScrollLayout.targetOrigin(
            contentPosition: position,
            documentBounds: documentView.bounds,
            viewportBounds: clipView.bounds,
            documentIsFlipped: documentView.isFlipped
        )
        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)
        return true
    }

    fileprivate func connect(to scrollView: NSScrollView) {
        self.scrollView = scrollView
    }
}

public enum IndexedNativeScrollLayout {
    public static func targetOrigin(
        contentPosition: Double,
        documentBounds: CGRect,
        viewportBounds: CGRect,
        documentIsFlipped: Bool
    ) -> CGPoint {
        let fraction = CGFloat(min(max(contentPosition, 0), 1))
        let minimumY = documentBounds.minY
        let maximumY = max(
            minimumY,
            documentBounds.maxY - viewportBounds.height
        )
        let contentY = documentBounds.minY + fraction * documentBounds.height
        let flippedY = min(max(contentY, minimumY), maximumY)
        let y = documentIsFlipped
            ? flippedY
            : maximumY - (flippedY - minimumY)
        return CGPoint(x: viewportBounds.origin.x, y: y)
    }
}

/// A zero-height reader placed inside scroll content. Unlike view-tree
/// introspection from an overlay, the superview chain identifies the exact
/// scroll view even when multiple lists occupy the same bounds.
public struct IndexedNativeScrollTargetReader: NSViewRepresentable {
    public let controller: IndexedNativeScrollController

    public init(controller: IndexedNativeScrollController) {
        self.controller = controller
    }

    public func makeNSView(context: Context) -> ProbeView {
        ProbeView(controller: controller)
    }

    public func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.controller = controller
        nsView.connectIfPossible()
    }

    public final class ProbeView: NSView {
        fileprivate var controller: IndexedNativeScrollController

        fileprivate init(controller: IndexedNativeScrollController) {
            self.controller = controller
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            connectIfPossible()
            DispatchQueue.main.async { [weak self] in
                self?.connectIfPossible()
            }
        }

        fileprivate func connectIfPossible() {
            var candidate = superview
            while let view = candidate {
                if let scrollView = view as? NSScrollView {
                    controller.connect(to: scrollView)
                    return
                }
                candidate = view.superview
            }
        }
    }
}
