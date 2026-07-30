#!/bin/bash
# ---------------------------------------------------------------------------
# record_scenario.sh
#
# Wrapper qui lance un scenario autopilot dans Xvfb et enregistre une vidéo
# MP4 avec ffmpeg. C'est le point d'entrée public — tout le reste est
# délégué au script interne _record_inside_xvfb.sh qui tourne dans le
# framebuffer virtuel.
#
# Usage :
#   ./tools/record_scenario.sh <scenario.txt> [width] [height] [output.mp4]
#
# Exemples :
#   ./tools/record_scenario.sh docs/scenario/demo.txt
#   ./tools/record_scenario.sh docs/scenario/FM_GS.txt 1920 1080 demo.mp4
#
# Variables d'environnement :
#   GETSOMEPUZZLE_BIN  — alternative au binaire par défaut
#                        (default: build/linux/x64/release/bundle/getsomepuzzle)
# ---------------------------------------------------------------------------
set -euo pipefail

SCENARIO="${1:?Usage: $0 <scenario.txt> [width] [height] [output.mp4]}"

export SCENARIO
export WIDTH="${2:-1280}"
export HEIGHT="${3:-720}"
export OUTPUT="${4:-${SCENARIO%.txt}.mp4}"
export APP="${GETSOMEPUZZLE_BIN:-build/linux/x64/release/bundle/getsomepuzzle}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "→ Scénario  : $SCENARIO"
echo "→ Résolution: ${WIDTH}x${HEIGHT}"
echo "→ Sortie    : $OUTPUT"
echo "→ Binaire   : $APP"
echo

xvfb-run -a -s "-screen 0 ${WIDTH}x${HEIGHT}x24 -nocursor" \
  "$SCRIPT_DIR/_record_inside_xvfb.sh"

echo
echo "--- Résultat ---"
ffprobe "$OUTPUT" 2>&1 | grep -E "Stream|Duration" || true
du -h "$OUTPUT"
echo "✓ $OUTPUT"
