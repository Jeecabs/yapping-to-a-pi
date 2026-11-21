# Architecture

## Two native clients

The repository ships a Pi extension and **computer, listen**, an independent SwiftUI/AppKit app. Both use the same Swift speech helper. Neither sends audio outside the native process or submits dictated text.

```txt
Pi lifecycle -> DictationController -> TypeScript process adapter --+
                                                                 +-> native Swift helper -> Apple Speech
Mac app -> AppModel -> Swift HelperSession process adapter --------+
           |
           +-> optional on-device Foundation Models -> text insertion
```

`YappingCore` holds validated desktop protocol messages, text replacements, settings/history storage, shortcut gestures, audio input discovery, and floating-bar geometry. `YappingToAPiApp` owns global shortcuts, the nonactivating panel, permissions, app lifecycle, local writing, and Accessibility/clipboard insertion. Pi's existing seams remain unchanged.

The desktop transport reads stdout with POSIX `read` on a dedicated thread. `FileHandle.read(upToCount:)` waits to fill a pipe buffer on macOS and must not be used for live status delivery. The app validates bounded NDJSON frames before updating state. A fake-helper regression test verifies listening is received while the child is still alive and graceful stop delivers final text.

Recording snapshots its language, microphone, style, dictionary, snippets, and destination. Late callbacks are rejected by a session identifier. Preparation, permission, model download, and finalization have deadlines. Cancel and app shutdown close stdin, terminate the helper, and escalate to SIGKILL. A stop during preparation discards the result. Normal stop waits for the final transcript. Failure retains the latest text for manual recovery, and so does cancelling while the writing model is still refining: the transcript is kept before the model sees it.

The desktop helper is embedded inside `computer, listen.app/Contents/Resources`. Microphone permission belongs to the GUI app when launched normally. Accessibility enables global shortcuts and insertion. When dictation finishes, the text goes on the clipboard and stays there, then the app sends Command-V to whatever has focus. Apps match that shortcut by character, so the key is looked up on the current keyboard layout with Command held: the key in QWERTY's V position is ⌘K on Dvorak and ⌘C on Turkish F. Secure fields are excluded: the text is copied but not pasted. Plain dictation reads only the focused field's role, length and selection range; its text and selected text are read for a voice edit or when nearby-text spelling is on. Accessibility calls wait on the other app from the thread that filters the keyboard, so their timeout is one second rather than the default six. A dictation finished with the app's own window in front is copied and shown on Home, and reported as copied rather than as a failed paste. Voice edits replace a selection, so they paste only when the captured field, selection, and contents are unchanged. No Return event is synthesized. Where the focused field reports its length through Accessibility, the app confirms the paste changed it; terminals and some web views don't report it and are taken on trust. The floating bar then says where the text landed (for example, "pasted in Notes") or that it stayed on the clipboard, and why.

The floating bar is always on screen. Its panel is a fixed, mostly transparent canvas sized for the largest state, so state changes and the hover card are SwiftUI animations rather than window resizes; transparent pixels pass clicks through to the app below. Resting the pointer on the bar opens a card with the shortcuts for the current state, built from the user's bindings (Settings: on hover, off, compact or full). Near the top of the screen it opens downward. The hints are laid out at the card's full width and pinned beside the pill, which never moves; the card's growing clip uncovers them and they fade in behind it. Pinned to the card's moving edge, they would start on top of the controls and truncate while the width animates.

A hold key starts recording after 220 ms, the longest press that still counts as a tap. Hold bindings match their modifiers exactly, so ⌘ fn is someone else's shortcut. If another modifier joins before recording starts, the hold is dropped silently, except ⌃ joining fn, which becomes edit; any other key while a modifier hold key is down cancels. The bar's buttons and the menu start and stop recordings too, and a start can be refused (a password field, no selection to edit), so the gesture is brought in line with the recorder on every key event: a recording it did not begin counts as hands-free and ends on the next press or toggle, and one that never began is forgotten. A refusal is named on the bar. When macOS disables the event tap, the release of a hold key may have been missed; if the key is no longer down, a held recording is finished rather than discarded, and a hands-free one carries on. Settings rejects bindings that equal an enabled macOS shortcut (read with `CopySymbolicHotKeys`) and modifier keys used constantly while typing (⇧, left ⌘). When a binding uses fn and macOS still acts on 🌐 (`AppleFnUsageType` unset or non-zero), Settings says so, because the emoji picker or input switch fires alongside dictation.

