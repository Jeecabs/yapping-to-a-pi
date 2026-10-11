# computer, listen

You talk. Your Mac types. On-device dictation with a native Mac app and the **yapping to a pi** [Pi](https://github.com/badlogic/pi-mono) extension.

## Mac app

Build and open the native app:

```bash
pnpm install
pnpm run build:app
pnpm run open:app
```

The bundle is `native/.build/computer, listen.app`. It includes the speech helper, a typographic Dock icon, and a matching menu bar mark. The built app runs without Node or Pi. Builds are signed locally; distribution signing and notarization are separate.

Enable Microphone and Accessibility in the app's setup or Settings. Download a speech language once, then dictate on device. Opening the app does not open the microphone.

| Action | Default |
| --- | --- |
| Hold to talk | Hold **Fn / Globe**, release to finish |
| Hands-free | **Fn + Space** or double-tap **Fn** |
| Finish hands-free dictation | Press **Fn** or click Stop |
| Cancel | **Escape** or the pill's X |
| Edit selected text by voice | Select text, then hold **Fn + Control** |
| Change any shortcut | **Settings → dictation**: click a shortcut, then press new keys |

The small floating pill is always on screen. While you dictate, it shows a rolling waveform from your microphone and recording controls. It starts 6 points above the screen's bottom edge. Drag its middle to move it; the app remembers its position and display. **Settings → Appearance & floating bar** provides a live preview, size, opacity, waveform sensitivity, bottom spacing, screen/Dock anchoring, recenter, and light/dark appearance controls. Sensitivity changes the display, not microphone gain. Preview never records.

The hub includes local searchable text history, original-text recovery, dictionary corrections, spoken snippets, per-app writing styles, and reviewable rewrites. Settings provides microphone selection, Apple-supported speech languages, login launch, Dock visibility, sounds, context, and history retention. Snippets currently insert plain text.

Cleanup is off by default, so you get exactly what you said. Turn it on during setup or in Style. Cleanup, styles, and voice editing use Apple's on-device Foundation Models and require Apple Intelligence. If cleanup fails or is unavailable, the app keeps the original transcript. Voice editing leaves the selection unchanged on failure. When you finish, the text is copied to your clipboard and pasted wherever your cursor is. It stays on the clipboard so you can paste it again. Password fields get the copy but not the paste. Voice edits only replace the selection if it hasn't changed. Nothing presses Return or submits a prompt.

Settings, dictionary, snippets, and optional text history are stored in `~/Library/Application Support/Yapping to a Pi/desktop.json`. Audio is never saved. The app has no cloud processing or analytics. Pi settings remain separate.

The desktop rebrand preserves the original bundle identifier and data folder so existing preferences and history remain available. The repository, Pi package, and CLI names remain `yapping-to-a-pi`.

This app follows Wispr Flow's personal dictation workflow. It does not claim identical model quality or language coverage. See the [feature research and parity notes](docs/WISPR-FLOW-PARITY.md) for the reference behavior and remaining differences.

## Pi extension

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

On your first recording, macOS may ask for microphone access for the terminal app that runs Pi, such as Ghostty, Terminal, or iTerm2. The helper runs as part of that app, so macOS grants access to the app rather than to yapping to a pi. Apple downloads the speech model if needed. Recognition then runs on device.

## Use

Press **F6** to start and stop dictation. On some Mac keyboards, use **Fn-F6**, or enable standard function keys in macOS settings. Press again during preparation to cancel without inserting text.

Pi 1.0 runs fullscreen by default, which adds a clickable **[ ● Dictate ]** button above the editor. Click it to listen, then click **[ ■ Stop mic ]** to insert the transcript. Partial text appears above the editor without changing your draft. The button keeps keyboard focus in the editor and is disabled while finalizing.

In regular mode (`"tuiMode": "regular"` or `pi --tui-mode regular`), the terminal owns mouse input, so the idle button is hidden and you use the shortcut. The microphone stays off until you start dictation.

The transcript goes in at the cursor as plain, editable text, however long it is. If your draft doesn't already end in a space, dictation adds one first. If you switch microphones while dictating, recording continues on the new macOS default input.

If finishing takes too long, Pi inserts the live preview instead and tells you to check it before sending.

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

- **Microphone access denied:** Enable the terminal app that runs Pi, such as Ghostty, Terminal, or iTerm2, in System Settings → Privacy & Security → Microphone.
- **No speech detected:** Select your microphone in Control Center → Sound. Dictation uses the macOS default input device. Run `/dictation doctor` to check it.
- **Helper missing:** Check that macOS and Swift meet the requirements, then reinstall:

  ```bash
  pi remove https://github.com/Jeecabs/yapping-to-a-pi
  pi install https://github.com/Jeecabs/yapping-to-a-pi
  ```

## Privacy

- Apple's `SpeechAnalyzer` transcribes audio on device.
- The extension receives text, never audio. The helper does not save recordings.
- macOS grants microphone access to your terminal app, so other programs you run in that terminal can also use the microphone.
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

`verify` runs TypeScript checks, extension and native tests, both app builds, signature checks, and diagnostics without opening the microphone. Use `pnpm run doctor:native` for helper diagnostics or `pnpm run doctor:app` for bundle diagnostics. Permission results from command-line diagnostics apply to that launch context; the app's Settings shows its GUI permission state.

Builds sign with the first Developer ID Application or Apple Development identity in your keychain. macOS keys Accessibility and Microphone grants to the signature, so a stable identity keeps those grants across rebuilds. With no identity, builds are signed ad hoc, and every rebuild needs Accessibility granted again. To choose an identity, or force ad hoc with `-`:

```bash
YAPPING_TO_A_PI_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" pnpm run build:app
```

Distributing a prebuilt helper requires separate hardened runtime signing and notarization. The Git install builds from source.

### Releasing the Mac app

`pnpm run release:app` builds `native/.build/computer-listen.dmg`. It signs the helper and then the app with a Developer ID, hardened runtime, a secure timestamp and `native/Release.entitlements` (microphone only). It then notarizes and staples the app and the DMG. One-time setup:

1. Create a **Developer ID Application** certificate. In Xcode, go to Settings → Accounts → your team → Manage Certificates → + → Developer ID Application. This needs a paid Apple Developer Program membership.
2. Save notary credentials using an app-specific password from account.apple.com:

```bash
xcrun notarytool store-credentials computer-listen --apple-id you@example.com --team-id TEAMID
```

`YAPPING_TO_A_PI_SKIP_NOTARIZE=1 pnpm run release:app` checks signing and DMG packaging without credentials. The App Store isn't an option. The app needs Accessibility trust to hear its global shortcut and to paste, and sandboxed apps can't receive that trust.

See [Architecture](docs/ARCHITECTURE.md) for the controller, native helper, and protocol.

Audio conversion code is adapted from Apple's WWDC25 SpeechAnalyzer sample. Its license is in [`native/APPLE-SAMPLE-LICENSE.txt`](native/APPLE-SAMPLE-LICENSE.txt).
