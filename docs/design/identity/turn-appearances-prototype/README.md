# Turn appearance prototype

Turn is the user's selected shape from the second icon study. These files
explore its light, dark, and system-tinted appearances before app integration.

Open `index.html` directly, or serve this directory with a local HTTP server.
Switch the rendering generation using the bottom bar; the colour swatches
change both tinted previews. The displayed images are native Apple renders.

## Source

`Turn.icon` is an editable Icon Composer document with a page background and
two SVG layers. Geometry matches A2 in `../icon-refinements-prototype.html`.
The square SVG canvases are unmasked; the system supplies the icon mask.
No highlights, outlines, or shadows are drawn into the source artwork.
The native renderer can add its own enclosure treatment.

| Part | Default | Dark | Monochrome annotation |
| --- | --- | --- | --- |
| Page | `#F6F2EC` | `#28231F` | `#141414` |
| Fold | `#AB9982` | `#BBAA94` | `#FFFFFF` |
| Under-page | `#241F1B` | `#0E0C0A` | `#383838` |

Icon Composer calls the monochrome appearance **Mono** in its UI and encodes
it as `tinted` in `icon.json`. The system derives tinted light and tinted
dark from this one annotation. The colours in the preview are sample user
tint choices, not separately shipped colour assets.

## Rebuild the previews

```sh
python3 docs/design/identity/turn-appearances-prototype/render.py
```

Requires Xcode 27 with Icon Composer 27. The script uses the Icon Composer
app's `Contents/Executables/ictool`, whose export interface differs from
`xcrun ictool`. It renders iOS design generations 26 and 27 at 512 pixels,
60 points at 2x, and 32 points at 2x, then creates the download archive.
`render-manifest.json` records the renderer version and each output.

## Verification

- Native rendering of Default, Dark, TintedLight and TintedDark.
- Copper, green, blue and violet tint choices in both tinted appearances.
- Separate native exports for 60 pt and 32 pt, not just browser reductions.
- `actool` compilation passed for iPhone and iPad with iOS 26.0 as minimum.
  It produced `Assets.car`, an icon information plist, and iPhone/iPad PNGs.
- No simulator was booted. No app installation or physical-device check.
- This document is not yet included in the Aujour app target.

Compilation used:

```sh
mkdir -p /tmp/aujour-turn-icon-compiled
xcrun actool docs/design/identity/turn-appearances-prototype/Turn.icon \
  --compile /tmp/aujour-turn-icon-compiled --platform iphonesimulator \
  --minimum-deployment-target 26.0 --target-device iphone --target-device ipad \
  --app-icon Turn --output-partial-info-plist /tmp/aujour-turn-icon-compiled/Info.plist \
  --output-format human-readable-text --warnings --notices
```

Apple references:

- [Creating an icon with Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
- [App icon design guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Icon Composer group lab: monochrome contrast](https://developer.apple.com/videos/play/wwdc2026/8012/)
