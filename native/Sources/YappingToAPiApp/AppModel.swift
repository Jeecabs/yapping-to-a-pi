import AppKit
import AVFoundation
@preconcurrency import ApplicationServices
import FoundationModels
import Observation
import ServiceManagement
import Speech
import YappingCore

enum AppPage: String, CaseIterable, Identifiable {
    case home = "Home", history = "History", dictionary = "Dictionary", snippets = "Snippets"
    case style = "Style", rewrite = "Rewrite", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: "house"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        case .snippets: "text.badge.plus"
        case .style: "slider.horizontal.3"
        case .rewrite: "wand.and.stars"
        case .settings: "gearshape"
        }
    }
}

enum RecordingPhase: Equatable {
    case idle, preparing, listening, finishing, writing
    var title: String {
        switch self {
        case .idle: "Ready when you are"
        case .preparing: "Getting ready"
        case .listening: "Listening"
        case .finishing: "Finishing your thought"
        case .writing: "Refining on your Mac"
        }
    }
}

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    var data: DesktopData { didSet { persist(); configurationChanged?() } }
    var page: AppPage = .home
    var phase: RecordingPhase = .idle
    var preparationLabel = "Starting"
    var preview = ""
    var latestText = ""
    var status = ""
    var storageError: String?
    var microphoneGranted = false
    var accessibilityGranted = false
    var shortcutReady = false
    var modelInstalled = false
    var writerStatus: String?
    var locales: [String] = []
    var inputDevice = "System default"
    var audioInputs: [AudioInput] = []
    var waveform = WaveformHistory()
    var isCommand = false
    var startedAt: Date?
    var launchAtLogin = false
    var scratchpad = ""
    var selectedTransform: UUID?
    var transforming = false
    var transformOriginal: String?
    var transformResult = ""
    var setupBusy = false
    var previewingBar = false
    /// A short line the floating bar shows after a dictation that didn't simply paste.
    var barNotice: String?
    /// True while Settings is listening for a new shortcut; the global shortcut stands down.
    var recordingShortcut = false
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var accessibilityWatch: Task<Void, Never>?
    @ObservationIgnored var configurationChanged: (() -> Void)?
    @ObservationIgnored var presentationChanged: (() -> Void)?
    @ObservationIgnored var recordingEnded: (() -> Void)?
    @ObservationIgnored private let store: DesktopStore
    @ObservationIgnored private var readOnly = false
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var session: HelperSession?
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var transformTask: Task<Void, Never>?
    @ObservationIgnored private var destination: TextDestination?
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var didListen = false
    @ObservationIgnored private var stoppedDuringPreparation = false
    @ObservationIgnored private var recordingSettings = DesktopSettings()
    @ObservationIgnored private var recordingStyle: WritingStyle = .natural
    @ObservationIgnored private var recordingVocabulary: [VocabularyEntry] = []
    @ObservationIgnored private var recordingSnippets: [Snippet] = []

    var isBusy: Bool { phase != .idle }
    var totalWords: Int { data.history.reduce(0) { $0 + $1.wordCount } }
    var estimatedMinutesSaved: Int {
        max(0, Int(Double(totalWords) / 40 - data.history.reduce(0) { $0 + $1.duration } / 60))
    }
    var wordsPerMinute: Int {
        let duration = data.history.reduce(0) { $0 + $1.duration }
        return duration > 0 ? Int(Double(totalWords) / duration * 60) : 0
    }

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Yapping to a Pi", isDirectory: true)
        store = DesktopStore(url: directory.appendingPathComponent("desktop.json"))
        do { data = try store.load() }
        catch { data = DesktopData(); readOnly = true; storageError = "Could not read saved data: \(error.localizedDescription) Your file has been preserved." }
        data.pruneHistory()
        loaded = true
    }

    func refreshReadiness() async {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        writerStatus = LocalWriter.unavailableReason
        inputDevice = AVCaptureDevice.default(for: .audio)?.localizedName ?? "No microphone"
        audioInputs = AudioInputs.available()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        let supported = await SpeechTranscriber.supportedLocales
        locales = supported.map { $0.identifier(.bcp47) }.sorted {
            Locale.current.localizedString(forIdentifier: $0) ?? $0 < Locale.current.localizedString(forIdentifier: $1) ?? $1
        }
        let selected = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: data.settings.locale))
        let installed = await SpeechTranscriber.installedLocales
        modelInstalled = selected.map { locale in installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) } } ?? false
        configurationChanged?()
    }

    func requestMicrophone() {
        Task {
            microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
            if !microphoneGranted { openPrivacy("Microphone") }
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Accessibility")
        watchAccessibility()
    }

    /// macOS sends no notification when Accessibility is granted. Poll until it is, then install the
    /// shortcut, so the hotkey works without relaunching.
    func watchAccessibility() {
        guard accessibilityWatch == nil, !AXIsProcessTrusted() else { return }
        accessibilityWatch = Task { [weak self] in
            while !Task.isCancelled, !AXIsProcessTrusted() {
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self, !Task.isCancelled else { return }
            self.accessibilityWatch = nil
            self.accessibilityGranted = true
            self.configurationChanged?()
        }
    }

    func showBarNotice(_ notice: String) {
        barNotice = notice
        presentationChanged?()
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.barNotice = nil
            self?.presentationChanged?()
        }
    }

    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func installLanguage() {
        guard !setupBusy, !isBusy else { return }
        setupBusy = true
        status = "Preparing the on-device language model…"
        Task {
            defer { setupBusy = false }
            do {
                guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: data.settings.locale)) else {
                    throw AppFailure("Apple's speech model does not support this language.")
                }
                let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
                await refreshReadiness()
                status = "Language ready. Speech recognition runs on this Mac."
            } catch { status = error.localizedDescription }
        }
    }

    func start(command: Bool = false) {
        guard !isBusy else { return }
        let target = TextDestination.capture()
        guard target?.secure != true else { showStatus("Dictation is unavailable in password fields."); return }
        if command {
            guard let target, !target.selectedText.isEmpty else { showStatus("Select text in another app, then hold \(data.settings.shortcuts.editSelection.title) to edit it."); return }
            if let reason = LocalWriter.unavailableReason { showStatus(reason); return }
        }
        sessionID = UUID()
        let id = sessionID
        destination = target
        isCommand = command
        recordingSettings = data.settings
        recordingStyle = data.appStyles.first { $0.bundleID == target?.bundleID }?.style ?? data.settings.style
        recordingVocabulary = data.vocabulary
        recordingSnippets = data.snippets
        preview = ""; status = ""; didListen = false; stoppedDuringPreparation = false
        noticeTask?.cancel(); barNotice = nil
        startedAt = nil
        phase = .preparing
        preparationLabel = "Starting"
        watchPreparation(id: id, seconds: 25)
        presentationChanged?()
        do {
            let session = try HelperSession(locale: recordingSettings.locale, inputUID: recordingSettings.inputUID)
            self.session = session
            sessionTask = Task { [weak self] in
                for await event in session.events {
                    guard let self, self.sessionID == id, !Task.isCancelled else { return }
                    switch event {
                    case .message(let message): await self.receive(message, id: id)
                    case .failed(let message): self.fail(message)
                    case .ended(let code):
                        if self.isBusy && self.phase != .writing {
                            self.fail(code == 0 ? "Recording ended without a final transcript." : "The speech helper stopped (\(code)).")
                        }
                    }
                }
            }
        } catch { fail(error.localizedDescription) }
    }

    func toggle() { isBusy ? stop() : start() }

    func stop() {
        guard phase == .preparing || phase == .listening else { return }
        stoppedDuringPreparation = !didListen
        phase = .finishing
        session?.stop()
        let id = sessionID
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.sessionID == id, self.phase == .finishing else { return }
            self.fail("Finishing took too long. The last preview is available to copy; check it before using it.")
        }
        presentationChanged?()
    }

    func cancel() {
        guard isBusy else { return }
        cleanup()
        preview = ""; status = "Dictation cancelled."
        presentationChanged?()
    }

    private func receive(_ message: HelperMessage, id: UUID) async {
        switch message {
        case .level(let value): waveform.append(value)
        case .state(let state, let device):
            if let device { inputDevice = device }
            switch state {
            case "listening" where phase == .preparing:
                timeoutTask?.cancel()
                didListen = true; startedAt = Date(); phase = .listening
                status = ""
                microphoneGranted = true
                if data.settings.soundEffects { NSSound(named: "Tink")?.play() }
            case "installing-model" where phase == .preparing:
                preparationLabel = "Model…"
                status = "Downloading Apple's speech model…"
                watchPreparation(id: id, seconds: 600)
            case "requesting-permission" where phase == .preparing:
                preparationLabel = "Allow mic"
                status = "Allow microphone access to start dictating."
                watchPreparation(id: id, seconds: 120)
            case "finalizing": if phase != .writing { phase = .finishing }
            default: break
            }
            presentationChanged?()
        case .partial(let text): preview = text
        case .final(let raw):
            timeoutTask?.cancel()
            guard !stoppedDuringPreparation, didListen else { cleanup(); presentationChanged?(); return }
            await finish(raw, id: id)
        case .failure(let message): fail(message.replacingOccurrences(of: "the terminal app that runs Pi; enable that app", with: "\(Brand.name); enable the app"))
        }
    }

    private func finish(_ raw: String, id: UUID) async {
        let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else {
            cleanup(); showStatus("No speech detected. Try moving closer to your microphone."); showBarNotice("didn’t catch that"); return
        }
        let duration = Date().timeIntervalSince(startedAt ?? Date())
        let target = destination
        let command = isCommand
        var text = TextRules.applyVocabulary(original, entries: recordingVocabulary)
        var note = ""
        do {
            if command {
                phase = .writing; presentationChanged?()
                text = try await LocalWriter.edit(target?.selectedText ?? "", instruction: text, locale: recordingSettings.locale)
            } else if (recordingSettings.polish && recordingStyle != .verbatim) || !recordingSettings.outputLanguage.isEmpty {
                phase = .writing; presentationChanged?()
                do {
                    text = try await LocalWriter.polish(text, style: recordingStyle, locale: recordingSettings.locale,
                                                      app: target?.name ?? Brand.name, context: recordingSettings.useContext ? target?.context ?? "" : "",
                                                      outputLanguage: recordingSettings.outputLanguage)
                } catch {
                    // Keep the complete transcript when the optional writing model is unavailable.
                    note = "Original transcript kept. \(error.localizedDescription)"
                }
            }
            guard sessionID == id, !Task.isCancelled else { return }
            if !command {
                text = TextRules.applyVocabulary(text, entries: recordingVocabulary)
                text = TextRules.expandSnippets(text, snippets: recordingSnippets)
            }
            latestText = text
            if data.settings.saveHistory {
                data.history.insert(HistoryEntry(original: command ? target?.selectedText ?? "" : original, text: text,
                                                 appName: target?.name ?? Brand.name, duration: duration, isCommand: command), at: 0)
                data.pruneHistory()
            }
            do {
                if command, let target { try target.replaceSelection(with: text) } else { try TextDestination.paste(text) }
            } catch {
                note = error.localizedDescription
                showBarNotice("copied · press ⌘V to paste")
            }
            guard sessionID == id else { return }
            cleanup()
            preview = ""
            status = note
            if data.settings.soundEffects { NSSound(named: "Pop")?.play() }
            presentationChanged?()
        } catch {
            guard sessionID == id else { return }
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        if !preview.isEmpty { latestText = preview }
        cleanup()
        showStatus(message)
        showBarNotice("something went wrong · open the app")
    }

    private func watchPreparation(id: UUID, seconds: Int) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.sessionID == id, self.phase == .preparing else { return }
            self.fail("Dictation could not start. Check microphone permission and language readiness in Settings, then try again.")
        }
    }

    private func cleanup() {
        sessionID = UUID()
        timeoutTask?.cancel(); timeoutTask = nil
        session?.terminate(); session = nil
        sessionTask?.cancel(); sessionTask = nil
        phase = .idle
        waveform = WaveformHistory()
        startedAt = nil
        destination = nil
        recordingEnded?()
    }

    func showStatus(_ message: String) { status = message; presentationChanged?() }
    func previewBar() { previewingBar = true; presentationChanged?() }
    func endBarPreview() { previewingBar = false; configurationChanged?() }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); status = "Copied." }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { SMAppService.openSystemSettingsLoginItems() }
        } catch { status = "Could not change login setting: \(error.localizedDescription)" }
    }

    func runTransform() {
        guard !transforming, let transform = data.transforms.first(where: { $0.id == selectedTransform }) ?? data.transforms.first else { return }
        let source = scratchpad.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        transforming = true
        transformTask = Task {
            defer { transforming = false }
            do {
                let result = try await LocalWriter.edit(source, instruction: transform.instruction, locale: data.settings.locale)
                try Task.checkCancellation()
                transformOriginal = source; transformResult = result
            } catch is CancellationError { }
            catch { status = error.localizedDescription }
        }
    }

    func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "computer, listen history.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = data.history.map { "## \($0.date.formatted()) · \($0.appName)\n\n\($0.text)" }.joined(separator: "\n\n")
        do { try text.write(to: url, atomically: true, encoding: .utf8); status = "History exported." }
        catch { status = error.localizedDescription }
    }

    func openDataFolder() { NSWorkspace.shared.open(store.url.deletingLastPathComponent()) }

    func shutdown() { cleanup(); transformTask?.cancel(); persist() }

    private func persist() {
        guard loaded, !readOnly else { return }
        do { try store.save(data); storageError = nil }
        catch { storageError = "Could not save changes: \(error.localizedDescription)" }
    }
}
