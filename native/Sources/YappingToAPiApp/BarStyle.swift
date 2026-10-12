import SwiftUI

/// Shared sizes and motion for the floating bar. Sizes are in points before the user's bar scale.
enum BarStyle {
    static let rowHeight = 32.0
    /// The idle pill, used to keep a dragged bar reachable on screen.
    static let restingWidth = 90.0
    static let cardWidth = 236.0
    static let radius = 16.0
    static let hintRowHeight = 22.0
    static let hintPadding = 8.0
    static let maxHintRows = 3.0
    static let meterWidth = 72.0
    /// Room around the pill inside the panel for its shadow.
    static let inset = 14.0

    static var canvas: CGSize {
        CGSize(width: cardWidth + inset * 2, height: rowHeight + hintPadding * 2 + hintRowHeight * maxHintRows + inset * 2)
    }

    /// Opening waits a beat so a pointer passing over the bar doesn't open it.
    static let openDelay = Duration.milliseconds(140)
    /// Closing waits a little longer, so slipping off the edge doesn't snap it shut.
    static let closeDelay = Duration.milliseconds(260)
    static let open = Animation.spring(duration: 0.28, bounce: 0)
    static let close = Animation.spring(duration: 0.2, bounce: 0)
    /// State changes: idle, listening, finishing and notices.
    static let morph = Animation.spring(duration: 0.26, bounce: 0)
    static let fade = Animation.easeOut(duration: 0.12)
}
