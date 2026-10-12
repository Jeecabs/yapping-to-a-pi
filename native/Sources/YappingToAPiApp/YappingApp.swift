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
            let panel = DictationPanel(contentRect: NSRect(origin: .zero, size: BarStyle.canvas),
                                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            // The bar draws its own shadow; a window shadow would outline the whole transparent canvas.
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            let host = NSHostingView(rootView: RecordingOverlay(model: model,
                openHub: { [weak self] in self?.openHub() }, onDragEnded: { [weak self] in self?.rememberBarPosition() }))
            // The panel's size follows the bar scale only, never the bar's content.
            host.sizingOptions = []
            panel.contentView = host
            self.panel = panel
        }
        guard let panel else { return }
        let preferences = model.data.settings.appearanceOptions
        let savedScreen = preferences.position.flatMap { position in NSScreen.screens.first { Self.displayID($0) == position.displayID } }
        let screen = savedScreen ?? (panel.isVisible ? panel.screen : nil)
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let screen {
            let scale = preferences.scale
            let placement = OverlayLayout.placement(screen: screen.frame, visible: screen.visibleFrame, row: Self.restingRow(scale),
                                                    canvas: CGSize(width: BarStyle.canvas.width * scale, height: BarStyle.canvas.height * scale),
                                                    inset: BarStyle.inset * scale, preferences: preferences)
            if model.barExpandsUp != placement.expandsUp { model.barExpandsUp = placement.expandsUp }
            if panel.frame != placement.frame { panel.setFrame(placement.frame, display: true) }
        }
        panel.orderFrontRegardless()
    }

    private static func restingRow(_ scale: Double) -> CGSize {
        CGSize(width: BarStyle.restingWidth * scale, height: BarStyle.rowHeight * scale)
    }

    private static func displayID(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func rememberBarPosition() {
        guard let panel, let screen = panel.screen else { return }
        let scale = model.data.settings.appearanceOptions.scale
        let center = OverlayLayout.rowCenter(in: panel.frame, row: Self.restingRow(scale), inset: BarStyle.inset * scale,
                                             expandsUp: model.barExpandsUp)
        model.data.settings.appearanceOptions.position = BarPosition(displayID: Self.displayID(screen),
            x: (center.x - screen.frame.minX) / screen.frame.width,
            y: (center.y - screen.frame.minY) / screen.frame.height)
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
