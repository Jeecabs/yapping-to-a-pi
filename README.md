# yapping to a pi

Private [Pi](https://github.com/badlogic/pi-mono) package for hotkey-triggered, on-device dictation on macOS.

Press the shortcut once to listen and again to finish. The transcript is pasted at the Pi editor cursor and stays editable. It is never submitted automatically.

## Requirements

- macOS 26 or newer
- a locale supported by Apple's `SpeechTranscriber`
- Xcode Command Line Tools / Swift 6.2 to build the native helper
- Pi interactive TUI

This Mac has already been verified with `en-AU`: the model is supported and installed.

## Install

### HTTPS

```bash
pi install https://github.com/Jeecabs/yapping-to-a-pi
```

### Git shorthand

```bash
pi install git:github.com/Jeecabs/yapping-to-a-pi
```

### Local development

```bash
git clone https://github.com/Jeecabs/yapping-to-a-pi.git
cd yapping-to-a-pi
pnpm install
pi install .
```

`pnpm install` builds and ad-hoc signs `YappingToAPiHelper.app`. Reload Pi if it is already open:

```text
/reload
```

## Use

Default shortcut:

```text
Ctrl-Option-D
```

- First press: prepare and listen.
- Second press: finalize and insert text.
- Edit the text normally, then submit it yourself.

The UI stays quiet while idle. While active, the footer shows only a small `mic` indicator.

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

Pi reloads the extension after a saved change so the new shortcut takes effect.

Environment variables override saved settings for one shell/session:

- `PI_DICTATION_SHORTCUT`
- `PI_DICTATION_LOCALE`
- `PI_DICTATION_HELPER` — native executable override for development

## Commands

| Command | Description |
| --- | --- |
| `/dictation` | Toggle listening |
| `/dictation stop` | Stop and finalize |
| `/dictation status` | Show phase, shortcut, and locale |
| `/dictation settings` | Open the configuration TUI |
| `/dictation doctor` | Check model and microphone status |
| `/dictation shortcut <keys>` | Save a new shortcut and reload |
| `/dictation locale <locale>` | Save a new BCP-47 locale and reload |

## First recording

macOS may ask for microphone access for **yapping to a pi**. If access was denied, enable it in:

```text
System Settings → Privacy & Security → Microphone
```

If a supported language model is not installed, Apple's `AssetInventory` downloads it once before listening.

## Privacy

- Audio goes directly from `AVAudioEngine` to Apple's on-device `SpeechAnalyzer`.
- The extension never receives audio.
- The helper has no network client and does not save recordings.
- Apple may use the network only to download/update model assets through `AssetInventory`.
- Dictated text is inserted into the Pi editor; it reaches the selected model only if you submit the prompt.

## Development

```bash
pnpm install
pnpm check
pnpm test
pnpm build:native
pnpm doctor
```

Architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

Research and primary sources: [`docs/research/macos-on-device-dictation-for-pi.md`](docs/research/macos-on-device-dictation-for-pi.md)

The audio conversion implementation is adapted from Apple's WWDC25 SpeechAnalyzer sample under the license in [`native/APPLE-SAMPLE-LICENSE.txt`](native/APPLE-SAMPLE-LICENSE.txt).
