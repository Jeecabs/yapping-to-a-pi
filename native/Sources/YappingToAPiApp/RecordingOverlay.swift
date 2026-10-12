import SwiftUI
import YappingCore

/// The floating bar. Its panel is a fixed canvas, so every change of shape here is a SwiftUI animation rather
/// than a window resize: the pill morphs between states, and opens into a card of shortcuts on hover.
struct RecordingOverlay: View {
    let model: AppModel
    var openHub: () -> Void
    var onDragEnded: () -> Void = {}

    @State private var expanded = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var cardSize = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var options: AppearancePreferences { model.data.settings.appearanceOptions }
    private var showsHints: Bool { expanded && options.hover != .off }
    private var hints: [BarHint] {
        let stage: BarHint.Stage = switch model.phase {
        case .listening: .listening
        case .idle: model.shortcutReady || model.previewingBar ? .ready : .needsAccess
        default: .working
        }
        return BarHint.hints(for: stage, shortcuts: model.data.settings.shortcuts)
    }
    private var hintTransition: AnyTransition {
        let insertion: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .offset(y: model.barExpandsUp ? 6 : -6))
        return .asymmetric(insertion: insertion.animation(BarStyle.open.delay(0.04)), removal: .opacity.animation(BarStyle.fade))
    }

    var body: some View {
        let scale = options.scale
        let up = model.barExpandsUp
        let shape = RoundedRectangle(cornerRadius: BarStyle.radius)
        VStack(spacing: 0) {
            if showsHints && up {
                BarHintList(hints: hints, detail: options.hover)
                    .padding([.horizontal, .top], BarStyle.hintPadding + 4).padding(.bottom, 2)
                    .overlay { BarDragHandle(onEnd: onDragEnded) }
                    .transition(hintTransition)
            }
            BarControls(model: model, openHub: openHub, onDragEnded: onDragEnded)
            if showsHints && !up {
                BarHintList(hints: hints, detail: options.hover)
                    .padding([.horizontal, .bottom], BarStyle.hintPadding + 4).padding(.top, 2)
                    .overlay { BarDragHandle(onEnd: onDragEnded) }
                    .transition(hintTransition)
            }
        }
        .frame(width: showsHints ? BarStyle.cardWidth : nil)
        .background { shape.fill(Palette.overlay.opacity(options.opacity)).strokeBorder(.white.opacity(0.14)) }
        .clipShape(shape)
        .shadow(color: .black.opacity(0.3), radius: 9, y: 3)
        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : BarStyle.morph, value: model.phase)
        .animation(reduceMotion ? nil : BarStyle.morph, value: model.barNotice)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
        .scaleEffect(scale, anchor: up ? .bottom : .top)
        // Tracks the pill or card as drawn, after scaling; the transparent rest of the panel lets clicks through.
        .background(alignment: up ? .bottom : .top) {
            HoverTracker(onChange: hover).frame(width: cardSize.width * scale, height: cardSize.height * scale)
        }
        .padding(up ? .bottom : .top, BarStyle.inset * scale)
        .frame(width: BarStyle.canvas.width * scale, height: BarStyle.canvas.height * scale, alignment: up ? .bottom : .top)
    }

    /// Opens after a short rest and closes after a short grace, so passing over or slipping off doesn't flicker.
    private func hover(_ inside: Bool) {
        hoverTask?.cancel()
        guard inside != expanded else { return }
        hoverTask = Task {
            try? await Task.sleep(for: inside ? BarStyle.openDelay : BarStyle.closeDelay)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : inside ? BarStyle.open : BarStyle.close) { expanded = inside }
        }
    }
}
