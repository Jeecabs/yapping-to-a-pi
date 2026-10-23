import SwiftUI
import YappingCore

/// The shortcuts that hang off the pill's edge. They're always laid out at the card's full width, so text never
/// reflows or truncates while the card grows; the card's clip uncovers them and they fade in once it leads.
struct BarHintCard: View {
    let hints: [BarHint]
    let detail: BarHoverDetail
    let expandsUp: Bool
    let shown: Bool
    let height: Double
    var onDragEnded: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The card's added height for these hints, so the pill can make room before they're drawn.
    static func height(rows: Int) -> Double {
        Double(rows) * BarStyle.hintRowHeight + BarStyle.hintInset + BarStyle.hintGap
    }

    var body: some View {
        let still = shown || reduceMotion
        BarHintList(hints: hints, detail: detail)
            .padding(.horizontal, BarStyle.hintInset)
            .padding(expandsUp ? .top : .bottom, BarStyle.hintInset)
            .padding(expandsUp ? .bottom : .top, BarStyle.hintGap)
            .frame(width: BarStyle.cardWidth, height: height, alignment: expandsUp ? .bottom : .top)
            .overlay { BarDragHandle(onEnd: onDragEnded) }
            .opacity(shown ? 1 : 0)
            .blur(radius: still ? 0 : 3)
            .scaleEffect(still ? 1 : 0.96, anchor: expandsUp ? .bottom : .top)
            .animation(shown && !reduceMotion ? BarStyle.reveal : BarStyle.fade, value: shown)
            .allowsHitTesting(shown)
    }
}
