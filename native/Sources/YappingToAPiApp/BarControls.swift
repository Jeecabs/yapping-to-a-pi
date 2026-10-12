import SwiftUI
import YappingCore

/// The pill's own row: start, cancel and finish, the live meter, and short notices. It keeps its natural width,
/// so its buttons stay put while the bar opens around them.
struct BarControls: View {
    let model: AppModel
    var openHub: () -> Void
    var onDragEnded: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if model.isBusy {
                BarIconButton(title: "Cancel dictation", systemImage: "xmark", width: 22,
                              help: "Cancel dictation (\(model.data.settings.shortcuts.cancel.title))", action: model.cancel)
                if model.phase == .listening {
                    InputMeter(samples: model.waveform.samples, sensitivity: model.data.settings.appearanceOptions.sensitivity)
                        .frame(width: BarStyle.meterWidth)
                        .overlay { BarDragHandle(onEnd: onDragEnded) }.help("Drag to move")
                        .transition(.blurReplace)
                    BarIconButton(title: "Finish dictation", systemImage: "stop.fill", width: 22, action: model.stop)
                } else {
                    ProgressView().controlSize(.mini).tint(.white)
                    Text(model.phase == .preparing ? model.preparationLabel : "Finishing")
                        .font(.system(size: 10, weight: .medium)).contentTransition(.opacity)
                        .overlay { BarDragHandle(onEnd: onDragEnded) }.help("Drag to move")
                        .transition(.blurReplace)
                }
            } else {
                BarIconButton(title: "Start dictation", systemImage: "mic.fill", action: start)
                if let notice = model.barNotice, !model.previewingBar {
                    HStack(spacing: 5) {
                        if notice.kind == .landed {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.signal)
                        }
                        Text(notice.text).foregroundStyle(notice.kind == .landed ? .white : Palette.signal)
                    }
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
                    .overlay { BarDragHandle(onEnd: onDragEnded) }.help(model.status.isEmpty ? notice.text : model.status)
                    .transition(.blurReplace)
                } else if !model.shortcutReady && !model.previewingBar {
                    // Without Accessibility the shortcut can't be heard and text can't be pasted. A quiet dot in the
                    // bar's usual slot says so without changing its shape; the tooltip and click explain the rest.
                    Button(action: model.requestAccessibility) {
                        Circle().fill(Palette.signal).frame(width: 6, height: 6).frame(width: 10, height: 28).contentShape(.rect)
                    }
                    .buttonStyle(BarButtonStyle())
                    .help("Shortcut and paste need Accessibility. Click to allow.").accessibilityLabel("Allow Accessibility")
                } else if model.previewingBar {
                    InputMeter(samples: [0.08, 0.17, 0.35, 0.65, 0.88, 0.56, 0.24, 0.46, 0.73, 0.95, 0.63, 0.27, 0.1],
                               sensitivity: model.data.settings.appearanceOptions.sensitivity)
                        .frame(width: BarStyle.meterWidth)
                        .overlay { BarDragHandle(onEnd: onDragEnded) }.help("Drag to move")
                        .transition(.blurReplace)
                } else {
                    Image(systemName: "ellipsis").font(.system(size: 8)).frame(width: 10, height: 28)
                        .overlay { BarDragHandle(onEnd: onDragEnded) }.help("Drag to move")
                        .transition(.blurReplace)
                }
                BarIconButton(title: "Open \(Brand.name)", systemImage: model.status.isEmpty ? "arrow.up.right" : "text.bubble",
                              help: model.status.isEmpty ? nil : model.status, action: openHub)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: BarStyle.rowHeight)
        .fixedSize()
    }

    private func start() { model.start() }
}
