import Carbon
import YappingCore

/// What macOS itself does with keys, so a binding can stay out of its way.
enum SystemShortcuts {
    /// The shortcuts turned on in System Settings › Keyboard › Keyboard Shortcuts.
    static func enabled() -> [KeyBinding] {
        var copied: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&copied) == noErr,
              let entries = copied?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int, code < 0xFFFF,
                  let flags = entry[kHISymbolicHotKeyModifiers as String] as? Int else { return nil }
            return KeyBinding(keyCode: UInt16(code), modifiers: modifiers(flags), keyLabel: "")
        }
    }

    /// Whether pressing 🌐 also does something in macOS, such as emoji or switching input source. Unset means
    /// the system default, which does.
    static var globeKeyActs: Bool {
        CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
        let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString)
        return (value as? Int) != 0
    }

    private static func modifiers(_ flags: Int) -> KeyModifiers {
        var result: KeyModifiers = []
        if flags & controlKey != 0 { result.insert(.control) }
        if flags & optionKey != 0 { result.insert(.option) }
        if flags & shiftKey != 0 { result.insert(.shift) }
        if flags & cmdKey != 0 { result.insert(.command) }
        if flags & Int(kEventKeyModifierFnMask) != 0 { result.insert(.function) }
        return result
    }
}
