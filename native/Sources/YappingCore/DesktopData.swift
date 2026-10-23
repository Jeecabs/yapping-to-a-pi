import Foundation

public enum WritingStyle: String, Codable, CaseIterable, Sendable {
    case natural, casual, professional, concise, verbatim

    public var title: String { rawValue.capitalized }
    public var instruction: String {
        switch self {
        case .natural: "Keep the speaker's voice. Use normal capitalization and punctuation."
        case .casual: "Use a relaxed, conversational tone. Keep it brief without adding slang."
        case .professional: "Use clear, professional sentences. Preserve meaning and every detail."
        case .concise: "Remove unnecessary words without losing information."
        case .verbatim: "Preserve the original transcript exactly."
        }
    }
}

public struct VocabularyEntry: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var spoken: String
    public var written: String
    public init(spoken: String, written: String) { self.spoken = spoken; self.written = written }
}

public struct Snippet: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var trigger: String
    public var text: String
    public init(trigger: String, text: String) { self.trigger = trigger; self.text = text }
}

public struct AppStyle: Codable, Identifiable, Equatable, Sendable {
    public var id: String { bundleID }
    public var bundleID: String
    public var name: String
    public var style: WritingStyle
    public init(bundleID: String, name: String, style: WritingStyle) {
        self.bundleID = bundleID; self.name = name; self.style = style
    }
}

public struct TextTransform: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var instruction: String
    public init(name: String, instruction: String) { self.name = name; self.instruction = instruction }

    fileprivate var isLegacyPreset: Bool {
        switch (name, instruction) {
        case ("Polish", "Improve clarity and grammar while preserving the meaning and tone."),
             ("Prompt engineer", "Rewrite as a clear, specific prompt for an AI assistant. Preserve the user's intent, constraints, and all provided details. Do not invent requirements."):
            true
        default: false
        }
    }
}

public enum RewritePreset: String, CaseIterable, Identifiable, Sendable {
    case cleanUp, shorten, list, prompt
    public var id: Self { self }
    public var title: String {
        switch self {
        case .cleanUp: "clean up"
        case .shorten: "shorten"
        case .list: "make a list"
        case .prompt: "write a prompt"
        }
    }
    public var instruction: String {
        switch self {
        case .cleanUp:
            "Fix spelling, grammar and punctuation. Remove fillers. Resolve self-corrections: 'Friday, actually Thursday' becomes 'Thursday'. Keep the author's voice, language and politeness. Preserve facts, names, numbers and requests. Add no new details."
        case .shorten:
            "Make this as brief as possible. Merge repeated points so each requirement appears only once. Keep the author's tone and language. Preserve meaning, requests, names, numbers and deadlines. Add no new facts."
        case .list:
            "Turn the text into a concise bullet list. Combine repeated points. Keep all names, numbers, deadlines and requested actions. Use the original language. Do not invent tasks, facts or headings."
        case .prompt:
            "Turn these notes into a clear prompt for an AI assistant. State the task first, then the provided context, constraints and desired output when present. Preserve every requirement. Do not invent details, add boilerplate roles or answer the prompt. Use the original language."
        }
    }
}

public struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var original: String
    public var text: String
    public var appName: String
    public var duration: TimeInterval
    public var isCommand: Bool
    public var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
    public init(original: String, text: String, appName: String, duration: TimeInterval, isCommand: Bool) {
        self.original = original; self.text = text; self.appName = appName
        self.duration = duration; self.isCommand = isCommand
    }
}

public enum HotkeyChoice: String, Codable, CaseIterable, Sendable {
    case function, rightOption
    public var title: String { self == .function ? "Fn / Globe" : "Right Option" }
    public var symbol: String { self == .function ? "fn" : "⌥" }
}

public struct DesktopSettings: Codable, Equatable, Sendable {
    public var locale = "en-AU"
    public var inputUID = ""
    /// Legacy single hold-key choice. Still decoded so older settings files load; seeds `shortcuts`.
    public var hotkey: HotkeyChoice = .function
    public var shortcutBindings: ShortcutBindings?
    public var shortcuts: ShortcutBindings {
        get { shortcutBindings ?? ShortcutBindings(hotkey: hotkey) }
        set { shortcutBindings = newValue }
    }
    public var style: WritingStyle = .natural
    /// Apple Intelligence cleanup is opt-in: by default you get exactly what you said.
    public var polish = false
    public var useContext = false
    public var saveHistory = true
    public var retentionDays = 30
    public var soundEffects = false
    public var showDockIcon = true
    public var outputLanguage = ""
    public var onboardingComplete = false
    public var appearance: AppearancePreferences?
    public var appearanceOptions: AppearancePreferences {
        get { appearance ?? AppearancePreferences() }
        set { appearance = newValue }
    }
    public init() {}
}

public struct DesktopData: Codable, Equatable, Sendable {
    public var version = 1
    public var settings = DesktopSettings()
    public var vocabulary: [VocabularyEntry] = []
    public var snippets: [Snippet] = []
    public var appStyles: [AppStyle] = []
    public var transforms: [TextTransform] = []
    public var history: [HistoryEntry] = []
    public init() {}

    public mutating func pruneHistory(now: Date = Date()) {
        guard settings.saveHistory else { history = []; return }
        if settings.retentionDays > 0 {
            let cutoff = now.addingTimeInterval(-Double(settings.retentionDays) * 86_400)
            history.removeAll { $0.date < cutoff }
        }
        if history.count > 2_000 { history = Array(history.prefix(2_000)) }
    }
}

/// One local, atomic document. A read failure never silently overwrites existing history.
public struct DesktopStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> DesktopData {
        guard FileManager.default.fileExists(atPath: url.path) else { return DesktopData() }
        var data = try JSONDecoder().decode(DesktopData.self, from: Data(contentsOf: url))
        guard data.version == 1 else { throw StoreFailure.newerVersion }
        // Built-ins now live outside saved custom rewrites. Preserve any edited legacy preset.
        data.transforms.removeAll { $0.isLegacyPreset }
        return data
    }

    public func save(_ data: DesktopData) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(data).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public enum StoreFailure: LocalizedError {
        case newerVersion
        public var errorDescription: String? { "This data was saved by a newer version of Yapping. Update the app before making changes." }
    }
}
