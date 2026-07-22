# yapping to a pi

Private [Pi](https://github.com/badlogic/pi-mono) package for hotkey-triggered, on-device dictation on macOS.

Press the shortcut once to listen and again to finish. The transcript is pasted at the Pi editor cursor and stays editable. It is never submitted automatically.

## Requirements

- macOS 26 or newer
- a locale supported by Apple's `SpeechTranscriber`
- Xcode Command Line Tools / Swift 6.2 with the Xcode license accepted
- Pi interactive TUI

Runtime and install checks accept macOS 26 and all newer major versions. Unsupported hosts receive an actionable version message instead of a generic missing-helper error.

## Install

The repository is private. Configure GitHub HTTPS credentials first if needed:

```bash
gh auth login
gh auth setup-git
```

Then install it directly from GitHub:

```bash
pi install https://github.com/Jeecabs/yapping-to-a-pi
```

Git shorthand also works:

```bash
pi install git:github.com/Jeecabs/yapping-to-a-pi
```

For local development:

```bash
git clone https://github.com/Jeecabs/yapping-to-a-pi.git
cd yapping-to-a-pi
pnpm install
pi install .
```

On a supported host, installation builds `YappingToAPiHelper.app`. On an unsupported host, installation keeps the extension available but skips the helper build so dictation commands can explain the unmet requirement. Reload Pi if it is already open:

```text
/reload
```

If an interrupted update leaves the native helper missing on a supported Mac, reinstall cleanly:

```bash
pi remove https://github.com/Jeecabs/yapping-to-a-pi
pi install https://github.com/Jeecabs/yapping-to-a-pi
```

## Use

Default shortcut:

```text
Ctrl-Option-D
```

- First press: prepare and listen. Letter shortcuts ignore case, so `Ctrl-Option-D` also works with Shift or Caps Lock.
- Second press while listening: finalize and insert text.
- Second press while preparing: cancel; no transcript is inserted.
- Edit the text normally, then submit it yourself.

The UI stays quiet while idle. While active, the footer shows a small `mic` indicator and a compact widget above the editor shows only the current phase and any partial transcript. The finalized transcript is inserted once at the editor cursor so dictation never overwrites edits in progress.

Dictation follows the current macOS default input device. If AirPods or another microphone are selected but provide silence, macOS may not switch automatically; choose the intended input in Control Center → Sound. `/dictation status` identifies the device used by an active recording, and `/dictation doctor` identifies the current default input.

## Settings TUI

```text
/dictation settings
```

The compact settings menu edits the shortcut and locale, and runs diagnostics.

Direct configuration also works:

```text
/dictation shortcut f6
/dictation shortcut ctrl+alt+x
/dictation locale en-AU
```

Shortcut and locale changes are saved to:

```text
~/.pi/agent/yapping-to-a-pi.json
```

Pi reloads the extension after a saved change. Modified letter shortcuts register shifted and unshifted variants for case-insensitive activation; both variants are checked for reserved Pi/editor collisions. If the settings file is malformed, it is quarantined and safe defaults load with a warning.

Environment variables override saved settings for one shell/session:

- `PI_DICTATION_SHORTCUT`
- `PI_DICTATION_LOCALE`
- `PI_DICTATION_HELPER` — native executable override for development

Invalid overrides are ignored with a warning rather than disabling the extension. If the helper is unavailable, `/dictation`, its shortcut, and `/dictation doctor` first report unsupported macOS versions clearly. On a supported macOS release, a missing helper message points to the Xcode/Swift 6.2 build requirement.

## Commands

| Command | Description |
| --- | --- |
| `/dictation` | Toggle listening |
| `/dictation stop` | Stop or cancel the active session |
| `/dictation status` | Show phase, active input device, shortcut, and locale |
| `/dictation settings` | Open the configuration TUI |
| `/dictation doctor` | Check input device, model, and microphone status |
| `/dictation shortcut <keys>` | Save a new shortcut and reload |
| `/dictation locale <locale>` | Save a BCP-47 locale and reload |

Language-only locales such as `en` are valid; the helper resolves them to Apple's supported equivalent and reports the selected locale in diagnostics.

## First recording

macOS may ask for microphone access for **yapping to a pi**. If access was denied, enable it in:

```text
System Settings → Privacy & Security → Microphone
```

If a supported language model is not installed, Apple's `AssetInventory` downloads it once before listening. A stop request prevents later preparation phases, including microphone startup; the controller force-terminates a helper that does not cancel promptly.

## Privacy

- Audio goes directly from `AVAudioEngine` to Apple's on-device `SpeechAnalyzer`.
- The extension never receives audio.
- The helper has no network client and does not save recordings.
- Apple may use the network only to download/update model assets through `AssetInventory`.
- Dictated text is inserted into the Pi editor; it reaches the selected model only if you submit the prompt.

## Native signing

Local builds use an ad-hoc signature by default. macOS may ask for microphone permission again after a helper update, and quarantined copies are not intended for general distribution.

A stable signing identity can be supplied locally:

```bash
YAPPING_TO_A_PI_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" pnpm run build:native
```

Public distribution would additionally require hardened runtime signing and notarization.

## Development

```bash
pnpm install
pnpm run check
pnpm run test
pnpm run test:native
pnpm run build:native
pnpm run doctor:native
```

Or run everything:

```bash
pnpm run verify
```

Architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

Research and primary sources: [`docs/research/macos-on-device-dictation-for-pi.md`](docs/research/macos-on-device-dictation-for-pi.md)

The audio conversion implementation is adapted from Apple's WWDC25 SpeechAnalyzer sample under the license in [`native/APPLE-SAMPLE-LICENSE.txt`](native/APPLE-SAMPLE-LICENSE.txt).
