import AppKit
import SwiftUI
import YappingCore

struct DictionaryView: View {
    @Bindable var model: AppModel
    @State private var spoken = ""
    @State private var written = ""
    @State private var search = ""
    @State private var editing: UUID?
    var body: some View {
        PageHeading(title: "yes, that’s a word", subtitle: "Names, technical terms, and the words you use every day. Save their exact spelling.")
        Surface(editing == nil ? "add a word" : "edit correction") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 12) {
                    field("when i say", placeholder: "e.g. pie tools", value: $spoken)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary).padding(.bottom, 6)
                    field("write instead", placeholder: "pi-tools", value: $written)
                    if editing != nil { Button("cancel") { reset() }.buttonStyle(LineButtonStyle()) }
                    Button(editing == nil ? "add word" : "save", action: save).buttonStyle(SignalButtonStyle(compact: true))
                        .disabled(written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Leave the spoken form blank to preserve a word's capitalization. Up to 60 characters per field.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
        TextField("find a word", text: $search).textFieldStyle(.roundedBorder)
        let entries = model.data.vocabulary.filter { search.isEmpty || $0.spoken.localizedStandardContains(search) || $0.written.localizedStandardContains(search) }
        if entries.isEmpty {
            EmptyState(title: "every word has a place.", detail: "Add your name, your project's name, or a phrase that needs a little help.")
        } else {
            Surface("\(entries.count) words") {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        HStack(spacing: 14) {
                            Text(entry.spoken).font(Brand.mono(12)).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Palette.muted)
                            Text("→").font(Brand.mono(12)).foregroundStyle(Palette.muted)
                            Text(entry.written).font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
                            Button("edit") { spoken = entry.spoken; written = entry.written; editing = entry.id }
                                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
                            Button { model.data.vocabulary.removeAll { $0.id == entry.id }; if editing == entry.id { reset() } } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                                .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Delete \(entry.written)")
                        }.padding(.vertical, 12)
                        if entry.id != entries.last?.id { Hairline() }
                    }
                }
            }
        }
    }
    private func field(_ label: String, placeholder: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            MonoLabel(label)
            TextField(placeholder, text: value).textFieldStyle(.roundedBorder).onSubmit(save)
        }
    }
    private func save() {
        let written = written.trimmingCharacters(in: .whitespacesAndNewlines)
        let spoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? written : spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty, spoken.count <= 60, written.count <= 60 else { model.status = "Use 1 to 60 characters for each field."; return }
        guard !model.data.vocabulary.contains(where: { $0.id != editing && $0.spoken.caseInsensitiveCompare(spoken) == .orderedSame }) else {
            model.status = "That spoken form already exists. Edit its existing entry."; return
        }
        if let index = model.data.vocabulary.firstIndex(where: { $0.id == editing }) {
            model.data.vocabulary[index].spoken = spoken; model.data.vocabulary[index].written = written
        } else { model.data.vocabulary.append(.init(spoken: spoken, written: written)) }
        reset()
    }
    private func reset() { spoken = ""; written = ""; editing = nil }
}

