import AppKit
import SwiftUI

/// Reports right-button drags in the board's own coordinate space.
///
/// SwiftUI's `DragGesture` cannot tell which mouse button is down, so the
/// right-drag annotation gesture has to come from AppKit. The view is
/// invisible and, critically, only claims hit tests while a right-mouse
/// event is being routed - every left click passes straight through to the
/// square buttons underneath it.
struct RightDragCatcher: NSViewRepresentable {
    /// Called with the press and release points, in the catcher's own
    /// top-left-origin coordinates.
    var onRightDrag: (CGPoint, CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightDrag = onRightDrag
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onRightDrag = onRightDrag
    }

    final class CatcherView: NSView {
        var onRightDrag: ((CGPoint, CGPoint) -> Void)?
        private var pressLocation: CGPoint?

        /// Top-left origin, so points line up with the SwiftUI layout above
        /// without every caller having to flip them.
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseDragged, .rightMouseUp:
                return self
            default:
                return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            pressLocation = convert(event.locationInWindow, from: nil)
        }

        override func rightMouseUp(with event: NSEvent) {
            defer { pressLocation = nil }
            guard let pressLocation else { return }
            onRightDrag?(pressLocation, convert(event.locationInWindow, from: nil))
        }

        /// Suppresses the system context menu, which would otherwise appear
        /// on top of the annotation the user just drew.
        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
}
