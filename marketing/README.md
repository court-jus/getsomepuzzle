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

## Still missing

- **Screenshots**: phone (Play: ≥2; App Store: 6.7" + 6.5") and tablet
  sets, in each of the three locales. Capture from real devices/simulators
  once a signed build exists.
- **Promo video**: optional on both stores.

## Tone

The bundled descriptions stay deliberately sober — straightforward
explanations of the gameplay and a short paragraph stating the app is
free, ad-free, tracker-free and open source. Avoid superlatives in
future edits; the differentiator is privacy + clarity, not hype.