struct SnippetsView: View {
    @Bindable var model: AppModel
    @State private var trigger = ""
    @State private var expansion = ""
    @State private var search = ""
    @State private var editing: UUID?
    var body: some View {
        PageHeading(title: "said it before", subtitle: "Turn a short spoken phrase into something you write often.")
        Surface(editing == nil ? "new snippet" : "edit snippet") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Spoken phrase, such as ‘my sign off’", text: $trigger).textFieldStyle(.roundedBorder)
                MonoLabel("expands to")
                TextEditor(text: $expansion).font(.system(size: 13)).scrollContentBackground(.hidden).padding(6)
                    .frame(height: 100).background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel("Snippet text")
                HStack {
                    Spacer()
                    if editing != nil { Button("cancel") { reset() }.buttonStyle(LineButtonStyle()) }
                    Button(editing == nil ? "add snippet" : "save snippet", action: save).buttonStyle(SignalButtonStyle(compact: true))
                        .disabled(trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || expansion.isEmpty)
                }
            }
        }
        TextField("find a snippet", text: $search).textFieldStyle(.roundedBorder)
        let snippets = model.data.snippets.filter { search.isEmpty || $0.trigger.localizedStandardContains(search) || $0.text.localizedStandardContains(search) }
        if snippets.isEmpty {
            EmptyState(title: "your everyday words, on speed dial.", detail: "Email sign-offs, addresses, introductions, and replies. Say the phrase on its own or inside a sentence.")
        } else {
            ForEach(snippets) { snippet in
                Surface {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("“\(snippet.trigger)”").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.accent)
                            Spacer()
                            Button("edit") { trigger = snippet.trigger; expansion = snippet.text; editing = snippet.id }.buttonStyle(LineButtonStyle())
                            Button("delete") { model.data.snippets.removeAll { $0.id == snippet.id }; if editing == snippet.id { reset() } }
                                .buttonStyle(LineButtonStyle(destructive: true)).accessibilityLabel("Delete \(snippet.trigger)")
                        }
                        Text(snippet.text).font(.system(size: 13)).foregroundStyle(Palette.muted).textSelection(.enabled)
                    }
                }
            }
        }
    }
    private func save() {
        let trigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trigger.isEmpty, trigger.count <= 60, !expansion.isEmpty, expansion.count <= 4_000 else {
            model.status = "Use a phrase up to 60 characters and text up to 4,000 characters."; return
        }
        guard !model.data.snippets.contains(where: { $0.id != editing && $0.trigger.caseInsensitiveCompare(trigger) == .orderedSame }) else {
            model.status = "That phrase already has a snippet."; return
        }
        if let index = model.data.snippets.firstIndex(where: { $0.id == editing }) {
            model.data.snippets[index].trigger = trigger; model.data.snippets[index].text = expansion
        } else { model.data.snippets.append(.init(trigger: trigger, text: expansion)) }
        reset()
    }
    private func reset() { trigger = ""; expansion = ""; editing = nil }
}

