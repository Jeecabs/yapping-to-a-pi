# computer, listen artwork

## App icon

`AppIcon.png` is the transparent 1024 × 1024 master. A silver-white `c` and lime comma sit on a flat graphite tile. Both glyphs use the actual Helvetica Neue Bold outlines.

Render it on macOS with:

```sh
xcrun swift scripts/render-app-icon.swift
```

The renderer uses Core Text glyph paths, SwiftUI continuous corners and a Core Graphics sRGB canvas. It requires HelveticaNeue-Bold and refuses font substitution. No generated imagery, texture or shadow is used.

| Element | Specification |
| --- | --- |
| Tile | 824 × 824 px, centered with 100 px transparent margins |
| Corners | Continuous, 185 px radius |
| Graphite | `#181B18` |
| Silver-white | `#EDF1E8` |
| Lime | `#D5F66B` |
| Lettering | HelveticaNeue-Bold, fitted as one group, at least 18% padding inside the tile |

`scripts/build-app.mjs` resizes the master into the complete macOS icon family and embeds both `AppIcon.png` and `AppIcon.icns`. App views that use `AppIcon` load this PNG. The menu bar uses a monochrome `c,` glyph in `YappingApp.swift`.

The deterministic master replaces the image-generated version on 2026-10-11. Palette, fonts and interface styles live in `native/Sources/YappingToAPiApp/Brand.swift`.

## README illustration

`readme-hero.png` is the selected 1774 × 887 speaker poster. Its oversized headline and dithered lime speaker follow the website's visual style. The small product name and floating editor window were removed from the final banner.

Generated with the built-in imagegen tool. The exact prompt is saved in [readme-hero.prompt.md](readme-hero.prompt.md).

Three website-inspired alternatives are saved in `readme-options/`:

| Option | Direction |
| --- | --- |
| [01. Desktop collage](readme-options/01-desktop.png) | Oversized wordmark, floating windows and a dithered speaker |
| [02. Speaker poster](readme-options/02-speaker.png) | A bold headline and enlarged lime speaker |
| [03. Pedalboard](readme-options/03-pedalboard.png) | Colourful effects pedals beneath the website's cleanup headline |

All three are 1774 × 887 PNGs. Their [exact prompts and reference notes](readme-options/prompts.md) are saved alongside them.

The first illustration and its prompt are archived as [00-initial.png](readme-options/00-initial.png) and [00-initial.prompt.md](readme-options/00-initial.prompt.md).
