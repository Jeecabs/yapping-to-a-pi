import AppKit
import SwiftUI
import YappingCore

struct AppIcon: View {
    var size: CGFloat = 44
    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else { Image(systemName: "desktopcomputer").resizable().scaledToFit().foregroundStyle(Palette.accent) }
        }
        .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct MainView: View {
    @Bindable var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                if let error = model.storageError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.12))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        switch model.page {
                        case .home: HomeView(model: model)
                        case .history: HistoryView(model: model)
                        case .dictionary: DictionaryView(model: model)
                        case .snippets: SnippetsView(model: model)
                        case .style: StyleView(model: model)
                        case .rewrite: RewriteView(model: model)
                        case .settings: AppSettingsView(model: model)
                        }
                    }
                    .frame(maxWidth: 820, alignment: .leading).padding(.horizontal, 48).padding(.vertical, 40)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if !model.status.isEmpty {
                    HStack(spacing: 12) {
                        MonoLabel("note", color: Palette.accent)
                        Text(model.status).font(.system(size: 12)).textSelection(.enabled)
                        Spacer(minLength: 8)
                        Button("dismiss") { model.status = "" }
                            .buttonStyle(.plain).font(Brand.mono(11)).foregroundStyle(Palette.muted).help("Dismiss message")
                    }
                    .padding(.horizontal, 48).padding(.vertical, 12).background(Palette.sidebar)
                    .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
                }
            }
        }
        .foregroundStyle(Palette.ink).background(Palette.paper).tint(Palette.accent).frame(minWidth: 920, minHeight: 640)
        .preferredColorScheme(model.data.settings.appearanceOptions.theme == .system ? nil : (model.data.settings.appearanceOptions.theme == .dark ? .dark : .light))
        .task { await model.refreshReadiness() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Wordmark(size: 22)
            }.padding(.horizontal, 10).padding(.top, 28).padding(.bottom, 36)
            VStack(spacing: 2) {
                ForEach(AppPage.allCases) { page in
                    let active = model.page == page
                    Button { model.page = page } label: {
                        HStack(spacing: 12) {
                            Text(page.rawValue.lowercased()).font(.system(size: 14, weight: .medium))
                            Spacer()
                        }
                        .padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
                        .foregroundStyle(active ? Palette.charcoal : Palette.ink)
                        .background(active ? Palette.signal : .clear, in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain).accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12).frame(width: 204).background(Palette.sidebar)
    }
}

/// "computer, listen" with the comma in phosphor, echoing the app icon's c, mark.
struct Wordmark: View {
    var size: CGFloat
    var body: some View {
        Text("computer\(Text(",").foregroundStyle(Palette.accent))\nlisten")
            .font(Brand.display(size)).tracking(-size * 0.036).lineSpacing(-size * 0.14)
            .accessibilityLabel(Brand.name)
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Brand.display(40)).tracking(-1.6)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Separates items inside a section; quieter than the section rule above it.
struct Hairline: View {
    var body: some View { Rectangle().fill(Palette.line.opacity(0.45)).frame(height: 1) }
}

/// A ruled section: hairline, mono label, then content. No boxes.
struct Surface<Content: View>: View {
    var label: String?
    @ViewBuilder var content: Content
    init(_ label: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Rectangle().fill(Palette.line).frame(height: 1)
            if let label { MonoLabel(label) }
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text).font(Brand.mono(11))
            .padding(.horizontal, 8).frame(minWidth: 26).frame(height: 24)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.line) }
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
    }
}

struct RecordButton: View {
    @Bindable var model: AppModel
    var body: some View {
        Button(model.isBusy ? "finish" : "start talking") { model.toggle() }
            .buttonStyle(SignalButtonStyle())
            .disabled(model.phase == .finishing || model.phase == .writing)
    }
}

