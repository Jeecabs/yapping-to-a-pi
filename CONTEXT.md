# yapping to a pi

Private Pi package for Lachlan's on-device voice-input workflow. It owns a Pi shortcut, compact status UI, a recording state machine, and a bundled native macOS helper.

## Language

**yapping to a pi**:
A focused Pi package that inserts locally transcribed speech into the prompt editor.
_Avoid_: Voice assistant, autonomous prompt sender, cloud transcription client

**Editable Dictation**:
A final transcript pasted at the current editor cursor and left for human review.
_Avoid_: Auto-submit, voice command execution

**Recording Session**:
One helper process from preparation through final transcript or failure.
_Avoid_: Background microphone daemon, global always-listening process

**Native Helper**:
The bundled macOS executable that hides AVFoundation, SpeechAnalyzer, model assets, permissions, and transcript finalization behind NDJSON.
_Avoid_: Swift logic spread through the TypeScript extension

**Honest Dictation State**:
One of idle, preparing, listening, stopping, or failed, based on process events rather than assumptions.
_Avoid_: Permanent “ready” status without checking the helper

## Relationships

- **yapping to a pi** is installed separately from general operation extensions.
- **Editable Dictation** is produced only after a **Recording Session** finalizes.
- `DictationController` owns **Honest Dictation State** and process cleanup.
- The **Native Helper** is session-scoped and never persists audio.
- Apple speech model assets may require a one-time download; recognition then runs on device.

## Testing

Keep light tests around protocol parsing, state transitions, duplicate-final suppression, stop behavior, and configuration. Compile and doctor the native helper without opening the microphone in automated verification.
