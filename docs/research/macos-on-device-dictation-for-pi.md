# macOS on-device Dictation from Pi via a hotkey

## Verdict

Yes. There are two viable versions, and the best first version needs no Pi code:

1. **System Dictation into Pi's focused editor (recommended first):** assign a macOS Dictation shortcut, focus Pi's prompt editor, press the shortcut, speak, and press it again to stop. Apple says Dictation can enter text “anywhere you can type.” The OS owns the microphone UI, recognition, punctuation, and on-device/privacy status.
2. **Pi-owned dictation extension (recommended only if we want custom behavior):** a Pi shortcut starts/stops a small native Swift helper using Apple's Speech framework. The helper returns text to the TypeScript extension, which inserts it into the current prompt with `ctx.ui.pasteToEditor()`.

A Pi-owned version should be **toggle-to-talk**, not hold-to-talk. Pi's normal extension shortcut API reports a shortcut activation. Key-release events belong to focused custom TUI components and require terminal protocol support, so press-and-hold would be less portable.

## What is already available on this Mac

Read-only inspection on 2026-07-22 found:

- macOS **26.6** on **Apple M2 Pro** (`arm64`).
- Dictation is enabled (`com.apple.assistant.support`, `Dictation Enabled = 1`).
- The offline Dictation status reports both **en-AU** and **en-US** as installed, high quality, continuous-listening capable, and auto-punctuation capable.
- Dictation's preferred locale is **en-AU**.
- The currently selected trigger could not be identified through a stable, supported preference key; check the **Shortcut** field in Keyboard settings rather than relying on private plist values.

These preferences are useful implementation evidence, but they are undocumented internals. Apple's supported way to verify privacy is the text shown under **System Settings → Keyboard → Dictation**. Apple says that text states whether general Dictation audio and transcripts are processed on the device or sent to Siri servers.[1]

## Option A — use system Dictation directly

### Expected flow

1. Open **System Settings → Keyboard → Dictation**.
2. Confirm the text under Dictation says processing happens on this device.
3. In the **Shortcut** pop-up, use the microphone key, one of Apple's listed shortcuts, or **Customize** a shortcut (Apple gives `Option-Z` as an example).[1]
4. Focus Pi's prompt editor.
5. Press the Dictation shortcut, speak, then press the shortcut again to stop.
6. Review/edit the prompt and press Enter normally.

Apple documents that Dictation:

- enters text anywhere text can be typed;
- starts from the microphone key, configured Dictation shortcut, or **Edit → Start Dictation**;
- can be stopped with Escape, the microphone key, or the configured shortcut;
- supports arbitrary-length dictation and stops after 30 seconds without speech;
- supports auto-punctuation and spoken formatting commands in supported languages.[1]

### Why it should fit Pi

Pi's TUI has a real input editor and explicit IME/focus support. Its extension/TUI APIs also expose editor insertion primitives (`setEditorText()` and `pasteToEditor()`), showing that editor text is a supported mutable surface.[2][3]

The remaining uncertainty is empirical terminal compatibility: Apple's support page says “anywhere you can type,” but it does not specifically certify Pi or every terminal emulator. This can be answered with a one-minute test and requires no system mutation beyond choosing a shortcut.

### Advantages

- No extension, daemon, native build, or model API integration.
- OS-level shortcut can work even though Pi does not receive the Function/Globe key itself.
- Uses Apple's Dictation UI and configured microphone/language.
- On-device behavior is visible in supported System Settings UI.
- Lowest maintenance burden.

### Limitations

- Pi gets committed text, not a structured transcript stream.
- Pi cannot reliably display its own recording status or apply coding-specific vocabulary before insertion.
- There is no documented public API for a Pi extension to command the system Dictation UI to start. Apple's documented start mechanisms are user actions (microphone key, Dictation shortcut, or Edit menu).[1] Apple's developer API is for building an app-owned recognizer, not controlling the system Dictation overlay.[4][5]

## Option B — a Pi-owned on-device dictation extension

### Recommended architecture

```text
Pi TUI shortcut
   │
   ├─ first press: spawn native helper, show “listening” status
   │
   ├─ helper: microphone → Apple Speech framework → partial/final transcript
   │
   └─ second press: stop/finalize helper → paste final text into Pi editor
```

#### TypeScript Pi extension

Use:

- `pi.registerShortcut(...)` for a Pi-local toggle;
- `pi.exec(...)` or a spawned child process for the Swift helper;
- `ctx.ui.setStatus(...)` / `ctx.ui.notify(...)` for recording state;
- `ctx.ui.pasteToEditor(transcript)` to insert at the active cursor rather than replacing the whole prompt;
- `session_shutdown` to terminate a recording/helper cleanly.[2]

The shortcut is active while Pi's TUI is focused. A true system-wide shortcut would instead require a native menu-bar/agent process and macOS global event handling, which is a separate product and may require Accessibility/Input Monitoring permission.

#### Native Swift helper

On macOS 26, use `SpeechAnalyzer` with one of these modules:

