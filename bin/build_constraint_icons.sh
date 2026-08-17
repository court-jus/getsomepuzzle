#!/usr/bin/env bash
# Regenerate the static constraint icons used by the website from the
# same preview widgets the in-editor constraint-type picker uses.
#
# Reads:  lib/widgets/constraints/registry.dart  (constraintUIRegistry)
# Writes: assets/constraint_icons/<slug>.png        (light theme, 128px)
#         assets/constraint_icons/<slug>-dark.png   (dark theme, 128px)
#
# Run from the repo root after editing a preview widget or adding a new
# constraint slug to the UI registry:
#   bin/build_constraint_icons.sh
#
# Requires a Linux Flutter desktop device. On a headless machine (e.g. CI)
# it is wrapped in xvfb-run — same requirement as the marketing
# screenshots, see marketing/README.md.

set -euo pipefail

if [[ ! -f pubspec.yaml ]] || [[ ! -d assets ]]; then
  echo "Run this script from the repo root (couldn't find pubspec.yaml + assets/)." >&2
  exit 1
fi

if [[ -n "${DISPLAY:-}" ]]; then
  flutter test integration_test/constraint_icons_test.dart -d linux
else
  xvfb-run -a flutter test integration_test/constraint_icons_test.dart -d linux
fi