# Marketing assets

Everything that ships outside the app: store-listing texts, icons,
feature graphic. Filled in for English, French and Spanish — the same
three locales the app itself supports.

## Layout

```
marketing/
├── sample_3x3.svg          single source of truth for the launcher icon
├── feature_graphic.svg     1024×500 banner used by the Play Store listing
├── app_icon_1024.png       rendered from sample_3x3.svg via Inkscape
├── icon_512.png            same, downsized to 512px
├── feature_graphic.png     rendered from feature_graphic.svg
├── play_store/
│   ├── en-US/   title, short_description, full_description, changelogs/default
│   ├── fr-FR/   …
│   └── es-ES/   …
└── app_store/
    ├── en-US/   name, subtitle, description, keywords, promotional_text,
    │            release_notes, privacy_url, support_url, marketing_url
    ├── fr-FR/   …
    └── es-ES/   …
```

The directory layout matches what `fastlane supply` (Play) and
`fastlane deliver` (App Store) expect — adopt `fastlane` later and these
files become drop-in metadata.

## Length budgets

| File | Limit | Where it appears |
|------|-------|------------------|
| `play_store/*/title.txt` | 30 chars | App name on the Play Store |
| `play_store/*/short_description.txt` | 80 chars | Card preview on the Play Store |
| `play_store/*/full_description.txt` | 4000 chars | Listing body on the Play Store |
| `play_store/*/changelogs/default.txt` | 500 chars | "What's new" for the Play Store |
| `app_store/*/name.txt` | 30 chars | App name on the App Store |
| `app_store/*/subtitle.txt` | 30 chars | Subtitle on the App Store |
| `app_store/*/description.txt` | 4000 chars | Listing body on the App Store |
| `app_store/*/keywords.txt` | 100 chars | Comma-separated keywords (App Store search) |
| `app_store/*/promotional_text.txt` | 170 chars | Editable without resubmitting (App Store) |
| `app_store/*/release_notes.txt` | 4000 chars | "What's new" for the App Store |

## Image specs

| File | Source | Size | Used by |
|------|--------|------|---------|
| `app_icon_1024.png` | `sample_3x3.svg` | 1024×1024 | `flutter_launcher_icons` (every platform) |
| `icon_512.png` | `sample_3x3.svg` | 512×512 | Play Store listing icon |
| `feature_graphic.png` | `feature_graphic.svg` | 1024×500 | Play Store feature graphic |

App Store wants its own 1024×1024 icon — use `app_icon_1024.png`. iOS
strips the alpha channel automatically through `flutter_launcher_icons`,
but the PNG is already opaque (Inkscape exports with a white background).

### Regenerating the rasters

Always use Inkscape, not ImageMagick — ImageMagick's SVG rasterizer
produces visibly soft output at icon sizes.

```bash
# Launcher icon (1024)
inkscape marketing/sample_3x3.svg \
  --export-type=png --export-filename=marketing/app_icon_1024.png \
  --export-width=1024 --export-height=1024 \
  --export-background=white --export-background-opacity=1

# Play Store icon (512)
inkscape marketing/sample_3x3.svg \
  --export-type=png --export-filename=marketing/icon_512.png \
  --export-width=512 --export-height=512 \
  --export-background=white --export-background-opacity=1

# Play Store feature graphic
inkscape marketing/feature_graphic.svg \
  --export-type=png --export-filename=marketing/feature_graphic.png \
  --export-width=1024 --export-height=500 \
  --export-background=white --export-background-opacity=1
```

After re-rendering `app_icon_1024.png`, run
`dart run flutter_launcher_icons` to fan it out across Android, iOS, web,
Windows.

## Screenshots

Captured from the integration-test harness on Linux. Each scenario is a
regular `testWidgets` body that drives the app to the target screen and
then walks the render tree to grab the topmost
`RenderRepaintBoundary`, writing a PNG straight to
`marketing/screenshots/raw/<locale>_<NN>_<name>.png`. The boilerplate
lives in `integration_test/screenshots_test.dart` (test bodies + capture
helper) and reuses the existing `integration_test/helpers/harness.dart`
for puzzle seeding and SharedPreferences mocking — no separate
`flutter drive` driver is needed.

### Why not `binding.takeScreenshot()`

`IntegrationTestWidgetsFlutterBinding.takeScreenshot()` routes through a
platform channel that isn't implemented on Flutter desktop, so it throws
`MissingPluginException` on Linux. Walking the render tree to a
`RenderRepaintBoundary` and calling `toImage` directly avoids the
channel and works the same on Linux, macOS and Windows hosts.

### Run

```bash
# English (default)
xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux

# French / Spanish — overrides the seeded SharedPreferences locale
LOCALE=fr xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux
LOCALE=es xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux
```

The viewport is set to 1080×1920 at dpr=2 (→ 2160×3840 PNG), large
enough to crop down to any phone aspect ratio in post-processing. The
`marketing/screenshots/raw/` directory is gitignored — once you've
picked the keepers and cropped them to per-store dimensions, drop the
final files in `marketing/screenshots/<locale>/` (tracked).

### Required output (per store)

- **Play Store**: ≥2 phone screenshots; 7" and 10" tablet recommended.
- **App Store**: 6.7" iPhone (1290×2796) + 6.5" iPhone (1242×2688), and
  12.9" iPad (2048×2732) if you target tablets.

### Current scenarios

| File | What it shows |
|------|---------------|
| `<locale>_01_rich_grid.png` | A 5×8 fixture (`_fixture5x8MultiRules`) carrying CC + DF + GS + PA + SY constraints — visual proof that the game runs deeper than single-rule grids. |
| `<locale>_02_drawer.png` | The main drawer open, surfacing browse / generate / create / stats / settings entries. |
| `<locale>_03_help.png` | The help page, top of the constraint catalogue. |
| `<locale>_04_editor_rule_picker.png` | The in-app editor with the constraint-type picker dialog open, listing all 12 rule types. |

### Adding a scenario

Drop another `testWidgets` block in `screenshots_test.dart`, drive the
UI to the screen, call `_capture(tester, '${locale}_NN_name')`. Re-run
the command; the new PNG appears alongside the others.

### Capture implementation

`_capture` rasters the `RenderView`'s root `OffsetLayer` via
`layer.toImage(view.paintBounds, pixelRatio: …)`. The root layer
composites every child layer the user sees — home grid + drawer
overlay + modal dialog stacked the way Flutter actually paints them —
so the screenshot matches what's on screen.

A `RenderRepaintBoundary.toImage` approach was tried first but only
ever sees one subtree at a time: walking DFS-first picks the home
behind the overlay, walking DFS-last picks the overlay alone. Neither
gives the composed view.

## Still missing

- **Final, cropped screenshots** committed under
  `marketing/screenshots/<locale>/`. The capture pipeline above is
  ready, but each raw PNG still needs a quick visual review and a crop
  to the relevant store/device aspect.
- **Promo video**: optional on both stores.

## Tone

The bundled descriptions stay deliberately sober — straightforward
explanations of the gameplay and a short paragraph stating the app is
free, ad-free, tracker-free and open source. Avoid superlatives in
future edits; the differentiator is privacy + clarity, not hype.