- **`SpeechTranscriber` (preferred):** Apple's newer, entirely on-device model. Apple describes it as faster and more flexible, suitable for long-form, conversational, and distant audio. Locale model assets are installed and managed through `AssetInventory`.[5][6]
- **`DictationTranscriber` (fallback or exact system-model preference):** uses the same models as system Dictation or `SFSpeechRecognizer` configured for on-device recognition, and does not support network-only locales.[4]

The helper should:

1. choose `en-AU` by default but make locale configurable;
2. check supported and installed locales;
3. install the needed model with `AssetInventory` if absent (a one-time network download may be required, after which transcription runs locally);[5][6]
4. request microphone access and include `NSMicrophoneUsageDescription` in its app bundle;[7]
5. capture live audio with AVFoundation;
6. expose volatile text for a Pi status/widget if desired;
7. finalize on stop and emit one machine-readable final result on stdout or a local socket.

A bundled helper app is safer than an unbundled Swift script because macOS privacy prompts and usage descriptions are app/bundle-oriented.

### Older compatibility route

`SFSpeechRecognizer` is available on macOS 10.15+. Before starting a request:

- check `supportsOnDeviceRecognition`;
- set `request.requiresOnDeviceRecognition = true`.

Apple says that setting prevents audio from being sent over the network, but is honored only when the recognizer reports on-device support; Apple also notes on-device recognition may be less accurate.[8][9]

This route requires speech-recognition authorization and a valid `NSSpeechRecognitionUsageDescription`; Apple's docs warn that calling authorization without the key crashes the app.[10][11] On this macOS 26 machine, `SpeechAnalyzer` is the better primary API.

## Hotkey design

### Best zero-code hotkey

Use the **microphone key** if present, or a custom macOS Dictation shortcut that does not collide with terminal/Pi bindings. Apple's own example is `Option-Z`.[1]

### Best Pi-owned hotkey

Use a **toggle** such as an unused function key. Avoid shortcuts that already have Pi meanings, including:

- `Escape` — interrupt/abort;
- `Ctrl-D` — exit when the editor is empty;
- `Ctrl-T` — toggle thinking;
- `Alt-D` — delete word forward.

Pi supports extension shortcuts via `registerShortcut()` and documents key names/modifier combinations.[2][12] Function-key behavior still depends on macOS keyboard settings and the physical keyboard.

### Why not hold-to-talk initially

`registerShortcut()` is appropriate for an activation/toggle. Pi TUI components can opt into key-release events, but only through focused component input and terminal support (the docs specifically call out the Kitty protocol).[3] That is too fragile for a first version. A second press to stop is reliable and matches Apple's own system Dictation interaction.

## Recommended sequence

1. **Run the zero-code test first.** Configure the macOS Dictation shortcut and dictate one sentence into Pi.
2. If it works, keep it. This is the smallest, most private, least brittle solution.
3. Build the Pi extension only if we need one of these concrete additions:
   - a visible Pi recording indicator;
   - coding vocabulary/contextual strings;
   - transcript post-processing;
   - automatic insertion at the cursor with controlled whitespace;
   - strict app-owned enforcement of on-device APIs;
   - recording lifecycle tied to the Pi session.
4. If building, target macOS 26 first with `SpeechAnalyzer` + `SpeechTranscriber`, with `DictationTranscriber` as a locale/device fallback. Keep submission manual; do **not** auto-send a dictated prompt.

## Sources

1. Apple, **Dictate messages and documents on Mac**: https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac
2. Pi, **Extensions** (full local documentation): `/Users/lachlanjacobs/.nvm/versions/node/v24.18.0/lib/node_modules/@earendil-works/pi-coding-agent/docs/extensions.md`
3. Pi, **TUI Components** (IME and key-release behavior): `/Users/lachlanjacobs/.nvm/versions/node/v24.18.0/lib/node_modules/@earendil-works/pi-coding-agent/docs/tui.md`
4. Apple Developer, **DictationTranscriber**: https://developer.apple.com/documentation/speech/dictationtranscriber
5. Apple Developer, **Bring advanced speech-to-text to your app with SpeechAnalyzer** (WWDC25): https://developer.apple.com/videos/play/wwdc2025/277/
6. Apple Developer, **AssetInventory**: https://developer.apple.com/documentation/speech/assetinventory
7. Apple Developer, **NSMicrophoneUsageDescription**: https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription
8. Apple Developer, **requiresOnDeviceRecognition**: https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition
9. Apple Developer, **supportsOnDeviceRecognition**: https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition
10. Apple Developer, **requestAuthorization(_:)**: https://developer.apple.com/documentation/speech/sfspeechrecognizer/requestauthorization(_:)
11. Apple Developer, **NSSpeechRecognitionUsageDescription**: https://developer.apple.com/documentation/bundleresources/information-property-list/nsspeechrecognitionusagedescription
12. Pi, **Keybindings**: `/Users/lachlanjacobs/.nvm/versions/node/v24.18.0/lib/node_modules/@earendil-works/pi-coding-agent/docs/keybindings.md`
