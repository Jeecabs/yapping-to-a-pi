# computer, listen artwork

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
