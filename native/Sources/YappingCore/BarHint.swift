/// One shortcut the floating bar shows on hover. Keys come from the user's bindings, so hints follow rebinding.
public struct BarHint: Equatable, Identifiable, Sendable {
    public enum Stage: Sendable { case ready, listening, working, needsAccess }

    public let label: String
    public let shortLabel: String
    /// Nil when the hint is an instruction rather than a shortcut.
    public let keys: String?
    /// The compact bar shows only these.
    public let compact: Bool
    public var id: String { label }

    /// What the user can press next, given what the bar is doing now.
    public static func hints(for stage: Stage, shortcuts: ShortcutBindings) -> [BarHint] {
        switch stage {
        case .ready: [
            BarHint(label: "hold to talk", shortLabel: "talk", keys: shortcuts.talk.title, compact: true),
            BarHint(label: "hands-free", shortLabel: "hands-free", keys: shortcuts.handsFree.title, compact: true),
            BarHint(label: "edit selected text", shortLabel: "edit", keys: shortcuts.editSelection.title, compact: false)
        ]
        case .listening: [
            BarHint(label: "let go to finish", shortLabel: "finish", keys: shortcuts.talk.title, compact: true),
            BarHint(label: "stop hands-free", shortLabel: "stop", keys: shortcuts.handsFree.title, compact: false),
            BarHint(label: "cancel", shortLabel: "cancel", keys: shortcuts.cancel.title, compact: true)
        ]
        case .needsAccess: [
            BarHint(label: "shortcuts and paste need Accessibility", shortLabel: "click the dot to allow shortcuts",
                    keys: nil, compact: true)
        ]
        case .working: [
            BarHint(label: "cancel", shortLabel: "cancel", keys: shortcuts.cancel.title, compact: true)
        ]
        }
    }
}
