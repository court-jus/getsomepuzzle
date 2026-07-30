#!/bin/bash
# ---------------------------------------------------------------------------
# _record_inside_xvfb.sh   (interne — ne pas appeler directement)
#
# Tourne dans l'environnement Xvfb créé par record_scenario.sh.
# Reçoit les paramètres via les variables d'environnement exportées par
# le wrapper (SCENARIO, WIDTH, HEIGHT, OUTPUT, APP).
# ---------------------------------------------------------------------------
set -euo pipefail

echo "→ Xvfb : $DISPLAY (${WIDTH}x${HEIGHT})"

# --- Boucle de retry (max 3×) pour absorber les segfaults OpenGL sous Xvfb ---
MAX_RETRIES=3
RETRY_DELAY=3
EXIT_CODE=0

for ATTEMPT in $(seq 1 $MAX_RETRIES); do
  echo "→ Tentative $ATTEMPT/$MAX_RETRIES"

  # Démarrer ffmpeg
  ffmpeg -loglevel warning \
    -f x11grab -video_size "${WIDTH}x${HEIGHT}" -framerate 30 \
    -draw_mouse 0 -i "${DISPLAY}.0" \
    -c:v libx264 -preset fast -crf 23 -pix_fmt yuv420p \
    -y "$OUTPUT" &
  FFPID=$!
  sleep 0.5
  echo "✓ ffmpeg recording (pid $FFPID)"

  # Lancer l'application (bloquant — quitte automatiquement à la fin du scénario)
  echo "→ Lancement du scénario \"$SCENARIO\"..."
  set +e  # autoriser un code de sortie non‑nul pour le retry
  WAYLAND_DISPLAY= GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 \
    "$APP" \
    --scenario="$SCENARIO" \
    --width="$WIDTH" \
    --height="$HEIGHT" \
    --no-onboarding \
    --lang=en
  EXIT_CODE=$?
  set -e

  # Succès → fin de la boucle
  if [ $EXIT_CODE -eq 0 ]; then
    echo "→ Scénario terminé"
    # Laisser ffmpeg encoder les dernières frames
    sleep 2
    kill "$FFPID" 2>/dev/null || true
    wait "$FFPID" 2>/dev/null || true
    echo "✓ Enregistrement terminé"
    exit 0
  fi

  # Échec → nettoyer ffmpeg avant de réessayer
  kill "$FFPID" 2>/dev/null || true
  wait "$FFPID" 2>/dev/null || true

  if [ $EXIT_CODE -eq 139 ]; then
    echo "⚠️  Segmentation fault (tentative $ATTEMPT/$MAX_RETRIES)"
  else
    echo "⚠️  L'application a quitté avec le code $EXIT_CODE (tentative $ATTEMPT/$MAX_RETRIES)"
  fi

  if [ $ATTEMPT -lt $MAX_RETRIES ]; then
    echo "→ Nouvelle tentative dans ${RETRY_DELAY}s..."
    sleep $RETRY_DELAY
  fi
done

# Toutes les tentatives ont échoué
echo "❌ Échec après $MAX_RETRIES tentatives"
exit 1
