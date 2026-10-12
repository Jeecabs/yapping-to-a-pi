import SwiftUI

/// An icon-only bar button that still carries its title for VoiceOver.
struct BarIconButton: View {
    let title: String
    let systemImage: String
    var width = 24.0
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).labelStyle(.iconOnly)
                .frame(width: width, height: 28).contentShape(.rect)
        }
        .buttonStyle(BarButtonStyle())
        .help(help ?? title)
    }
}