Accessibility grants are stored against the code signature that was trusted at the time. A grant made for an older signature (for example an Apple Development build) still shows as on in System Settings but reports untrusted for the Developer ID build, and turning it off and on does not refresh it. Remove the entry, or run `tccutil reset Accessibility com.jeecabs.yapping-to-a-pi`, and grant again. The app keeps polling until the event tap installs, not just until trust is reported.

Foundation Models is optional and independently checks availability and locale support. Dictation cleanup is off until the user opts in during setup or in Style. The model follows instructions loosely: measured on macOS 26.7, a rules-only prompt answered dictated questions ("what is the capital of France" came back as "Paris"), carried out dictated requests, and obeyed nearby text it was only meant to read. So each request carries worked examples as earlier conversation turns, which cut that sharply, and no reply is trusted on its own: `TextRules.isFaithful` accepts tidied text only if it opens with the speaker's first word, keeps most of the words in order, adds few, is not much longer, and keeps a question a question. Tone styles get more room to drop and add words, under the same rule. Cleanup works on sentence-aligned chunks of at most 800 characters; a chunk that fails the check, trips a guardrail or takes over 20 seconds is kept exactly as spoken, so the result is always the speaker's words. The reply is capped at about the length of the chunk. Expect roughly half a second for a sentence and 3.5 seconds per 1,000 characters. Command editing has a bounded selected-text input and never replaces it on generation failure: the reply is capped, tags the model echoes are stripped, and an edit that takes over 45 seconds or comes back several times longer than the selection is discarded. Context is transient. History stores text only, with retention and never-store controls. The atomic local document uses a private directory and file permissions; unreadable data is preserved rather than overwritten.

Rewrite uses four built-in `RewritePreset` choices and up to eight saved custom instructions. Selection identifies a preset or custom UUID explicitly. Loading older data removes only the two unchanged legacy presets; edited instructions survive. The shared editing call generates plain text: a generated schema copied the source in live tests instead of applying requests such as bullet-list formatting. Each request snapshots the draft, instruction and locale. Editing the draft, changing the choice, cancelling or shutting down invalidates the request, so late results cannot replace newer work. Errors appear beside the editor. Applying a result enables undo until the next draft edit. Rewrite never pastes or submits text, and its last-dictation action can use saved history after launch.

The panel is 148 × 32 points while listening at default scale, and 84 × 32 while idle. It starts at the screen's bottom edge, follows the pointer's display until positioned, and stores dragged positions as display-relative coordinates. Saved positions are clamped after display or size changes. Appearance controls preview the real panel without opening the microphone. Text and long errors remain in the hub.

The opt-in microphone meter measures the capture buffer independently of the recognition format. It supports Float32, Float64, Int16 and Int32 PCM, including interleaved input, and takes the loudest channel's RMS. Apple's en-AU speech format on the development Mac is Int16; reading only `floatChannelData` from converted buffers suppressed all level messages. Levels now use a speech-oriented -60 to -18 dBFS display range, emit at most every 40 ms, and feed thirteen recent samples. Silence produces a flat line. Display sensitivity does not alter captured audio, and Reduce Motion disables interpolated bar motion.

`Brand.swift` owns the desktop's name, typography, and light/dark palette. Display names, icon assets, menus and bundle path use **computer, listen**. Internal executable names, the bundle identifier and Application Support directory retain their original names for compatibility. The optional sensitivity preference decodes safely from existing settings.

`build:app` builds the helper and desktop executable, generates a full `.icns` from `assets/AppIcon.png`, embeds the helper, signs and verifies a staged bundle, then replaces the previous bundle. `postinstall` continues to build only the helper for Pi.

## Runtime flow

