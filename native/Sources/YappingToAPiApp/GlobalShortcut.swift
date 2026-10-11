import AppKit
import ApplicationServices
import YappingCore

@MainActor
final class GlobalShortcut {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gesture = ShortcutGesture()
    private var holdTask: Task<Void, Never>?
    private var bindings = ShortcutBindings.defaults
    /// The hold key currently down, and the modifiers held right now.
    private var heldKey: UInt16?
    private var modifiers: KeyModifiers = []
    var onStart: ((Bool) -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var isRecording: (() -> Bool)?
    /// While Settings records a new shortcut, keys go to the recorder instead of starting dictation.
    var isSuspended: (() -> Bool)?

    @discardableResult
    func install(bindings: ShortcutBindings) -> Bool {
        self.bindings = bindings
        if let tap { CGEvent.tapEnable(tap: tap, enable: true); return true }
        guard AXIsProcessTrusted() else { return false }
        let mask = [CGEventType.flagsChanged, .keyDown, .keyUp].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<GlobalShortcut>.fromOpaque(info).takeUnretainedValue()
            let handled = MainActor.assumeIsolated { owner.handle(type, event: event) }
            return handled ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask,
                                         callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func reset() { holdTask?.cancel(); holdTask = nil; heldKey = nil; gesture.reset() }

    func uninstall() {
        reset()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil
    }

    static func modifiers(_ flags: CGEventFlags) -> KeyModifiers {
        var result: KeyModifiers = []
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskSecondaryFn) { result.insert(.function) }
        return result
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reset()
            onCancel?()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard isSuspended?() != true else { return false }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        modifiers = Self.modifiers(event.flags)

        if type == .flagsChanged {
            guard let own = KeyBinding.modifierKeys[code]?.flag else { return false }
            let down = modifiers.contains(own)
            if bindings.handsFree.isModifierOnly, down, bindings.handsFree.matchesPress(keyCode: code, modifiers: modifiers) {
                holdTask?.cancel()
                dispatch(gesture.toggle(), key: nil)
                return true
            }
            if down, heldKey == nil, bindings.holdAction(keyCode: code, modifiers: modifiers) != nil {
                press(code)
                return true
            }
            if !down, heldKey == code {
                release()
                return true
            }
            return false
        }

        let repeating = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if bindings.cancel.matchesPress(keyCode: code, modifiers: modifiers), isRecording?() == true {
            if type == .keyDown { reset(); onCancel?() }
            return true
        }
        if bindings.handsFree.matchesPress(keyCode: code, modifiers: modifiers) {
            if type == .keyDown, !repeating {
                holdTask?.cancel()
                dispatch(gesture.toggle(), key: nil)
            }
            return true
        }
        // Ordinary keys can be hold bindings too, such as F5 or ⌃⌥ d.
        if heldKey == code, KeyBinding.modifierKeys[code] == nil {
            if type == .keyUp { release() }
            return true
        }
        if type == .keyDown, !repeating, heldKey == nil, KeyBinding.modifierKeys[code] == nil,
           bindings.holdAction(keyCode: code, modifiers: modifiers) != nil {
            press(code)
            return true
        }
        if type == .keyDown, let heldKey, KeyBinding.modifierKeys[heldKey] != nil {
            // Another key while a modifier hold key is down is a normal combination, such as fn-F6 for Pi.
            holdTask?.cancel()
            if gesture.active && !gesture.handsFree { onCancel?() }
            gesture.reset()
            self.heldKey = nil
        }
        return false
    }

    private func press(_ code: UInt16) {
        heldKey = code
        dispatch(gesture.press(at: ProcessInfo.processInfo.systemUptime), key: code)
        holdTask?.cancel()
        holdTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard let self else { return }
            dispatch(gesture.hold(), key: heldKey)
        }
    }

    private func release() {
        holdTask?.cancel()
        heldKey = nil
        dispatch(gesture.release(at: ProcessInfo.processInfo.systemUptime), key: nil)
    }

    private func dispatch(_ action: ShortcutGesture.Action?, key: UInt16?) {
        switch action {
        case .start:
            // Decide talk or edit when recording starts, so the edit modifier can be added after the key.
            let edit = key.flatMap { bindings.holdAction(keyCode: $0, modifiers: modifiers) } == .editSelection
            onStart?(edit)
        case .stop: onStop?()
        case .cancel: onCancel?()
        case nil: break
        }
    }
}