/// The phosphor screen. Always dark, whatever the window appearance: it is the computer listening.
struct Readout: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(model.phase == .listening ? Palette.signal : Palette.signal.opacity(0.3)).frame(width: 7, height: 7)
                MonoLabel(statusWord, color: Palette.signal)
                Spacer()
                if model.phase == .listening, let start = model.startedAt {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        MonoLabel(Duration.seconds(max(0, context.date.timeIntervalSince(start))).formatted(.time(pattern: .minuteSecond)),
                                  color: Palette.signal.opacity(0.7))
                    }
                }
            }
            Group {
                if model.isBusy {
                    Text(model.preview.isEmpty ? "speak naturally." : model.preview)
                        .font(.system(size: 22, weight: .medium)).lineSpacing(3)
                        .foregroundStyle(Palette.signal.opacity(model.preview.isEmpty ? 0.45 : 1))
                        .textSelection(.enabled)
                } else {
                    Text(model.phase.title.lowercased() + ".").font(Brand.display(44)).tracking(-1.8)
                        .foregroundStyle(Palette.signal)
                }
            }
            .shadow(color: Palette.signal.opacity(0.35), radius: 10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .bottomLeading)
            .padding(.top, 36).padding(.bottom, 28)
            HStack(spacing: 10) {
                if model.phase == .listening {
                    InputMeter(samples: model.waveform.samples, sensitivity: model.data.settings.appearanceOptions.sensitivity)
                } else {
                    KeyCap(text: model.data.settings.shortcuts.talk.title)
                    MonoLabel("hold to talk")
                    KeyCap(text: model.data.settings.shortcuts.handsFree.title).padding(.leading, 10)
                    MonoLabel("hands-free")
                }
                Spacer()
                if model.isBusy { Button("cancel") { model.cancel() }.buttonStyle(LineButtonStyle()) }
                RecordButton(model: model)
            }
        }
        .padding(24)
        .background(Palette.screen, in: RoundedRectangle(cornerRadius: 14))
        .overlay { Scanlines().clipShape(RoundedRectangle(cornerRadius: 14)) }
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)) }
        .environment(\.colorScheme, .dark)
    }

    private var statusWord: String {
        switch model.phase {
        case .idle: "standby"
        case .preparing: model.preparationLabel
        case .listening: model.isCommand ? "rec · editing selection" : "rec"
        case .finishing: "finishing"
        case .writing: "refining on this mac"
        }
    }
}

/// Faint CRT rows. Texture, not decoration: keeps the large dark field from reading as flat fill.
struct Scanlines: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(0.025)))
                y += 3
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct HomeView: View {
    @Bindable var model: AppModel
    var body: some View {
        PageHeading(title: "you talk. your mac types.", subtitle: "Hold the key, say the thing, let go. Your words land wherever you were typing.")

        if !model.data.settings.onboardingComplete { SetupView(model: model) }

        Readout(model: model)

        Surface("last thing you said") {
            ZStack(alignment: .topLeading) {
                if model.latestText.isEmpty {
                    Text("A messy thought. A long email. That thing you keep putting off.")
                        .font(.system(size: 15)).foregroundStyle(Palette.muted).padding(.horizontal, 5).allowsHitTesting(false)
                }
                TextEditor(text: $model.latestText).font(.system(size: 15)).scrollContentBackground(.hidden)
                    .frame(minHeight: 72).accessibilityLabel("Practice dictation")
            }.padding(.horizontal, -5) // TextEditor insets its text; align it with the label above.
            HStack(spacing: 10) {
                MonoLabel("\(model.totalWords.formatted()) words off your mind")
                Spacer()
                Button("find your words ↗") { model.page = .history }.buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accent)
                Button("copy") { model.copy(model.latestText) }.buttonStyle(LineButtonStyle()).disabled(model.latestText.isEmpty)
            }
        }
    }
}