```txt
Mic button, F6, or /dictation
        │
        ▼
Pi extension (`src/index.ts`)
        │ toggle
        ▼
DictationController
        │ starts/stops one session
        ▼
Native helper process adapter
        │ NDJSON over stdout; newline stop request over stdin
        ▼
YappingToAPiHelper.app
        │ microphone buffers
        ▼
AVAudioEngine → SpeechAnalyzer → SpeechTranscriber
        │
        └─ Apple-managed on-device model assets
```

The extension never receives audio. It receives only helper state messages and transcript text.

## Deep modules

### `DictationController`

Small interface:

```ts
toggle(options): "started" | "stop-requested"
stop(reason): boolean
snapshot(): DictationSnapshot
dispose(): Promise<void>
```

The implementation hides helper creation, monotonic state transitions, partial transcript state, final transcript deduplication, the preview fallback for a recording that breaks or will not finish, SIGTERM/SIGKILL escalation, bounded disposal, process exit behavior, and cleanup. Generation tokens reject callbacks from detached helper sessions. The extension supplies callbacks for state changes and one finalized transcript.

### Native helper

Small process interface:

```txt
stdin:  one newline requests graceful stop
stdout: one validated NDJSON message per line
exit:   0 after normal finalization; non-zero after failure
```

The implementation hides microphone permission, equivalent-locale resolution, model installation, audio conversion, input-device restarts, streaming recognition, volatile-result replacement, supervised pipeline tasks, and finalization. A synchronized stop gate prevents preparation from starting later side effects after cancellation. Bounded audio queues turn overload into a visible failure instead of silently dropping speech.

## Protocol

Messages are newline-delimited JSON:

```json
{"type":"state","state":"preparing","locale":"en-AU"}
{"type":"state","state":"listening","locale":"en-AU","inputDevice":"MacBook Pro Microphone"}
{"type":"partial","text":"hello wor"}
{"type":"final","text":"Hello world."}
{"type":"error","code":"microphone-denied","message":"Microphone access was denied."}
```

Each `partial` carries the finalized text plus the current volatile text, and the helper sends one after every recognition result, including final ones. The helper may repeat `listening` with a new `inputDevice` after an input-device change.

The desktop client passes `--meter` to opt into `{"type":"level","level":0.5}` messages, normalized from input RMS and throttled to about 12 Hz. These contain no audio samples. Pi does not request or receive meter messages, so its protocol remains unchanged. `--input-uid <UID>` selects a specific microphone for desktop recordings; omitting it follows the macOS default. A missing selected device fails visibly. Device UIDs are resolved on every recording.

The TypeScript adapter validates parsed JSON before it reaches the controller. Unknown message types and malformed lines become protocol errors; they are never cast into trusted values.

## Lifecycle

