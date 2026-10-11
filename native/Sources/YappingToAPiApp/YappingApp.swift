import AppKit
import SwiftUI
import ApplicationServices
import AVFoundation
import FoundationModels
import YappingCore

@main
struct YappingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        if CommandLine.arguments.contains("--diagnose") {
            let report: [String: Any] = [
                "app": Brand.name, "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "microphone": AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                "accessibility": AXIsProcessTrusted(),
                "writingModel": String(describing: SystemLanguageModel.default.availability),
                "helperBundled": Bundle.main.url(forResource: "YappingToAPiHelper", withExtension: "app") != nil,
                "iconBundled": Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
            }
            exit(0)
        }
    }

    var body: some Scene {
        Window(Brand.name, id: "main") { MainView(model: .shared) }
            .defaultSize(width: 1080, height: 800)
            .windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("About \(Brand.name)") {
                        NSApplication.shared.orderFrontStandardAboutPanel(options: [
                            .applicationName: Brand.name,
                            .credits: NSAttributedString(string: "On-device dictation, wherever you write.\nBuilt for macOS and Pi."),
                            .applicationIcon: NSApplication.shared.applicationIconImage as Any
                        ])
                    }
                }
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { AppModel.shared.page = .settings; delegate.openHub() }.keyboardShortcut(",")
                }
                CommandMenu("Dictation") {
                    Button("Start or finish dictation") { AppModel.shared.toggle() }.keyboardShortcut("d", modifiers: [.command, .shift])
                    Button("Cancel dictation") { AppModel.shared.cancel() }.disabled(!AppModel.shared.isBusy)
                    Divider()
                    Button("Show history") { AppModel.shared.page = .history; delegate.openHub() }
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel.shared
    private let shortcut = GlobalShortcut()
    private var statusItem: NSStatusItem?
    private var panel: DictationPanel?
    private var lastDockSetting: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOf: url)
        }
        shortcut.onStart = { [weak model] command in model?.start(command: command) }
        shortcut.onStop = { [weak model] in model?.stop() }
        shortcut.onCancel = { [weak model] in model?.cancel() }
        shortcut.isRecording = { [weak model] in model?.isBusy == true }
        shortcut.isSuspended = { [weak model] in model?.recordingShortcut == true }
        model.recordingEnded = { [weak shortcut] in shortcut?.reset() }
        model.configurationChanged = { [weak self] in self?.configure() }
        model.presentationChanged = { [weak self] in self?.presentStatus() }
        createStatusItem()
        configure()
        // SwiftUI creates the window. Opening the app never requests permissions or starts audio,
        // unless it is explicitly launched with --request-accessibility (setup and recovery).
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--request-accessibility") { model.requestAccessibility() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await model.refreshReadiness() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openHub(); return true }
    func applicationWillTerminate(_ notification: Notification) { shortcut.uninstall(); model.shutdown() }

    @objc func openHub() {
        NSApp.windows.first { !($0 is NSPanel) && $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func toggle() { model.toggle() }
    @objc private func editSelection() { model.start(command: true) }
    @objc private func showSettings() { model.page = .settings; openHub() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func configure() {
        model.shortcutReady = shortcut.install(bindings: model.data.settings.shortcuts)
        if !model.shortcutReady { model.watchAccessibility() }
        if lastDockSetting != model.data.settings.showDockIcon {
            lastDockSetting = model.data.settings.showDockIcon
            NSApp.setActivationPolicy(model.data.settings.showDockIcon ? .regular : .accessory)
        }
        // The bar is the app's resting presence: always on screen, not only while recording.
        presentStatus()
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = Self.menuIcon()
        statusItem?.button?.toolTip = Brand.name
        let menu = NSMenu()
        let entries: [(String, Selector?)] = [
            (Brand.name, #selector(openHub)), ("", nil),
            ("Start / finish dictation", #selector(toggle)),
            ("Edit selected text by voice", #selector(editSelection)),
            ("", nil), ("Settings…", #selector(showSettings)), ("Quit \(Brand.name)", #selector(quit))
        ]
        for (title, action) in entries {
            if title.isEmpty { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        statusItem?.menu = menu
    }

    private func presentStatus() {
        if panel == nil {
            let panel = DictationPanel(contentRect: NSRect(origin: .zero, size: RecordingOverlay.size(for: model)),
                                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.contentView = NSHostingView(rootView: RecordingOverlay(model: model,
                openHub: { [weak self] in self?.openHub() }, onDragEnded: { [weak self] in self?.rememberBarPosition() }))
            self.panel = panel
        }
        guard let panel else { return }
        let size = RecordingOverlay.size(for: model)
        let preferences = model.data.settings.appearanceOptions
        let savedScreen = preferences.position.flatMap { position in NSScreen.screens.first { Self.displayID($0) == position.displayID } }
        let screen = savedScreen ?? (panel.isVisible ? panel.screen : nil)
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let screen {
            panel.setFrame(OverlayLayout.frame(screen: screen.frame, visible: screen.visibleFrame, size: size, preferences: preferences), display: true)
        }
        panel.orderFrontRegardless()
    }

    private static func displayID(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func rememberBarPosition() {
        guard let panel, let screen = panel.screen else { return }
        model.data.settings.appearanceOptions.position = BarPosition(displayID: Self.displayID(screen),
            x: (panel.frame.midX - screen.frame.minX) / screen.frame.width,
            y: (panel.frame.midY - screen.frame.minY) / screen.frame.height)
    }

    private static func menuIcon() -> NSImage {
        let icon = NSImage(size: NSSize(width: 19, height: 19), flipped: false) { _ in
            let mark = NSAttributedString(string: "c,", attributes: [
                .font: NSFont(name: Brand.displayFont, size: 21) ?? NSFont.systemFont(ofSize: 21, weight: .bold),
                .foregroundColor: NSColor.black,
                .kern: -1
            ])
            let size = mark.size()
            mark.draw(at: NSPoint(x: (19 - size.width) / 2, y: (19 - size.height) / 2 + 1))
            return true
        }
        icon.isTemplate = true
        return icon
    }
}

final class DictationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct RecordingOverlay: View {
    @Bindable var model: AppModel
    var openHub: () -> Void
    var onDragEnded: () -> Void = {}

    static func size(for model: AppModel) -> NSSize {
        let scale = model.data.settings.appearanceOptions.scale
        let width: CGFloat = switch true {
        case model.phase == .listening || model.previewingBar: 148
        case model.isBusy: 124
        case model.barNotice != nil: 236
        default: 84
        }
        return NSSize(width: width * scale, height: 32 * scale)
    }

    var body: some View {
        HStack(spacing: 8) {
            if model.isBusy {
                Button { model.cancel() } label: { Image(systemName: "xmark").frame(width: 22, height: 28) }
                    .help("Cancel dictation (\(model.data.settings.shortcuts.cancel.title))").accessibilityLabel("Cancel dictation")
                if model.phase == .listening {
                    InputMeter(samples: model.waveform.samples, sensitivity: model.data.settings.appearanceOptions.sensitivity).frame(maxWidth: .infinity)
                        .overlay { BarDragHandle(onEnd: onDragEnded) }.help("Drag to move")
                    Button { model.stop() } label: { Image(systemName: "stop.fill").frame(width: 22, height: 28) }
                        .help("Finish dictation").accessibilityLabel("Finish dictation")
                } else {
                    ProgressView().controlSize(.mini).tint(.white)
                    Text(model.phase == .preparing ? model.preparationLabel : "Finishing")
                        .font(.system(size: 10, weight: .medium)).frame(maxWidth: .infinity)
                        .overlay { BarDragHandle(onEnd: onDragEnded) }.help("Drag to move")
                }
            } else {
                Button { model.start() } label: { Image(systemName: "mic.fill").frame(width: 24, height: 28) }
                    .help("Start dictation").accessibilityLabel("Start dictation")
                if let notice = model.barNotice, !model.previewingBar {
                    Text(notice).font(.system(size: 11, weight: .medium)).lineLimit(1).foregroundStyle(Palette.signal)
                        .frame(maxWidth: .infinity).overlay { BarDragHandle(onEnd: onDragEnded) }.help(model.status)
                } else if !model.shortcutReady && !model.previewingBar {
                    // Without Accessibility the shortcut can't be heard and text can't be pasted. A quiet dot in the
                    // bar's usual slot says so without changing its shape; the tooltip and click explain the rest.
                    Button { model.requestAccessibility() } label: {
                        Circle().fill(Palette.signal).frame(width: 6, height: 6).frame(width: 10, height: 28)
                    }.help("Shortcut and paste need Accessibility. Click to allow.").accessibilityLabel("Allow Accessibility")
                } else if model.previewingBar {
                    InputMeter(samples: [0.08, 0.17, 0.35, 0.65, 0.88, 0.56, 0.24, 0.46, 0.73, 0.95, 0.63, 0.27, 0.1],
                               sensitivity: model.data.settings.appearanceOptions.sensitivity)
                        .frame(maxWidth: .infinity).overlay { BarDragHandle(onEnd: onDragEnded) }.help("Drag to move")
                } else {
                    Image(systemName: "ellipsis").font(.system(size: 8)).frame(width: 10, height: 28)
                        .overlay { BarDragHandle(onEnd: onDragEnded) }.help("Drag to move")
                }
                Button(action: openHub) { Image(systemName: model.status.isEmpty ? "arrow.up.right" : "text.bubble").frame(width: 24, height: 28) }
                    .help(model.status.isEmpty ? "Open \(Brand.name)" : model.status).accessibilityLabel("Open \(Brand.name)")
            }
        }
        .padding(.horizontal, 8)
        .frame(width: Self.size(for: model).width / model.data.settings.appearanceOptions.scale, height: 32)
        .background(Palette.overlay.opacity(model.data.settings.appearanceOptions.opacity), in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.14)) }
        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).buttonStyle(.plain).colorScheme(.dark)
        .scaleEffect(model.data.settings.appearanceOptions.scale)
        .frame(width: Self.size(for: model).width, height: Self.size(for: model).height)
    }
}

struct BarDragHandle: NSViewRepresentable {
    var onEnd: () -> Void
    func makeNSView(context: Context) -> DragView { let view = DragView(); view.onEnd = onEnd; return view }
    func updateNSView(_ view: DragView, context: Context) { view.onEnd = onEnd }
    final class DragView: NSView {
        var onEnd: (() -> Void)?
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event); onEnd?() }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}

struct InputMeter: View {
    let samples: [Double]
    var sensitivity = 1.0
    var color = Palette.signal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(samples.indices, id: \.self) { index in
                Capsule().fill(color)
                    .frame(width: 3, height: 20)
                    .scaleEffect(x: 1, y: WaveformHistory.height(for: samples[index], sensitivity: sensitivity) / 20)
            }
        }.frame(height: 20)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: samples)
            .accessibilityElement(children: .ignore).accessibilityLabel("Microphone input level")
    }
}
