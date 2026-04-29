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
SRC_DESKTOP="$SCRIPT_DIR/$DESKTOP_NAME"
DEST_DIR="$HOME/.local/share/applications"
DEST_DESKTOP="$DEST_DIR/$DESKTOP_NAME"
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

mkdir -p "$DEST_DIR"

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
