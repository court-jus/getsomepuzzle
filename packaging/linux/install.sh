#!/usr/bin/env bash
# Per-user install of the Get Some Puzzle desktop entry. Registers the
# `getsomepuzzle://` URL scheme so links from email clients / share sheets
# open the native app.
#
# Usage:
#   ./install.sh            install for the current user
#   ./install.sh --bin PATH override the binary path written into Exec=
#   ./install.sh --uninstall remove the desktop entry and the scheme handler

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." &> /dev/null && pwd)"
DESKTOP_NAME="getsomepuzzle.desktop"
ICON_NAME="getsomepuzzle"
SRC_DESKTOP="$SCRIPT_DIR/$DESKTOP_NAME"
SRC_ICON="$REPO_ROOT/marketing/sample_3x3.svg"
DEST_DIR="$HOME/.local/share/applications"
DEST_DESKTOP="$DEST_DIR/$DESKTOP_NAME"
ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
DEST_ICON="$ICON_DIR/$ICON_NAME.svg"
DEFAULT_BIN="$REPO_ROOT/build/linux/x64/release/bundle/getsomepuzzle"

usage() {
    sed -n '2,9p' "${BASH_SOURCE[0]}"
    exit 1
}

uninstall() {
    if [[ -f "$DEST_DESKTOP" ]]; then
        rm -f "$DEST_DESKTOP"
        echo "Removed $DEST_DESKTOP"
    else
        echo "No desktop entry to remove."
    fi
    if [[ -f "$DEST_ICON" ]]; then
        rm -f "$DEST_ICON"
        echo "Removed $DEST_ICON"
        if command -v gtk-update-icon-cache &> /dev/null; then
            gtk-update-icon-cache --force --quiet "$HOME/.local/share/icons/hicolor" || true
        fi
    fi
    if command -v update-desktop-database &> /dev/null; then
        update-desktop-database "$DEST_DIR" || true
    fi
    echo "Done. The getsomepuzzle:// scheme is no longer routed to the app."
}

mode="install"
bin_path=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall) mode="uninstall"; shift;;
        --bin) bin_path="${2:-}"; shift 2;;
        -h | --help) usage;;
        *) echo "Unknown argument: $1" >&2; usage;;
    esac
done

if [[ "$mode" == "uninstall" ]]; then
    uninstall
    exit 0
fi

if [[ -z "$bin_path" ]]; then
    bin_path="$DEFAULT_BIN"
fi

if [[ ! -x "$bin_path" ]]; then
    echo "ERROR: binary not found or not executable: $bin_path" >&2
    echo "Build it first: flutter build linux --release" >&2
    echo "Or pass a custom path: $0 --bin /path/to/getsomepuzzle" >&2
    exit 1
fi

mkdir -p "$DEST_DIR" "$ICON_DIR"

# Install the launcher icon at the XDG location matching `Icon=getsomepuzzle`
# in the .desktop file. Using the scalable SVG avoids shipping a fan-out of
# raster sizes — every modern desktop environment renders it natively.
if [[ -f "$SRC_ICON" ]]; then
    install -m 644 "$SRC_ICON" "$DEST_ICON"
    echo "Installed $DEST_ICON"
    if command -v gtk-update-icon-cache &> /dev/null; then
        gtk-update-icon-cache --force --quiet "$HOME/.local/share/icons/hicolor" || true
    fi
else
    echo "WARNING: source icon not found at $SRC_ICON — desktop entry will fall back to a generic icon." >&2
fi

# Patch the Exec= line so the desktop entry points at the user's actual
# binary instead of the /usr/local/bin placeholder shipped in the repo.
sed "s|^Exec=.*|Exec=$bin_path %u|" "$SRC_DESKTOP" > "$DEST_DESKTOP"
chmod 644 "$DEST_DESKTOP"
echo "Installed $DEST_DESKTOP (Exec=$bin_path %u)"

if command -v update-desktop-database &> /dev/null; then
    update-desktop-database "$DEST_DIR"
    echo "Refreshed user desktop database."
else
    echo "Note: update-desktop-database not found; you may need to log out/in."
fi

if command -v xdg-mime &> /dev/null; then
    xdg-mime default "$DESKTOP_NAME" x-scheme-handler/getsomepuzzle
    echo "Registered getsomepuzzle:// scheme handler."
else
    echo "Note: xdg-mime not found; the scheme association may not stick." >&2
fi

cat <<EOF

Done. Test with:
    xdg-open 'getsomepuzzle://?puzzle=v2_12_3x3_100000000_FM:11_0:0_0'
EOF