- First toggle while idle checks host requirements, then starts one helper. Unsupported macOS releases get an actionable upgrade message before helper-path validation.
- A toggle while preparing cancels remaining preparation; it does not insert a transcript.
- A toggle while listening requests graceful finalization.
- The helper keeps capturing for 200 ms after the stop request, then stops capture, drains converted audio, finalizes SpeechAnalyzer, and awaits the complete result stream. The end of the last word is still inside the audio hardware when the request arrives, and stopping the engine drops the block the tap has not yet delivered (100 ms blocks, measured). Losing 150 ms from the end of a sentence changed its last word in one of six test recordings, and 300 ms in four.
- The transcriber reports volatile results without `.fastResults`, so the live preview arrives in bursts about four seconds apart. That option updates it about every second, but cost final accuracy on noisy audio in testing (4.5% to 5.7% word errors at 15 dB SNR, 14.3% to 18.4% at 5 dB), and the final text is what gets inserted.
- Unexpected audio or recognition task completion fails the session immediately.
- An `AVAudioEngineConfigurationChange` that stops the engine, such as a new default input, restarts capture on the new device and re-emits `listening`. A failed restart ends the session with `microphone-changed`.
- A chosen microphone (`--input-uid`) is selected before the engine starts, and the helper then waits up to 300 ms for the engine to report that change, which takes about 100 ms. An engine already running when the report arrives is stopped by it if the new microphone's format differs from the default's, and the restart lost the audio just after `listening`. The first start also holds the capture lock: a report that arrived mid-start used to start the engine a second time from the restart queue, and installing a second tap is an uncaught exception.
- If a stop after listening does not finish within the stop timeout, the controller terminates the helper, inserts the latest preview if there is one, and enters `failed` with a message saying which happened. Cancelling during preparation still returns to idle quietly.
- A recording that breaks while it is being heard (a helper error, a protocol error, a crash) also inserts the latest preview and says so: Pi has nowhere else to keep the words. A failure before listening, or after preparation was cancelled, inserts nothing.
- A toggle or `/dictation stop` while a failed helper is still exiting is ignored, so the failure keeps its own message.
- While the helper downloads the speech model or waits for microphone permission, the snapshot carries `waitingFor` and the widget says which, so a first run does not look stuck.
- The controller accepts at most one final transcript per recording and ignores late state regressions.
- Input-device detail remains available through status and diagnostics.
- `src/dictation-widget.ts` renders the mic button and partial text without changing the editor. Pi 0.85.0 supplies component-local mouse coordinates.
- Fullscreen mode, the default since Pi 1.0, shows a static idle button. Regular mode hides it because the terminal owns mouse input.
- Button clicks call the same toggle handler as the shortcut. The button never requests keyboard focus. Finalization disables it.
- Modified clicks, repeated clicks in a double-click, and clicks outside the button do not toggle recording.
- The widget has no timer. Shutdown disposes it and clears the UI before the controller stops.
- Pi pastes the finalized transcript at the editor cursor without submitting it. Keeping volatile recognition outside the editor avoids overwriting concurrent human edits or requiring unsupported cursor-range replacement.
- `src/transcript-insertion.ts` splits the transcript into pastes of at most 1000 characters and 10 lines, because Pi's editor collapses larger pastes into an uneditable `[paste #n …]` marker. Each chunk is one undo step. RPC hosts receive one paste because their `pasteToEditor` replaces the whole draft.
- Pi does not expose the cursor position, so insertion adds a leading space when the draft does not already end in whitespace.
- `session_shutdown` invalidates pending async starts and terminates the helper with SIGTERM, escalating to SIGKILL, instead of finalizing a transcript it would discard. It returns within a fixed deadline.

## Permissions and privacy

macOS attributes microphone access to the responsible process: the terminal app that runs Pi, because the helper is its descendant. The permission prompt, the Privacy & Security → Microphone entry, and the `microphone-denied` message therefore refer to that terminal app, not to the helper. `YappingToAPiHelper.app` still contains `NSMicrophoneUsageDescription`. macOS may prompt on the first recording. Capture follows the current macOS default input device; listening state and doctor messages report its name without changing the system route. The app has no network client and does not save audio. Apple's `AssetInventory` may download the locale model once; SpeechTranscriber performs transcription on device.

## Configuration

`/dictation settings` edits the persistent file at `~/.pi/agent/yapping-to-a-pi.json`. Its shortcut recorder parses one raw TUI keypress through Pi's keyboard parser instead of asking the user to type key syntax. Direct `/dictation shortcut …` and `/dictation locale …` commands use the same file and reload the extension after saving. Modified letter shortcuts are canonicalized without Shift and register both shifted and unshifted variants so activation is case-insensitive. Shortcut validation rejects effective Pi/editor collisions across both variants and rejects shift-only letters, which cannot be made case-insensitive without intercepting normal typing. Malformed files are quarantined and invalid environment overrides fall back safely with a warning.

Environment overrides:

- `PI_DICTATION_SHORTCUT`: Pi-local shortcut, default `f6`. Saved shortcuts keep precedence over the default.
- `PI_DICTATION_LOCALE`: BCP-47 locale, default `en-AU`.
- `PI_DICTATION_HELPER`: absolute helper executable override for development.

Configuration is read when Pi loads the extension. Native installation preflights macOS 26+ and Apple Swift 6.2+, accepting all future major versions rather than matching version 26 exactly. Postinstall skips the helper build without disabling the extension when requirements are unmet; explicit development builds still fail. This leaves commands and shortcuts available to explain the requirement. Supported native builds are staged, signed, verified, and swapped into place only after success so a failed rebuild preserves the previous helper.
