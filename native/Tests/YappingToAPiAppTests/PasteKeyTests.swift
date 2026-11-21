import Carbon
import Testing
@testable import YappingToAPiApp

@MainActor
@Suite("Paste key without posting any event")
struct PasteKeyTests {
    @Test("⌘V is sent on the key that types v, wherever the layout puts it")
    func pasteKeyFollowsTheLayout() throws {
        // Every Mac ships these layouts, enabled or not. Dvorak moves v; the last two only type it while ⌘ is down.
        let expected: [(String, CGKeyCode)] = [("US", 9), ("Dvorak", 47), ("DVORAK-QWERTYCMD", 9), ("Russian", 9)]
        let filter = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary
        let layouts = try #require(TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])
        for (name, key) in expected {
            let layout = try #require(layouts.first { layout in
                guard let property = TISGetInputSourceProperty(layout, kTISPropertyInputSourceID) else { return false }
                return Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String == "com.apple.keylayout.\(name)"
            }, "\(name) layout is missing")
            #expect(TextDestination.keyCode(typing: "v", on: layout) == key, "\(name)")
        }
    }
}
