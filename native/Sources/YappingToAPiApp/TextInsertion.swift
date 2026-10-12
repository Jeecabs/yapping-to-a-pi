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
    func replaceSelection(with text: String) async throws {
        guard isUnchanged() else { Self.copy(text); throw AppFailure("The selection changed. The edited text is on your clipboard.") }
        try await Self.paste(text)
    }

    /// Puts the text on the clipboard and pastes it wherever the cursor is now, returning the app's name. Throws
    /// when the text only reached the clipboard. The clipboard keeps the text, so it can be pasted again.
    /// Never synthesizes Return.
    @discardableResult
    static func paste(_ text: String) async throws -> String {
        copy(text)
        guard AXIsProcessTrusted() else { throw AppFailure("Copied. Enable Accessibility to paste automatically.") }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw AppFailure("Copied. \(Brand.name) was in front, so there was nowhere to paste. Click where the text should go and press ⌘V.")
        }
        let name = app.localizedName ?? "the app"
        let element = focusedElement()
        if let element, stringAttribute(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole {
            throw AppFailure("Copied. Not pasted into a password field.")
        }
        let before = element.flatMap(editState)
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw AppFailure("Copied. Could not paste into \(app.localizedName ?? "the app").")
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        // Where the field reports its length, confirm the paste changed it rather than assuming it did.
        // Terminals and some web views don't report it; those are taken on trust.
        guard let element, let before else { return name }
        for wait in [Duration.milliseconds(150), .milliseconds(450)] {
            try? await Task.sleep(for: wait)
            if editState(element) != before { return name }
        }
        throw AppFailure("Copied. \(name) didn't take the paste. Click where the text should go and press ⌘V.")
    }

    /// The length and selection of a text field, enough to tell whether a paste landed.
    private struct EditState: Equatable {
        let length: Int
        let selection: NSRange?
    }

    private static func editState(_ element: AXUIElement) -> EditState? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &value) == .success,
              let length = value as? Int else { return nil }
        return EditState(length: length, selection: selectedRange(element))
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
