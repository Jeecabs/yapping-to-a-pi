import SwiftUI

/// A shortcut drawn as a small key cap.
struct KeyChip: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(Brand.mono(10)).foregroundStyle(.white)
            .padding(.horizontal, 5).frame(height: 16)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.16)) }
    }
}
