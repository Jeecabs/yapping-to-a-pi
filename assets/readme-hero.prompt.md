# README speaker poster

Generated with the built-in `image_gen` tool on 2026-10-24 in image-edit mode.
Output: [readme-hero.png](readme-hero.png), opaque 1774 × 887 PNG, copied unchanged from the generated original.

The selected source is [02-speaker.png](readme-options/02-speaker.png). Its [original generation prompt](readme-options/prompts.md#02-speaker-poster) is preserved. Two edits remove the small product name beneath the headline, then the floating editor window.

## Edit 1: remove the product name

Intermediate output: [02-speaker-no-name.png](readme-options/02-speaker-no-name.png).

```text
Use case: precise-object-edit.
Asset type: final GitHub README banner.
Input image: Image 1 is the EDIT TARGET, the selected speaker poster.
Primary request: Remove only the small lime monospaced words "computer, listen" from the bottom-left corner. Fill their former area with the surrounding dark charcoal background, matching its subtle grain and horizontal ruled lines seamlessly. Leave that area empty.
Invariants: Keep the giant silver-white headline exactly "you talk." / "your mac" / "types." with its existing typography, line breaks, spacing and position. Preserve the speaker, lime woofer, coarse dithering, small editor window, cursor, colors, crop and overall composition unchanged. Do not add any replacement text, logo or decoration. Keep the opaque background and 2:1 landscape dimensions. Make only this small text removal.
```

## Edit 2: remove the editor window

Input: [02-speaker-no-name.png](readme-options/02-speaker-no-name.png).
Final output: [readme-hero.png](readme-hero.png).

```text
Use case: precise-object-edit.
Asset type: final GitHub README speaker poster.
Input image: Image 1 is the EDIT TARGET, the approved speaker poster after its small product name was removed.
Primary request: Remove the entire small floating editor window from the bottom-right corner, including its border, title bar, tiny controls, grey text-line shapes, lime cursor and shadow. Reconstruct what it covered: continue the speaker's lower-right cabinet and circular rim naturally, with matching coarse white-and-lime dithering, then the dark charcoal ruled background beyond the speaker. No rectangular patch or replacement object should remain.
Invariants: Keep the giant silver-white headline exactly "you talk." / "your mac" / "types." with the same typography, line breaks, position and spacing. Preserve the existing speaker silhouette, tweeter, lime woofer, coarse dither texture, dark green-charcoal palette, horizontal rules, crop and composition. The small product name at bottom-left has already been removed and must stay absent. Change only the former window area and its immediate edges. No new text, logo, cursor, frame, UI or decoration. Keep the opaque 2:1 landscape format.
```
