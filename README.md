# yapping to a pi

On-device voice dictation for [Pi](https://github.com/badlogic/pi-mono) on macOS.

Press **F6** to listen, then press it again to insert the transcript at your editor cursor. Edit before sending. Dictation never submits a prompt.

## Requirements

- macOS 26 or newer
- Xcode Command Line Tools with Apple Swift 6.2 or newer and the Xcode license accepted
- Node.js 22.19.0 or newer
- Pi 0.85.0 or newer
- A language supported by Apple's `SpeechTranscriber`

## Install

```bash
pi install https://github.com/Jeecabs/yapping-to-a-pi
```

Installation builds the native helper locally. If Pi is already open, run `/reload`.

On your first recording, macOS may ask for microphone access for **yapping to a pi**. Apple downloads the speech model if needed. Recognition then runs on device.

## Use

Press **F6** to start and stop dictation. On some Mac keyboards, use **Fn-F6**, or enable standard function keys in macOS settings. Press again during preparation to cancel without inserting text.

For a clickable mic button, start Pi in fullscreen mode:

```bash
pi --tui-mode fullscreen
```

Click **[ ● Dictate ]** to listen, then **[ ■ Stop mic ]** to insert the transcript. Partial text appears above the editor without changing your draft. The button keeps keyboard focus in the editor and is disabled while finalizing.

The idle button appears only in fullscreen mode. The microphone stays off until you start dictation.

## Settings

Run `/dictation settings` to change the shortcut or language and run diagnostics. Select the shortcut and press your new key combination.

You can also configure these directly:

```text
/dictation shortcut f6
/dictation shortcut ctrl+alt+x
/dictation locale en-AU
```

Pi saves settings to `~/.pi/agent/yapping-to-a-pi.json` and reloads the extension after each change. Defaults are `f6` and `en-AU`.

Modified letter shortcuts ignore Shift and Caps Lock. Pi rejects shortcuts that conflict with editor controls, including Shift-only letters.

Environment variables override saved settings for the current session:

| Variable | Purpose |
| --- | --- |
| `PI_DICTATION_SHORTCUT` | Shortcut binding |
| `PI_DICTATION_LOCALE` | BCP-47 language tag, such as `en-AU` or `en` |
| `PI_DICTATION_HELPER` | Native executable path for development |

## Commands

| Command | Description |
| --- | --- |
| `/dictation` | Toggle listening |
| `/dictation stop` | Stop or cancel the active recording |
| `/dictation status` | Show recording state, input device, shortcut, and language |
| `/dictation settings` | Open settings |
| `/dictation doctor` | Check input device, speech model, and microphone permission |
| `/dictation shortcut <keys>` | Save a shortcut and reload |
| `/dictation locale <locale>` | Save a language tag and reload |

## Troubleshooting

- **Microphone access denied:** Enable **yapping to a pi** in System Settings → Privacy & Security → Microphone.
- **No speech detected:** Select your microphone in Control Center → Sound. Dictation uses the macOS default input device. Run `/dictation doctor` to check it.
- **Helper missing:** Check that macOS and Swift meet the requirements, then reinstall:

  ```bash
  pi remove https://github.com/Jeecabs/yapping-to-a-pi
  pi install https://github.com/Jeecabs/yapping-to-a-pi
  ```

Local builds use ad-hoc signing. macOS may ask for microphone permission again after a helper update.

## Privacy

- Apple's `SpeechAnalyzer` transcribes audio on device.
- The extension receives text, never audio. The helper does not save recordings.
- Model downloads and updates use Apple's `AssetInventory`. The helper has no network client.
- Dictation stops when the Pi session shuts down.
- The transcript reaches your selected AI model only when you submit the prompt.

## Development

```bash
git clone https://github.com/Jeecabs/yapping-to-a-pi.git
cd yapping-to-a-pi
pnpm install
pi install .
pnpm run verify
```

`verify` runs TypeScript checks, existing tests, the native build, and diagnostics without opening the microphone. Use `pnpm run doctor:native` for native diagnostics alone.

To sign a local build with your own identity:

```bash
YAPPING_TO_A_PI_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" pnpm run build:native
```

Distributing a prebuilt helper requires separate hardened runtime signing and notarization. The Git install builds from source.

See [Architecture](docs/ARCHITECTURE.md) for the controller, native helper, and protocol.

Audio conversion code is adapted from Apple's WWDC25 SpeechAnalyzer sample. Its license is in [`native/APPLE-SAMPLE-LICENSE.txt`](native/APPLE-SAMPLE-LICENSE.txt).
