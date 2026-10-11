import Foundation

/// Modifier state, independent of AppKit and CoreGraphics so bindings can be stored and tested.
public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
    public static let function = KeyModifiers(rawValue: 1 << 4)

    var symbols: [String] {
        [(Self.function, "fn"), (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { contains($0.0) }.map(\.1)
    }
}

/// One physical key plus the modifiers held with it. A modifier key on its own (fn, right ⌥) is a valid binding.
public struct KeyBinding: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: KeyModifiers
    public var keyLabel: String

    public init(keyCode: UInt16, modifiers: KeyModifiers = [], keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = Self.normalized(modifiers, keyCode: keyCode).subtracting(Self.modifierKeys[keyCode]?.flag ?? [])
        self.keyLabel = keyLabel
    }

    public static let modifierKeys: [UInt16: (flag: KeyModifiers, label: String)] = [
        63: (.function, "fn"), 59: (.control, "left ⌃"), 62: (.control, "right ⌃"),
        58: (.option, "left ⌥"), 61: (.option, "right ⌥"), 56: (.shift, "left ⇧"), 60: (.shift, "right ⇧"),
        55: (.command, "left ⌘"), 54: (.command, "right ⌘")
    ]

    /// Keys whose events always carry the fn flag on Mac keyboards: F-keys, arrows and the navigation block.
    static let implicitFunctionKeys: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
        123, 124, 125, 126, 115, 119, 116, 121, 117, 114
    ]

    public static func normalized(_ modifiers: KeyModifiers, keyCode: UInt16) -> KeyModifiers {
        implicitFunctionKeys.contains(keyCode) ? modifiers.subtracting(.function) : modifiers
    }

    /// The flag this key sets while held, or nil for an ordinary key.
    public var ownModifier: KeyModifiers? { Self.modifierKeys[keyCode]?.flag }
    public var isModifierOnly: Bool { ownModifier != nil }
    var isFunctionKey: Bool { Self.implicitFunctionKeys.contains(keyCode) }

    /// "fn", "fn space", "⌃ fn", "⌘⇧ d"
    public var title: String {
        let symbols = modifiers.symbols
        let prefix = symbols.contains("fn") ? ["fn"] + [symbols.filter { $0 != "fn" }.joined()] : [symbols.joined()]
        return (prefix + [keyLabel]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Ordinary keys must match their modifiers exactly, so ⌘D never fires a ⌘⇧D binding.
    public func matchesPress(keyCode: UInt16, modifiers: KeyModifiers) -> Bool {
        keyCode == self.keyCode
            && Self.normalized(modifiers, keyCode: keyCode).subtracting(ownModifier ?? []) == self.modifiers
    }
}

public struct ShortcutBindings: Codable, Equatable, Sendable {
    public enum Action: String, CaseIterable, Sendable {
        case talk, handsFree, editSelection, cancel
        public var title: String {
            switch self {
            case .talk: "Hold to talk"
            case .handsFree: "Hands-free on or off"
            case .editSelection: "Hold to edit selected text"
            case .cancel: "Cancel while recording"
            }
        }
    }

    public var talk: KeyBinding
    public var handsFree: KeyBinding
    public var editSelection: KeyBinding
    public var cancel: KeyBinding

    public static let fn = KeyBinding(keyCode: 63, keyLabel: "fn")
    public static let defaults = ShortcutBindings(hotkey: .function)

    /// Builds the bindings that the single hold-key choice used to imply.
    public init(hotkey: HotkeyChoice) {
        talk = hotkey == .function ? Self.fn : KeyBinding(keyCode: 61, keyLabel: "right ⌥")
        let held: KeyModifiers = hotkey == .function ? .function : .option
        handsFree = KeyBinding(keyCode: 49, modifiers: held, keyLabel: "space")
        editSelection = KeyBinding(keyCode: talk.keyCode, modifiers: .control, keyLabel: talk.keyLabel)
        cancel = KeyBinding(keyCode: 53, keyLabel: "esc")
    }

    public subscript(action: Action) -> KeyBinding {
        get {
            switch action {
            case .talk: talk
            case .handsFree: handsFree
            case .editSelection: editSelection
            case .cancel: cancel
            }
        }
        set {
            switch action {
            case .talk: talk = newValue
            case .handsFree: handsFree = newValue
            case .editSelection: editSelection = newValue
            case .cancel: cancel = newValue
            }
        }
    }

    /// Which hold action a key starts given the modifiers held now. Talk and edit may share a key
    /// (fn and ⌃ fn); the binding whose modifiers are all held, with the most modifiers, wins.
    public func holdAction(keyCode: UInt16, modifiers: KeyModifiers) -> Action? {
        [Action.editSelection, .talk]
            .filter { action in
                let binding = self[action]
                let held = KeyBinding.normalized(modifiers, keyCode: keyCode).subtracting(binding.ownModifier ?? [])
                return binding.keyCode == keyCode && binding.modifiers.isSubset(of: held)
            }
            .max { self[$0].modifiers.rawValue.nonzeroBitCount < self[$1].modifiers.rawValue.nonzeroBitCount }
    }

    /// A sentence for the user if `binding` can't be used for `action`, otherwise nil.
    public func problem(with binding: KeyBinding, for action: Action) -> String? {
        if action == .cancel, binding.isModifierOnly { return "Cancel needs a regular key, such as esc." }
        if action != .cancel, !binding.isModifierOnly, !binding.isFunctionKey, binding.modifiers.isEmpty {
            return "Add a modifier such as ⌃ or ⌥, so typing \(binding.keyLabel) still works."
        }
        let reserved: [(UInt16, KeyModifiers)] = [(12, .command), (13, .command), (48, .command), (49, .command)]
        if reserved.contains(where: { $0.0 == binding.keyCode && $0.1 == binding.modifiers }) {
            return "\(binding.title) belongs to macOS. Choose another shortcut."
        }
        if let clash = Action.allCases.first(where: { $0 != action && self[$0] == binding }) {
            return "\(binding.title) is already used for \(clash.title.lowercased())."
        }
        return nil
    }
}