struct StyleView: View {
    @Bindable var model: AppModel
    @State private var selectedApp: NSRunningApplication?
    @State private var appStyle: WritingStyle = .natural
    /// Snapshotted when the menu appears, not re-read from NSWorkspace on every render.
    @State private var runningApps: [NSRunningApplication] = []
    var body: some View {
        PageHeading(title: "still sounds like you", subtitle: "Choose your everyday voice, then tailor it to the apps you use.")
        Surface("refine") {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("Refine dictation on this Mac", isOn: $model.data.settings.polish).font(.system(size: 14, weight: .semibold))
                Text("Clean up filler words, punctuation, and spoken corrections with Apple Intelligence. The original is always available in history.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                MonoLabel("default style").padding(.top, 6)
                stylePicker(selection: $model.data.settings.style)
                Text(model.data.settings.style.instruction).font(.system(size: 13)).foregroundStyle(.secondary)
                if let reason = model.writerStatus { Label(reason, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
            }
        }
        Surface("per app") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Keep messages casual and emails polished. An app's style takes priority over your default.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                HStack {
                    Menu(selectedApp?.localizedName ?? "Choose an open app") {
                        ForEach(runningApps, id: \.processIdentifier) { app in
                            Button(app.localizedName ?? "App") { selectedApp = app }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    .onAppear {
                        runningApps = NSWorkspace.shared.runningApplications
                            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
                    }
                    Picker("Style", selection: $appStyle) { ForEach(WritingStyle.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 150)
                    Button("add app") {
                        guard let app = selectedApp, let id = app.bundleIdentifier else { return }
                        model.data.appStyles.removeAll { $0.bundleID == id }
                        model.data.appStyles.append(.init(bundleID: id, name: app.localizedName ?? id, style: appStyle))
                        selectedApp = nil
                    }.buttonStyle(LineButtonStyle()).disabled(selectedApp == nil)
                }
                ForEach($model.data.appStyles) { $entry in
                    Hairline()
                    HStack {
                        Text(entry.name).font(.system(size: 13))
                        Spacer()
                        Picker("Style for \(entry.name)", selection: $entry.style) {
                            ForEach(WritingStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 150)
                        Button("remove") { model.data.appStyles.removeAll { $0.id == entry.id } }.buttonStyle(LineButtonStyle()).accessibilityLabel("Remove style for \(entry.name)")
                    }
                }
            }
        }
    }
    private func stylePicker(selection: Binding<WritingStyle>) -> some View {
        Picker("Default style", selection: selection) {
            ForEach(WritingStyle.allCases, id: \.self) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented).labelsHidden()
    }
}

struct RewriteView: View {
    @Bindable var model: AppModel
    @State private var name = ""
    @State private var instruction = ""
    @State private var editing: UUID?
    @State private var customError: String?
    var body: some View {
        PageHeading(title: "say it another way", subtitle: "Paste a draft. Pick a direction.")
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Picker("Rewrite as", selection: $model.selectedTransform) {
                        ForEach(RewritePreset.allCases) { Text($0.title).tag(RewriteChoice.preset($0)) }
                        if !model.data.transforms.isEmpty {
                            Section("your rewrites") {
                                ForEach(model.data.transforms) { Text($0.name).tag(RewriteChoice.custom($0.id)) }
                            }
                        }
                    }.labelsHidden().frame(width: 180, alignment: .leading).accessibilityLabel("Rewrite as")
                    Spacer()
                    Button("use last dictation") { if let text = model.lastDictation { model.scratchpad = text } }
                        .buttonStyle(LineButtonStyle()).disabled(model.lastDictation == nil)
                }
                TextEditor(text: $model.scratchpad).font(.system(size: 14)).scrollContentBackground(.hidden).padding(8)
                    .frame(height: 180).background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel("Text to rewrite")
                if let problem = model.transformError ?? model.transformProblem {
                    Text(problem).font(.system(size: 12)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }
                HStack {
                    if model.transformUndo != nil {
                        Button("undo", action: model.undoTransform).buttonStyle(LineButtonStyle())
                    }
                    Spacer()
                    if model.transforming {
                        ProgressView().controlSize(.small).accessibilityLabel("Rewriting")
                        Button("cancel", action: model.discardTransform).buttonStyle(LineButtonStyle())
                    }
                    Button(model.transforming ? "rewriting…" : "rewrite") { model.runTransform() }
                        .buttonStyle(SignalButtonStyle(compact: true))
                        .disabled(model.transforming || model.transformProblem != nil || model.scratchpad.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !model.transformResult.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Hairline()
                        MonoLabel("another way", color: Palette.accent)
                        Text(model.transformResult).textSelection(.enabled).font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Button("use result", action: model.applyTransform).buttonStyle(LineButtonStyle())
                            Button("discard", action: model.discardTransform).buttonStyle(LineButtonStyle())
                            Spacer()
                            Button("copy result") { model.copy(model.transformResult) }.buttonStyle(LineButtonStyle())
                        }
                    }
                }
            }
        }
        Surface {
            DisclosureGroup("your own rewrites") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.data.transforms) { transform in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(transform.name).font(.system(size: 13, weight: .medium))
                                Text(transform.instruction).font(.caption).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Button("edit") { editing = transform.id; name = transform.name; instruction = transform.instruction; customError = nil }
                                .buttonStyle(LineButtonStyle()).accessibilityLabel("Edit \(transform.name)")
                            Button("delete") { model.removeTransform(transform.id); if editing == transform.id { reset() } }
                                .buttonStyle(LineButtonStyle(destructive: true)).accessibilityLabel("Delete \(transform.name)")
                        }
                        Hairline()
                    }
                    TextField("name", text: $name).textFieldStyle(.roundedBorder)
                    TextField("what should change?", text: $instruction, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...4)
                    if let customError { Text(customError).font(.caption).foregroundStyle(Palette.muted) }
                    HStack {
                        Spacer()
                        if editing != nil { Button("cancel", action: reset).buttonStyle(LineButtonStyle()) }
                        Button(editing == nil ? "save rewrite" : "save changes") {
                            customError = model.saveTransform(name: name, instruction: instruction, replacing: editing)
                            if customError == nil { reset() }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(LineButtonStyle())
                    }
                }.padding(.top, 14)
            }.font(.system(size: 13, weight: .medium))
        }
    }
    private func reset() { name = ""; instruction = ""; editing = nil; customError = nil }
}

