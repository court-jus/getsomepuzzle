#!/usr/bin/env bash
# Build a single PDF of every doc referenced from docs/dev/index.md
# (plus index.md itself, as the leading section).
#
# Reads:  docs/dev/index.md + every .md it links to
#         docs/dev/pandoc_links.lua (cross-link rewriter)
# Writes: docs/dev/devdocs.pdf
#
# Run from the repo root after editing one of the docs:
#   bin/build_dev_docs_pdf.sh
#
# Requires pandoc 3+, lualatex, and a few texlive packages:
#   texlive-luatex texlive-latex-extra texlive-fonts-recommended fonts-noto fonts-symbola

set -euo pipefail

for tool in pandoc lualatex luaotfload-tool; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool not found in PATH." >&2
    echo "Install: sudo apt install pandoc texlive-luatex texlive-latex-extra texlive-fonts-recommended fonts-noto fonts-symbola" >&2
    echo "(texlive-luatex is the one that ships luaotfload + fontspec for lualatex;" >&2
    echo " the lualatex binary alone, from texlive-binaries, is not enough.)" >&2
    exit 1
  fi
done

if [[ ! -f pubspec.yaml ]] || [[ ! -f docs/dev/index.md ]]; then
  echo "Run this script from the repo root (couldn't find pubspec.yaml + docs/dev/index.md)." >&2
  exit 1
fi

# index.md leads, then the docs it links to (in editorial order).
files=( docs/dev/index.md )
while IFS= read -r f; do files+=( "$f" ); done < <(
  grep -oE '\[`[^`]+\.md`\]\([^)]+\.md\)' docs/dev/index.md \
  | sed -E 's/.*\(([^)]+)\)/docs\/dev\/\1/' \
  | awk '!seen[$0]++'
)

meta=$(mktemp --suffix=.yaml)
trap 'rm -f "$meta"' EXIT
cat >"$meta" <<'YAML'
mainfontfallback:
  - "Noto Sans"
  - "Noto Sans Symbols 2"
  - "Symbola"
monofontfallback:
  - "Noto Sans Mono"
  - "Symbola"
YAML

echo "Building PDF from ${#files[@]} docs..."
pandoc \
  --from=gfm \
  --pdf-engine=lualatex \
  --toc --toc-depth=2 \
  --number-sections \
  --lua-filter=docs/dev/pandoc_links.lua \
  --metadata-file="$meta" \
  --metadata=title="Get Some Puzzle — developer documentation" \
  --metadata=lang=en \
  -V geometry:margin=2cm \
  -V mainfont="DejaVu Serif" \
  -V monofont="DejaVu Sans Mono" \
  -V colorlinks=true \
  -V linkcolor=teal \
  -V urlcolor=teal \
  -V toccolor=black \
  "${files[@]}" \
  -o docs/dev/devdocs.pdf

echo "Done. PDF written to docs/dev/devdocs.pdf"
