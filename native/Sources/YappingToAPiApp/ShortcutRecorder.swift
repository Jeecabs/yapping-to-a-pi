import AppKit
import SwiftUI
import YappingCore

/// Click, then press keys. Ordinary keys record on key down; a modifier on its own records when it is
/// released without another key, so fn, right ⌥ and ⌃ fn can all be hold keys.
struct ShortcutRecorder: View {
    @Bindable var model: AppModel
    let action: ShortcutBindings.Action
    @State private var listening = false
    @State private var monitor: Any?
    @State private var pendingModifier: KeyBinding?

    var body: some View {
        Button { listening ? stop() : start() } label: {
            Text(listening ? "press keys…" : model.data.settings.shortcuts[action].title)
                .font(Brand.mono(12)).frame(minWidth: 96)
        }
        .buttonStyle(LineButtonStyle())
        .overlay { if listening { RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.accent, lineWidth: 1.5) } }
        .help(listening ? "Press the new shortcut. Click again to keep the current one." : "Click to change")
        .accessibilityLabel("\(action.title): \(model.data.settings.shortcuts[action].title). Click to change.")
        .onDisappear(perform: stop)
    }

    private func start() {
        guard !listening else { return }
        listening = true
        model.recordingShortcut = true
        pendingModifier = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            receive(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        listening = false
        pendingModifier = nil
        model.recordingShortcut = false
    }

    private func receive(_ event: NSEvent) {
        let modifiers = Self.modifiers(event.modifierFlags)
        if event.type == .keyDown {
            save(KeyBinding(keyCode: event.keyCode, modifiers: modifiers, keyLabel: Self.label(event)))
            return
        }
        guard let (flag, label) = KeyBinding.modifierKeys[event.keyCode].map({ ($0.flag, $0.label) }) else { return }
        if modifiers.contains(flag) {
            pendingModifier = KeyBinding(keyCode: event.keyCode, modifiers: modifiers, keyLabel: label)
        } else if let pending = pendingModifier, pending.keyCode == event.keyCode {
            save(pending)
        }
    }

    private func save(_ binding: KeyBinding) {
        if let problem = model.data.settings.shortcuts.problem(with: binding, for: action, system: SystemShortcuts.enabled()) {
            model.showStatus(problem)
        } else {
            model.data.settings.shortcuts[action] = binding
            model.status = ""
        }
        stop()
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var result: KeyModifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.function) { result.insert(.function) }
        return result
    }

    static func label(_ event: NSEvent) -> String {
        let named: [UInt16: String] = [
            49: "space", 53: "esc", 36: "return", 76: "enter", 48: "tab", 51: "delete", 117: "fwd delete",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "home", 119: "end", 116: "page up", 121: "page down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
            109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
            79: "F18", 80: "F19", 90: "F20"
        ]
        if let name = named[event.keyCode] { return name }
        return (event.charactersIgnoringModifiers ?? "key").lowercased()
    }
}
