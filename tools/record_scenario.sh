#!/bin/bash
# ---------------------------------------------------------------------------
# record_scenario.sh
#
# Wrapper qui lance un scenario autopilot dans Xvfb. Par défaut il enregistre
# une vidéo MP4 avec ffmpeg ; avec --screenshots il laisse l'application
# écrire des PNG aux points marqués par l'action `screenshot` du scénario
# (au lieu de générer une vidéo). C'est le point d'entrée public — tout le
# reste est délégué au script interne _record_inside_xvfb.sh qui tourne dans
# le framebuffer virtuel.
#
# Usage :
#   ./tools/record_scenario.sh <scenario.txt> [width] [height] [output.mp4] [--screenshots]
#
# Exemples :
#   ./tools/record_scenario.sh docs/scenario/demo.txt
#   ./tools/record_scenario.sh docs/scenario/FM_GS.txt 1920 1080 demo.mp4
#   ./tools/record_scenario.sh docs/scenario/demo.txt --screenshots
#
# En mode --screenshots les images sont écrites à côté du scénario :
#   docs/scenario/demo_01.png, demo_02.png, …
#
# Variables d'environnement :
#   GETSOMEPUZZLE_BIN  — alternative au binaire par défaut
#                        (default: build/linux/x64/release/bundle/getsomepuzzle)
# ---------------------------------------------------------------------------
set -euo pipefail

SCREENSHOTS=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --screenshots) SCREENSHOTS=1 ;;
    -*)
      echo "Option inconnue : $arg" >&2
      echo "Usage: $0 <scenario.txt> [width] [height] [output.mp4] [--screenshots]" >&2
      exit 2
      ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

SCENARIO="${POSITIONAL[0]:-}"
if [ -z "$SCENARIO" ]; then
  echo "Usage: $0 <scenario.txt> [width] [height] [output.mp4] [--screenshots]" >&2
  exit 2
fi

export SCENARIO
export SCREENSHOTS
export WIDTH="${POSITIONAL[1]:-1280}"
export HEIGHT="${POSITIONAL[2]:-720}"
export OUTPUT="${POSITIONAL[3]:-${SCENARIO%.txt}.mp4}"
export APP="${GETSOMEPUZZLE_BIN:-build/linux/x64/release/bundle/getsomepuzzle}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "→ Scénario  : $SCENARIO"
echo "→ Résolution: ${WIDTH}x${HEIGHT}"
if [ "$SCREENSHOTS" -eq 1 ]; then
  echo "→ Sortie    : ${SCENARIO%.txt}_01.png, _02.png, …"
else
  echo "→ Sortie    : $OUTPUT"
fi
echo "→ Binaire   : $APP"
echo

xvfb-run -a -s "-screen 0 ${WIDTH}x${HEIGHT}x24 -nocursor" \
  "$SCRIPT_DIR/_record_inside_xvfb.sh"

echo
echo "--- Résultat ---"
if [ "$SCREENSHOTS" -eq 1 ]; then
  ls -1 "${SCENARIO%.txt}"_*.png 2>/dev/null || echo "⚠️  Aucun PNG produit"
else
  ffprobe "$OUTPUT" 2>&1 | grep -E "Stream|Duration" || true
  du -h "$OUTPUT"
  echo "✓ $OUTPUT"
fi
