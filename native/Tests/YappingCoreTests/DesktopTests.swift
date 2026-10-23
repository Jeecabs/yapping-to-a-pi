import Foundation
import CoreGraphics
import Testing
@testable import YappingCore

@Suite("Desktop dictation without microphone access")
struct DesktopTests {
    @Test("Hold, hands-free and stop do not restart a recording")
    func gestures() {
        var gesture = ShortcutGesture()
        #expect(gesture.press(at: 1) == nil)
        #expect(gesture.hold() == .start)
        #expect(gesture.hold() == nil)
        #expect(gesture.release(at: 2) == .stop)
        #expect(gesture.press(at: 3) == nil)
        #expect(gesture.release(at: 3.1) == nil)
        #expect(gesture.press(at: 3.2) == .start)
        #expect(gesture.release(at: 3.3) == nil)
        #expect(gesture.handsFree)
        #expect(gesture.press(at: 4) == .stop)
        #expect(gesture.hold() == nil)
        #expect(gesture.release(at: 4.5) == nil)
        #expect(!gesture.active)
        #expect(gesture.toggle() == .start)
        #expect(gesture.toggle() == .stop)
        gesture.reset()
        #expect(gesture.release(at: 5) == nil)
    }

    @Test("Dictionary matching is bounded, longest first, and never cascades")
    func vocabulary() {
        let entries = [VocabularyEntry(spoken: "pie", written: "Pi"),
                       VocabularyEntry(spoken: "pie tools", written: "pi-tools"),
                       VocabularyEntry(spoken: "pi-tools", written: "WRONG")]
        #expect(TextRules.applyVocabulary("PIE TOOLS uses pie, not pies or 🥧pie1.", entries: entries)
                == "pi-tools uses Pi, not pies or 🥧pie1.")
        #expect(TextRules.replace("c++ and c", entries: [("c++", "C++")]) == "C++ and c")
    }

    @Test("Snippet punctuation, literal replacement characters and Unicode survive")
    func snippetsAndChunks() {
        let snippet = Snippet(trigger: "my address", text: "42 Pi Street\nSydney $1")
        #expect(TextRules.expandSnippets("My address.", snippets: [snippet]) == snippet.text)
        #expect(TextRules.expandSnippets("Send it to my address please.", snippets: [snippet]) == "Send it to 42 Pi Street\nSydney $1 please.")
        let text = String(repeating: "A family 👨‍👩‍👧‍👦 says héllo.\n", count: 100)
        let chunks = TextRules.chunks(text, limit: 80)
        #expect(chunks.joined() == text)
        #expect(chunks.allSatisfy { $0.count <= 80 })
        #expect(TextRules.chunks(String(repeating: "x", count: 201), limit: 100).map(\.count) == [100, 100, 1])
    }

    @Test("NDJSON accepts arbitrary UTF-8 boundaries and rejects malformed wire data")
    func protocolBoundary() throws {
        let bytes = Data("{\"type\":\"partial\",\"text\":\"héllo 👋\"}\n{\"type\":\"final\",\"text\":\"Done.\"}\n".utf8)
        var framer = MessageFramer()
        var messages: [HelperMessage] = []
        for byte in bytes { messages += try framer.append(Data([byte])) }
        try framer.finish()
        #expect(messages == [.partial("héllo 👋"), .final("Done.")])
        for invalid in ["{\"type\":\"partial\",\"text\":42}", "{\"type\":\"state\",\"state\":\"wrong\",\"locale\":\"en\"}", "{\"type\":\"final\"}", "{\"type\":\"unknown\"}"] {
            #expect(throws: (any Error).self) { try HelperMessage.decode(Data(invalid.utf8)) }
        }
        var incomplete = MessageFramer()
        _ = try incomplete.append(Data("{\"type\":".utf8))
        #expect(throws: (any Error).self) { try incomplete.finish() }
        var large = MessageFramer()
        #expect(throws: (any Error).self) { try large.append(Data(repeating: 65, count: 1_048_577)) }
    }

    @Test("Shortcut defaults keep fn, fn space, ⌃ fn and esc, and the old right ⌥ choice migrates")
    func shortcutDefaults() throws {
        let defaults = ShortcutBindings.defaults
        #expect(defaults.talk.title == "fn")
        #expect(defaults.handsFree.title == "fn space")
        #expect(defaults.editSelection.title == "⌃ fn")
        #expect(defaults.cancel.title == "esc")
        var settings = DesktopSettings()
        settings.hotkey = .rightOption
        #expect(settings.shortcuts.talk.keyCode == 61)
        #expect(settings.shortcuts.handsFree.modifiers == .option)
        // Settings saved before shortcuts existed still decode.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DesktopSettings())) as! [String: Any]
        legacy.removeValue(forKey: "shortcutBindings")
        let decoded = try JSONDecoder().decode(DesktopSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.shortcuts == .defaults)
    }

    @Test("Hold keys pick edit only when its extra modifier is held")
    func holdAction() {
        let bindings = ShortcutBindings.defaults
        #expect(bindings.holdAction(keyCode: 63, modifiers: [.function]) == .talk)
        #expect(bindings.holdAction(keyCode: 63, modifiers: [.function, .control]) == .editSelection)
        #expect(bindings.holdAction(keyCode: 49, modifiers: [.function]) == nil)
        // Another modifier with the hold key is a different shortcut, such as ⌘ fn.
        #expect(bindings.holdAction(keyCode: 63, modifiers: [.function, .command]) == nil)
        #expect(bindings.holdAction(keyCode: 63, modifiers: [.function, .control, .shift]) == nil)
        #expect(bindings.handsFree.matchesPress(keyCode: 49, modifiers: [.function]))
        #expect(!bindings.handsFree.matchesPress(keyCode: 49, modifiers: [.function, .shift]))
        // F-keys always report fn; that must not stop an F5 binding from matching.
        let f5 = KeyBinding(keyCode: 96, keyLabel: "F5")
        #expect(f5.matchesPress(keyCode: 96, modifiers: [.function]))
    }

    @Test("Shortcut validation rejects plain letters, duplicates, macOS shortcuts and modifier-only cancel")
    func shortcutValidation() {
        let bindings = ShortcutBindings.defaults
        #expect(bindings.problem(with: KeyBinding(keyCode: 2, keyLabel: "d"), for: .talk) != nil)
        #expect(bindings.problem(with: KeyBinding(keyCode: 2, modifiers: [.control, .option], keyLabel: "d"), for: .talk) == nil)
        #expect(bindings.problem(with: KeyBinding(keyCode: 96, keyLabel: "F5"), for: .talk) == nil)
        #expect(bindings.problem(with: bindings.handsFree, for: .talk) != nil)
        #expect(bindings.problem(with: KeyBinding(keyCode: 49, modifiers: .command, keyLabel: "space"), for: .handsFree) != nil)
        #expect(bindings.problem(with: KeyBinding(keyCode: 61, keyLabel: "right ⌥"), for: .cancel) != nil)
        #expect(bindings.problem(with: KeyBinding(keyCode: 61, keyLabel: "right ⌥"), for: .talk) == nil)
        #expect(bindings.problem(with: KeyBinding(keyCode: 56, keyLabel: "left ⇧"), for: .talk) != nil)
        #expect(bindings.problem(with: KeyBinding(keyCode: 55, keyLabel: "left ⌘"), for: .talk) != nil)
        let inputSource = KeyBinding(keyCode: 49, modifiers: .control, keyLabel: "space")
        #expect(bindings.problem(with: inputSource, for: .handsFree, system: [inputSource]) != nil)
        #expect(bindings.problem(with: inputSource, for: .handsFree) == nil)
        #expect(bindings.usesFunctionKey)
        #expect(!ShortcutBindings(hotkey: .rightOption).usesFunctionKey)
    }

    @Test("Apple Intelligence cleanup is off until the user opts in")
    func cleanupIsOptIn() {
        #expect(DesktopSettings().polish == false)
    }

    @Test("Local storage round trips and refuses to overwrite unreadable data")
    func persistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DesktopStore(url: directory.appendingPathComponent("desktop.json"))
        #expect(try store.load().settings == DesktopSettings())
        var data = DesktopData()
        data.vocabulary = [.init(spoken: "pie", written: "Pi")]
        data.settings.hotkey = .rightOption
        try store.save(data)
        #expect(try store.load() == data)
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: store.url) == corrupt)
    }

    @Test("Legacy rewrite defaults migrate without losing custom or edited instructions")
    func rewriteMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DesktopStore(url: directory.appendingPathComponent("desktop.json"))
        var data = DesktopData()
        let edited = TextTransform(name: "Polish", instruction: "Keep my spelling and make it warmer.")
        let custom = TextTransform(name: "meeting notes", instruction: "Make a checklist.")
        data.transforms = [
            .init(name: "Polish", instruction: "Improve clarity and grammar while preserving the meaning and tone."),
            .init(name: "Prompt engineer", instruction: "Rewrite as a clear, specific prompt for an AI assistant. Preserve the user's intent, constraints, and all provided details. Do not invent requirements."),
            edited, custom
        ]
        try store.save(data)
        let loaded = try store.load()
        #expect(loaded.transforms == [edited, custom])
        #expect(loaded.settings == data.settings)
        #expect(Set(RewritePreset.allCases.map(\.title)).count == RewritePreset.allCases.count)
        try store.save(loaded)
        #expect(try store.load() == loaded)
    }

    @Test("Retention is based on age and never-store removes history")
    func retention() {
        var data = DesktopData()
        var old = HistoryEntry(original: "Old", text: "Old", appName: "Test", duration: 1, isCommand: false)
        old.date = Date(timeIntervalSince1970: 0)
        let recent = HistoryEntry(original: "New", text: "New", appName: "Test", duration: 1, isCommand: false)
        data.history = [recent, old]
        data.pruneHistory()
        #expect(data.history == [recent])
        data.settings.saveHistory = false
        data.pruneHistory()
        #expect(data.history.isEmpty)
    }

    @Test("The bar starts at the screen edge and remembered positions stay reachable")
    func overlayPlacement() {
        let screen = CGRect(x: -1_440, y: 0, width: 1_440, height: 900)
        let visible = CGRect(x: -1_440, y: 80, width: 1_440, height: 795)
        let row = CGSize(width: 90, height: 32)
        let canvas = CGSize(width: 264, height: 142)
        var preferences = AppearancePreferences()
        func place() -> OverlayPlacement {
            OverlayLayout.placement(screen: screen, visible: visible, row: row, canvas: canvas, inset: 14, preferences: preferences)
        }
        func pill(_ placement: OverlayPlacement) -> CGPoint {
            OverlayLayout.rowCenter(in: placement.frame, row: row, inset: 14, expandsUp: placement.expandsUp)
        }
        let initial = place()
        #expect(initial.expandsUp)
        #expect(pill(initial).y - row.height / 2 == 6)
        #expect(initial.frame.midX == screen.midX)
        preferences.edge = .dock
        #expect(pill(place()).y - row.height / 2 == 86)
        preferences.position = BarPosition(displayID: 1, x: 2, y: -1)
        let clamped = pill(place())
        #expect(clamped.x + row.width / 2 <= screen.maxX)
        #expect(clamped.y - row.height / 2 == 2)
    }

    @Test("Near the top of the screen the bar opens downward and remembers the pill, not the panel")
    func overlayOpensDown() {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 875)
        let row = CGSize(width: 90, height: 32)
        var preferences = AppearancePreferences()
        preferences.position = BarPosition(displayID: 1, x: 0.5, y: 0.95)
        let placement = OverlayLayout.placement(screen: screen, visible: visible, row: row,
                                                canvas: CGSize(width: 264, height: 142), inset: 14, preferences: preferences)
        #expect(!placement.expandsUp)
        let center = OverlayLayout.rowCenter(in: placement.frame, row: row, inset: 14, expandsUp: false)
        #expect(abs(center.y - 855) <= 0.5)
    }

    @Test("Hover hints follow rebound shortcuts and the compact bar shows at most two")
    func barHints() {
        var shortcuts = ShortcutBindings.defaults
        shortcuts.talk = KeyBinding(keyCode: 61, keyLabel: "right ⌥")
        let ready = BarHint.hints(for: .ready, shortcuts: shortcuts)
        #expect(ready.first?.keys == "right ⌥")
        for stage in [BarHint.Stage.ready, .listening, .working, .needsAccess] {
            #expect(BarHint.hints(for: stage, shortcuts: shortcuts).count(where: \.compact) <= 2)
        }
        #expect(BarHint.hints(for: .listening, shortcuts: shortcuts).contains { $0.keys == "esc" })
    }

    @Test("Older settings without a hover choice open fully")
    func hoverDefault() throws {
        let preferences = try JSONDecoder().decode(AppearancePreferences.self, from: Data(#"{"theme":"system","barScale":1,"bottomSpacing":6,"edge":"screen","opacity":0.96}"#.utf8))
        #expect(preferences.hover == .full)
    }
}
