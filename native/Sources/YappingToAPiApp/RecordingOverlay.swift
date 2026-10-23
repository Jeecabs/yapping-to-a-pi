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
    private var hintHeight: Double { BarHintCard.height(rows: options.hover == .compact ? 1 : hints.count) }

    var body: some View {
        let scale = options.scale
        let up = model.barExpandsUp
        let shape = RoundedRectangle(cornerRadius: BarStyle.radius)
        BarControls(model: model, openHub: openHub, onDragEnded: onDragEnded)
            .frame(width: showsHints ? BarStyle.cardWidth : nil)
            // The hints hang at a fixed place beside the pill, which doesn't move. Pinned to the card's growing
            // edge instead, they would start on top of the controls and ride the edge out.
            .overlay(alignment: up ? .top : .bottom) {
                if options.hover != .off {
                    BarHintCard(hints: hints, detail: options.hover, expandsUp: up, shown: showsHints, height: hintHeight,
                                onDragEnded: onDragEnded)
                        .offset(y: up ? -hintHeight : hintHeight)
                }
            }
            .padding(up ? .top : .bottom, showsHints ? hintHeight : 0)
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