struct SetupView: View {
    @Bindable var model: AppModel
    var body: some View {
        Surface("before we start") {
            VStack(alignment: .leading, spacing: 14) {
                setupRow("microphone", detail: "Hear your voice only while you dictate.", ready: model.microphoneGranted, action: "enable") {
                    model.requestMicrophone()
                }
                setupRow("accessibility", detail: "Use your shortcut and insert text into other apps.", ready: model.accessibilityGranted, action: "enable") {
                    model.requestAccessibility()
                }
                setupRow("language model", detail: "Download once, then transcribe on this Mac.", ready: model.modelInstalled, action: "download") {
                    model.installLanguage()
                }.disabled(model.setupBusy)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("clean up with apple intelligence").font(.system(size: 14, weight: .semibold))
                        Text(model.writerStatus ?? "Optional. Removes filler words and tidies punctuation. Off keeps exactly what you said.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Toggle("Clean up with Apple Intelligence", isOn: $model.data.settings.polish)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(model.writerStatus != nil)
                }
                HStack {
                    if model.microphoneGranted && model.accessibilityGranted && model.modelInstalled {
                        Button("all set. let’s talk.") { model.data.settings.onboardingComplete = true }.buttonStyle(SignalButtonStyle(compact: true))
                    }
                    Spacer()
                    Button("later") { model.data.settings.onboardingComplete = true }.buttonStyle(.plain).font(Brand.mono(11)).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func setupRow(_ title: String, detail: String, ready: Bool, action: String, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer()
            if ready { MonoLabel("● ready", color: Palette.accent).accessibilityLabel("\(title) ready") }
            else { Button(action, action: perform).buttonStyle(LineButtonStyle()).accessibilityLabel("Enable \(title)") }
        }
    }
}

struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var originals: Set<UUID> = []
    @State private var confirmingClear = false
    private var entries: [HistoryEntry] {
        model.data.history.filter { search.isEmpty || $0.text.localizedStandardContains(search) || $0.original.localizedStandardContains(search) || $0.appName.localizedStandardContains(search) }
    }
    var body: some View {
        PageHeading(title: "things you said", subtitle: "Find, copy, and reuse your words. History stays on this Mac.")
        HStack(spacing: 8) {
            TextField("search your history", text: $search).textFieldStyle(.roundedBorder)
            Button("export") { model.exportHistory() }.buttonStyle(LineButtonStyle()).disabled(model.data.history.isEmpty)
            Button("clear") { confirmingClear = true }.buttonStyle(LineButtonStyle(destructive: true)).disabled(model.data.history.isEmpty)
        }
        if entries.isEmpty {
            EmptyState(title: search.isEmpty ? "your first thought belongs here." : "nothing matches.",
                       detail: search.isEmpty ? "Start dictating in any app. Your finished text will be waiting here." : "Try another word or app name.")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in row(entry) }
            }
        }
        Color.clear.frame(height: 0).confirmationDialog("Delete all dictation history on this Mac?", isPresented: $confirmingClear) {
            Button("Delete history", role: .destructive) { model.data.history = [] }
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        let showingOriginal = originals.contains(entry.id)
        return HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                MonoLabel(entry.date.formatted(date: .omitted, time: .shortened), color: Palette.ink)
                MonoLabel(entry.date.formatted(.dateTime.day().month(.abbreviated)))
                MonoLabel(entry.appName).lineLimit(1)
            }.frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 12) {
                Text(showingOriginal ? entry.original : entry.text).font(.system(size: 15)).lineSpacing(2).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    MonoLabel("\(entry.wordCount) words")
                    if entry.isCommand { MonoLabel("voice edit", color: Palette.accent) }
                    Spacer()
                    if entry.original != entry.text {
                        Button(showingOriginal ? "show edited" : "show original") {
                            if !originals.insert(entry.id).inserted { originals.remove(entry.id) }
                        }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
                    }
                    // Plain buttons, not a pull-down Menu: an SF Symbol-labelled Menu per row hung the app
                    // when an accessibility client was attached.
                    Button("delete") { model.data.history.removeAll { $0.id == entry.id } }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                    Button("rewrite") { model.scratchpad = entry.text; model.page = .rewrite }.buttonStyle(LineButtonStyle())
                    Button("copy") { model.copy(showingOriginal ? entry.original : entry.text) }.buttonStyle(LineButtonStyle())
                }
            }
        }
        .padding(.vertical, 20)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

struct EmptyState: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("— empty")
            Text(title).font(Brand.display(22)).tracking(-0.6)
            Text(detail).font(.system(size: 13)).foregroundStyle(Palette.muted).frame(maxWidth: 420, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 28)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}