struct AppSettingsView: View {
    @Bindable var model: AppModel
    @State private var confirmHistoryOff = false
    var body: some View {
        PageHeading(title: "make yourself at home", subtitle: "Your shortcuts, your language, your little floating bar.")
        AppearanceView(model: model)
        Surface("dictation") {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(ShortcutBindings.Action.allCases, id: \.self) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        ShortcutRecorder(model: model, action: action)
                    }
                }
                HStack {
                    Text("Click a shortcut, then press the new keys. A modifier on its own, like fn or right ⌥, works for holding. Double-tap the hold key for hands-free.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("reset shortcuts") { model.data.settings.shortcutBindings = nil; model.data.settings.hotkey = .function }
                        .buttonStyle(LineButtonStyle()).disabled(model.data.settings.shortcuts == .defaults)
                }
                if !model.shortcutReady { Label("Enable Accessibility to use the global shortcut.", systemImage: "keyboard").font(.caption).foregroundStyle(.secondary) }
                if model.globeKeyActs && model.data.settings.shortcuts.usesFunctionKey {
                    HStack {
                        Label("macOS also uses 🌐, so fn can open emoji too. Set “Press 🌐 key to” to Do Nothing.", systemImage: "globe")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("keyboard settings", action: model.openKeyboardSettings).buttonStyle(LineButtonStyle())
                    }
                }
                Hairline()
                Picker("Speech language", selection: $model.data.settings.locale) {
                    if !model.locales.contains(model.data.settings.locale) { Text(model.data.settings.locale).tag(model.data.settings.locale) }
                    ForEach(model.locales, id: \.self) { Text(Locale.current.localizedString(forIdentifier: $0) ?? $0).tag($0) }
                }.onChange(of: model.data.settings.locale) { Task { await model.refreshReadiness() } }
                HStack {
                    Label(model.modelInstalled ? "Language ready on this Mac" : "Language model needs a download", systemImage: model.modelInstalled ? "checkmark.circle" : "arrow.down.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(model.setupBusy ? "downloading…" : "download") { model.installLanguage() }.buttonStyle(LineButtonStyle()).disabled(model.setupBusy || model.modelInstalled || model.isBusy)
                }
                Picker("Microphone", selection: $model.data.settings.inputUID) {
                    Text("System default (\(model.inputDevice))").tag("")
                    if !model.data.settings.inputUID.isEmpty && !model.audioInputs.contains(where: { $0.id == model.data.settings.inputUID }) {
                        Text("Selected microphone unavailable").tag(model.data.settings.inputUID)
                    }
                    ForEach(model.audioInputs) { Text($0.name).tag($0.id) }
                }
                Toggle("Play start and finish sounds", isOn: $model.data.settings.soundEffects)
            }
        }
        Surface("on this mac") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLogin($0) }))
                Toggle("Show in Dock", isOn: $model.data.settings.showDockIcon)
                Hairline()
                HStack {
                    Label(model.microphoneGranted ? "Microphone enabled" : "Microphone needed", systemImage: "mic")
                    Spacer()
                    Button(model.microphoneGranted ? "manage" : "enable") { model.microphoneGranted ? model.openPrivacy("Microphone") : model.requestMicrophone() }.buttonStyle(LineButtonStyle())
                }
                HStack {
                    Label(model.accessibilityGranted ? "Accessibility enabled" : "Accessibility needed", systemImage: "keyboard")
                    Spacer()
                    Button(model.accessibilityGranted ? "manage" : "enable") { model.requestAccessibility() }.buttonStyle(LineButtonStyle())
                }
                Button("refresh permissions") { Task { await model.refreshReadiness() } }.buttonStyle(LineButtonStyle())
            }.font(.system(size: 13))
        }
        Surface("private by design") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Speech and writing models run on your Mac. Audio is never saved. No account, cloud processing, or analytics.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Toggle("Use nearby text for names and spelling", isOn: $model.data.settings.useContext)
                Text("Only the active text field is read. Context is discarded after dictation; password fields are excluded.")
                    .font(.caption).foregroundStyle(.secondary)
                Hairline()
                Toggle("Keep text history on this Mac", isOn: Binding(get: { model.data.settings.saveHistory }, set: { enabled in
                    if enabled { model.data.settings.saveHistory = true } else { confirmHistoryOff = true }
                }))
                Picker("Keep history for", selection: $model.data.settings.retentionDays) {
                    Text("24 hours").tag(1); Text("7 days").tag(7); Text("30 days").tag(30); Text("Until I delete it").tag(0)
                }.disabled(!model.data.settings.saveHistory).onChange(of: model.data.settings.retentionDays) { model.data.pruneHistory() }
                Button("open local data folder") { model.openDataFolder() }.buttonStyle(LineButtonStyle())
                Text("\(model.writerStatus ?? "Apple Intelligence is ready for on-device cleanup and voice editing.")")
                    .font(.caption).foregroundStyle(.secondary)
            }.font(.system(size: 13))
        }
        Surface {
            HStack(spacing: 12) {
            AppIcon(size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(Brand.name).font(.system(size: 13, weight: .semibold))
                MonoLabel("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0") · macos 26+")
            }
            Spacer()
            Link("github ↗", destination: URL(string: "https://github.com/Jeecabs/yapping-to-a-pi")!).font(.system(size: 12, weight: .medium))
            }
        }
        .confirmationDialog("Turn off history and delete saved dictations?", isPresented: $confirmHistoryOff) {
            Button("Turn off and delete", role: .destructive) { model.data.settings.saveHistory = false; model.data.history = [] }
        }
    }
}

