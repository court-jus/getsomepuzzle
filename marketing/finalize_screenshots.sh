#!/usr/bin/env bash
# Downsample raw screenshots to exact store dimensions and copy them
# into the tracked tree.
#
# Reads:  marketing/screenshots/raw/<locale>/<device>/<NN>_<name>.png
#         (2× supersample of each store's target spec)
# Writes: marketing/screenshots/<locale>/<device>/<NN>_<name>.png
#         (exact store dimensions, 50% size of source)
#
# Run from the repo root after the capture suite has produced raw PNGs:
#   xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux
#   marketing/finalize_screenshots.sh
#
# Optional first arg restricts processing to a single locale (en/fr/es)
# or a single locale/device path under raw/, e.g.:
#   marketing/finalize_screenshots.sh fr
#   marketing/finalize_screenshots.sh fr/iphone_67

set -euo pipefail

raw_root="marketing/screenshots/raw"
final_root="marketing/screenshots"

if [[ ! -d "$raw_root" ]]; then
  echo "No raw screenshots found at $raw_root — run the capture suite first:" >&2
  echo "  xvfb-run -a flutter test integration_test/screenshots_test.dart -d linux" >&2
  exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick (magick) not found in PATH." >&2
  exit 1
fi

scope="${1:-}"
src_root="$raw_root"
if [[ -n "$scope" ]]; then
  src_root="$raw_root/$scope"
  if [[ ! -d "$src_root" ]]; then
    echo "Scope '$scope' resolves to $src_root, which does not exist." >&2
    exit 1
  fi
fi

count=0
while IFS= read -r -d '' src; do
  rel="${src#$raw_root/}"
  dst="$final_root/$rel"
  mkdir -p "$(dirname "$dst")"
  magick "$src" -resize 50% "$dst"
  printf '  %s\n' "$dst"
  count=$((count + 1))
done < <(find "$src_root" -type f -name '*.png' -print0 | sort -z)

echo "Wrote $count finalized screenshots under $final_root/"
