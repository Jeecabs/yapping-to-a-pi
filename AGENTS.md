# AGENTS.md

## Product direction

**yapping to a pi** is a private Pi input extension for Lachlan's Mac. It turns speech into editable prompt text without sending the prompt automatically.

Core behavior:

- One Pi shortcut toggles listening on and off.
- Speech recognition stays on device after Apple model assets are installed.
- Final text is inserted at the Pi editor cursor and remains editable.
- Dictation never submits a prompt by itself.
- Recording is session-scoped and must stop during `session_shutdown`.
- The extension must remain quiet while idle and must not add LLM tools or prompt guidance.

## Architecture

Keep the three seams distinct:

```txt
Pi extension -> DictationController -> native Swift helper
```

- `src/index.ts` owns Pi lifecycle, commands, shortcut registration, UI, and editor insertion.
- `DictationController` owns the recording state machine and hides process lifecycle details.
- `helper-process.ts` is the native-process adapter and owns NDJSON transport details.
- `native/` owns microphone capture and Apple's Speech framework.

Do not move AVFoundation or Speech-framework details into the Pi extension. Do not make Pi lifecycle code parse raw child-process output.

## TypeScript safety

- Treat helper stdout as untrusted `unknown` and validate every NDJSON message.
- Avoid unchecked casts at the process seam.
- Keep controller tests on the same small interface used by the extension.
- Use Node built-ins; avoid runtime dependencies unless they remove substantial complexity.

## Native safety

- Target macOS 26 and use `SpeechAnalyzer` with `SpeechTranscriber`.
- Keep `NSMicrophoneUsageDescription` in the helper app bundle.
- Emit only NDJSON protocol messages on stdout. Diagnostics belong on stderr.
- Never emit captured audio or save recordings.
- Finalize recognition before exiting after a normal stop request.
- Model downloads are allowed only through Apple's `AssetInventory`.

## Development hygiene

- Run `pnpm check`, `pnpm test`, `pnpm build:native`, and `pnpm doctor` after meaningful changes.
- Do not trigger microphone permission prompts in automated tests.
- Update README and architecture docs when shortcut, install, permissions, or protocol behavior changes.
