import SwiftUI
import YappingCore

/// The shortcuts revealed when the pointer rests on the floating bar.
struct BarHintList: View {
    let hints: [BarHint]
    let detail: BarHoverDetail

    var body: some View {
        if detail == .compact {
            HStack(spacing: 12) {
                ForEach(hints.filter(\.compact)) { hint in
                    HStack(spacing: 5) {
                        if let keys = hint.keys { KeyChip(keys: keys) }
                        Text(hint.shortLabel).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: BarStyle.hintRowHeight)
        } else {
            VStack(spacing: 0) {
                ForEach(hints) { hint in
                    HStack {
                        Text(hint.label).foregroundStyle(.white.opacity(0.7))
                        Spacer(minLength: 8)
                        if let keys = hint.keys { KeyChip(keys: keys) }
                    }
                    .frame(height: BarStyle.hintRowHeight)
                }
            }
        }
    }
}
