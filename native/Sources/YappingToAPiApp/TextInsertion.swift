import AppKit
import ApplicationServices

@MainActor
struct TextDestination {
    let app: NSRunningApplication
    let element: AXUIElement?
    let selection: NSRange?
    let selectedText: String
    let originalValue: String?
    let secure: Bool
    var name: String { app.localizedName ?? "App" }
    var bundleID: String { app.bundleIdentifier ?? "" }

    static func capture() -> TextDestination? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let element = focusedElement()
        let subrole = element.flatMap { stringAttribute($0, kAXSubroleAttribute) }
        return TextDestination(app: app, element: element, selection: element.flatMap(selectedRange),
                               selectedText: element.flatMap { stringAttribute($0, kAXSelectedTextAttribute) } ?? "",
                               originalValue: element.flatMap { stringAttribute($0, kAXValueAttribute) },
                               secure: subrole == kAXSecureTextFieldSubrole)
    }

    var context: String {
        guard !secure, let originalValue else { return "" }
        let value = originalValue as NSString
        let cursor = min(selection?.location ?? value.length, value.length)
        let start = max(0, cursor - 350)
        return value.substring(with: NSRange(location: start, length: min(700, value.length - start)))
    }

    func isUnchanged() -> Bool {
        guard !secure, !app.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return false }
        if let element {
            guard let focused = Self.focusedElement(), CFEqual(element, focused) else { return false }
            if let selection, Self.selectedRange(element) != selection { return false }
            if let originalValue, Self.stringAttribute(element, kAXValueAttribute) != originalValue { return false }
        }
        return true
    }

    /// Voice edits replace a selection, so they only paste into the exact field and selection they captured.
    func replaceSelection(with text: String) throws {
        guard isUnchanged() else { Self.copy(text); throw AppFailure("The selection changed. The edited text is on your clipboard.") }
        try Self.paste(text)
    }

    /// Puts the text on the clipboard and pastes it wherever the cursor is now. The clipboard keeps the text,
    /// so it can be pasted again. Never synthesizes Return.
    static func paste(_ text: String) throws {
        copy(text)
        guard AXIsProcessTrusted() else { throw AppFailure("Copied. Enable Accessibility to paste automatically.") }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if let element = focusedElement(), stringAttribute(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole {
            throw AppFailure("Copied. Not pasted into a password field.")
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw AppFailure("Copied. Could not paste into \(app.localizedName ?? "the app").")
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func selectedRange(_ element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}
