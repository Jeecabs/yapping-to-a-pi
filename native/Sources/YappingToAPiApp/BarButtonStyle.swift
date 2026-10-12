import SwiftUI

/// Press feedback for the bar's small icon buttons.
struct BarButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(BarStyle.fade, value: configuration.isPressed)
    }
}