struct AppearanceView: View {
    @Bindable var model: AppModel
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    MonoLabel("appearance & floating bar")
                    Spacer()
                    Button(model.previewingBar ? "hide preview" : "preview bar") {
                        model.previewingBar ? model.endBarPreview() : model.previewBar()
                    }.buttonStyle(LineButtonStyle())
                }
                Picker("Appearance", selection: $model.data.settings.appearanceOptions.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Hairline()
                HStack {
                    Text("Bar size").frame(width: 106, alignment: .leading)
                    Slider(value: $model.data.settings.appearanceOptions.barScale, in: 0.8...1.3, step: 0.05)
                        .accessibilityLabel("Floating bar size")
                    Text("\(Int((model.data.settings.appearanceOptions.barScale * 100).rounded()))%")
                        .monospacedDigit().frame(width: 42, alignment: .trailing)
                }
                HStack {
                    Text("On hover").frame(width: 106, alignment: .leading)
                    Picker("On hover", selection: $model.data.settings.appearanceOptions.hover) {
                        ForEach(BarHoverDetail.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                HStack {
                    Text("Background").frame(width: 106, alignment: .leading)
                    Slider(value: $model.data.settings.appearanceOptions.opacity, in: 0.6...1, step: 0.05)
                        .accessibilityLabel("Floating bar background opacity")
                    Text("\(Int((model.data.settings.appearanceOptions.opacity * 100).rounded()))%")
                        .monospacedDigit().frame(width: 42, alignment: .trailing)
                }
                HStack {
                    Text("Waveform").frame(width: 106, alignment: .leading)
                    Slider(value: $model.data.settings.appearanceOptions.sensitivity, in: 0.5...2, step: 0.1)
                        .accessibilityLabel("Waveform sensitivity")
                    Text("\(model.data.settings.appearanceOptions.sensitivity.formatted(.number.precision(.fractionLength(1))))×")
                        .monospacedDigit().frame(width: 42, alignment: .trailing)
                }
                Text("Turn up the movement for a quieter microphone. This only changes the display.")
                    .font(.caption).foregroundStyle(Palette.muted)
                Picker("Position", selection: $model.data.settings.appearanceOptions.edge) {
                    ForEach(BarEdge.allCases, id: \.self) { Text($0.title).tag($0) }
                }.onChange(of: model.data.settings.appearanceOptions.edge) { model.data.settings.appearanceOptions.position = nil }
                HStack {
                    Text("Bottom spacing").frame(width: 106, alignment: .leading)
                    Slider(value: $model.data.settings.appearanceOptions.bottomSpacing, in: 0...100, step: 2)
                        .accessibilityLabel("Floating bar bottom spacing")
                    Text("\(Int(model.data.settings.appearanceOptions.bottomSpacing)) pt").monospacedDigit().frame(width: 42, alignment: .trailing)
                }.onChange(of: model.data.settings.appearanceOptions.bottomSpacing) { model.data.settings.appearanceOptions.position = nil }
                HStack {
                    Text("Drag the middle of the pill to place it anywhere. Your position is remembered.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("recenter") { model.data.settings.appearanceOptions.position = nil; model.previewBar() }.buttonStyle(LineButtonStyle())
                    Button("reset") { model.data.settings.appearance = nil; model.previewBar() }.buttonStyle(LineButtonStyle())
                }
            }.font(.system(size: 13))
        }
        .onChange(of: model.data.settings.appearanceOptions) { model.previewBar() }
        .onDisappear { model.endBarPreview() }
    }
}
