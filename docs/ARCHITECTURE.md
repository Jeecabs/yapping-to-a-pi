# Architecture

## Runtime flow

```txt
Ctrl-Option-D or /dictation
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

The implementation hides helper creation, state transitions, final transcript deduplication, stop timeouts, process exit behavior, and cleanup. The extension supplies callbacks for state changes and one finalized transcript.

### Native helper

Small process interface:

```txt
stdin:  one newline requests graceful stop
stdout: one validated NDJSON message per line
exit:   0 after normal finalization; non-zero after failure
```

The implementation hides microphone permission, locale resolution, model installation, audio conversion, streaming recognition, volatile-result replacement, and finalization.

## Protocol

Messages are newline-delimited JSON:

```json
{"type":"state","state":"preparing","locale":"en-AU"}
{"type":"state","state":"listening","locale":"en-AU"}
{"type":"partial","text":"hello wor"}
{"type":"final","text":"Hello world."}
{"type":"error","code":"microphone-denied","message":"Microphone access was denied."}
```

The TypeScript adapter validates parsed JSON before it reaches the controller. Unknown message types and malformed lines become protocol errors; they are never cast into trusted values.

## Lifecycle

- First toggle while idle starts one helper.
- A toggle while preparing/listening requests graceful stop.
- The helper finishes its audio stream and asks SpeechAnalyzer to finalize outstanding text.
- The controller accepts at most one final transcript per recording.
- Pi pastes that transcript at the editor cursor without submitting it.
- `session_shutdown` requests stop, waits briefly, then kills a stuck helper.

## Permissions and privacy

`YappingToAPiHelper.app` contains `NSMicrophoneUsageDescription`. macOS may prompt on the first recording. The app has no network client and does not save audio. Apple's `AssetInventory` may download the locale model once; SpeechTranscriber performs transcription on device.

## Configuration

`/dictation settings` edits the persistent file at `~/.pi/agent/yapping-to-a-pi.json`. Direct `/dictation shortcut …` and `/dictation locale …` commands use the same file and reload the extension after saving.

Environment overrides:

- `PI_DICTATION_SHORTCUT` — Pi-local shortcut, default `ctrl+alt+d`.
- `PI_DICTATION_LOCALE` — BCP-47 locale, default `en-AU`.
- `PI_DICTATION_HELPER` — absolute helper executable override for development.

Configuration is read when Pi loads the extension.
