import SwiftUI

/// Reports the pointer entering and leaving, even while the app is in the background. SwiftUI's own hover
/// tracking only follows the key window, and the floating bar's panel never becomes key.
struct HoverTracker: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) { view.onChange = onChange }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
        /// Tracks the pointer only; clicks go to the controls in front.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
