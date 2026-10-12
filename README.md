# computer, listen

You talk. Your Mac types. On-device dictation for macOS, plus a [Pi](https://github.com/badlogic/pi-mono) extension.

**[Download for macOS](https://github.com/Jeecabs/yapping-to-a-pi/releases/latest/download/computer-listen.dmg)** · requires macOS 26 · [computerlisten.com](https://computerlisten.com)

Hold a key, talk, let go. The text is pasted wherever you were typing, and the bar tells you where it landed. It never presses Return.

| Action | Default |
| --- | --- |
| Hold to talk | **fn** |
| Hands-free | **fn space**, or double-tap **fn** |
| Edit selected text by voice | hold **⌃ fn** |
| Cancel | **esc** |

Every shortcut can be changed in Settings. The app needs Microphone and Accessibility access, which it uses to hear the shortcut and paste.

**Private by default.** Speech is transcribed on your Mac with Apple's Speech framework. Audio is never saved. There's no account, cloud, or analytics. Apple Intelligence cleanup is optional and off by default.

## Pi extension

```bash
pi install https://github.com/Jeecabs/yapping-to-a-pi
```

Press **F6** to start and stop. The transcript lands at your cursor as editable text and is never sent automatically. Run `/dictation settings` to change the shortcut or language, or `/dictation doctor` if something's off. macOS grants microphone access to the terminal that runs Pi.

Requires Node 22.19+, Pi 0.85+, and Xcode Command Line Tools with Swift 6.2+.

## Development

```bash
pnpm install
pnpm run verify      # type checks, tests, both app builds, diagnostics
pnpm run open:app
```

Builds sign with the first Developer ID or Apple Development identity in your keychain, so Accessibility access survives rebuilds. `pnpm run release:app` builds the notarized DMG. It needs a Developer ID Application certificate and notary credentials saved as `computer-listen`:

```bash
xcrun notarytool store-credentials computer-listen --apple-id you@example.com --team-id TEAMID
```

See [Architecture](docs/ARCHITECTURE.md) for how it fits together.

## License

[GPL-3.0](LICENSE). You can use, change and share this code, but anything you distribute that's built on it must be open source under the same license.

Audio conversion is adapted from Apple's WWDC25 SpeechAnalyzer sample, which is under its own [MIT-style license](native/APPLE-SAMPLE-LICENSE.txt).
