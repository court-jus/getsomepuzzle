#!/usr/bin/env bash
# Regenerate every store / launcher icon and the Play Store feature
# graphic from their SVG sources.
#
# Reads:  marketing/sample_3x3.svg       (3x3 puzzle illustration, full-bleed)
#         marketing/feature_graphic.svg  (1024x500 Play Store banner)
# Writes: marketing/app_icon_1024.png    (1024x1024, source for flutter_launcher_icons)
#         marketing/icon_512.png         (512x512, Play Store listing icon)
#         marketing/feature_graphic.png  (1024x500, Play Store feature graphic)
#         android/app/src/main/res/mipmap-* / ios/Runner/Assets.xcassets / web/icons / windows/runner/resources
#                                        (fanned out by flutter_launcher_icons from app_icon_1024.png)
#
# Run from the repo root after editing one of the source SVGs:
#   bin/build_icons.sh
#
# Requires Inkscape on PATH. Inkscape (not ImageMagick) is mandatory for
# the SVG -> PNG step: ImageMagick gives a blurry result on these stroked
# vector icons.

set -euo pipefail

if ! command -v inkscape >/dev/null 2>&1; then
  echo "inkscape not found in PATH." >&2
  echo "Install it from https://inkscape.org/ (ImageMagick is NOT a substitute — it produces blurry output on these SVGs)." >&2
  exit 1
fi

if [[ ! -f pubspec.yaml ]] || [[ ! -d marketing ]]; then
  echo "Run this script from the repo root (couldn't find pubspec.yaml + marketing/)." >&2
  exit 1
fi

render() {
  local src="$1" dst="$2" w="$3" h="$4"
  echo "  inkscape $src -> $dst (${w}x${h})"
  inkscape "$src" \
    --export-type=png \
    --export-filename="$dst" \
    --export-width="$w" \
    --export-height="$h" \
    >/dev/null
}

echo "Rasterizing SVG sources with Inkscape..."
render marketing/sample_3x3.svg      marketing/app_icon_1024.png   1024 1024
render marketing/sample_3x3.svg      marketing/icon_512.png         512  512
render marketing/feature_graphic.svg marketing/feature_graphic.png 1024  500

echo "Fanning out app_icon_1024.png to every platform via flutter_launcher_icons..."
dart run flutter_launcher_icons

cat <<'NOTE'

Done.

Manual follow-up (flutter_launcher_icons doesn't cover it):
  - Refresh web/favicon.png by copying web/icons/Icon-192.png over it.
NOTE
