#!/usr/bin/env bash
# OpenFileSync installer
# Usage: curl -fsSL https://get.openfilesync.runatyr.dev/ | bash

set -euo pipefail

REPO="https://github.com/runatyr1/openfilesync"
INSTALL_DIR="/usr/local/share/openfilesync"
BIN_LINK="/usr/local/bin/ofs"

echo "OpenFileSync Installer"
echo "======================"
echo ""

# Check for root (needed for /usr/local install)
if [[ $EUID -ne 0 ]]; then
    SUDO="sudo"
    echo "Sudo required for installation to ${INSTALL_DIR}"
    sudo -v || { echo "Sudo authentication failed."; exit 1; }
else
    SUDO=""
fi

# --- Dependencies ---

install_rclone() {
    if command -v rclone &>/dev/null; then
        echo "rclone: already installed ($(rclone version --check 2>/dev/null || rclone version | head -1))"
        return
    fi
    echo "Installing rclone..."
    curl -fsSL https://rclone.org/install.sh | $SUDO bash
    echo "rclone: installed"
}

install_inotify_tools() {
    if command -v inotifywait &>/dev/null; then
        echo "inotify-tools: already installed"
        return
    fi
    echo "Installing inotify-tools..."
    if command -v apt-get &>/dev/null; then
        $SUDO apt-get update -qq && $SUDO apt-get install -y -qq inotify-tools
    elif command -v dnf &>/dev/null; then
        $SUDO dnf install -y -q inotify-tools
    elif command -v pacman &>/dev/null; then
        $SUDO pacman -S --noconfirm inotify-tools
    else
        echo "Warning: could not install inotify-tools automatically."
        echo "Install it manually for watch mode support."
        return
    fi
    echo "inotify-tools: installed"
}

echo "-- Checking dependencies --"
install_rclone
install_inotify_tools
echo ""

# --- Install openfilesync ---

echo "-- Installing OpenFileSync --"

if [[ -d "$INSTALL_DIR" ]]; then
    echo "Updating existing installation..."
    $SUDO rm -rf "$INSTALL_DIR"
fi

# Clone or download
if command -v git &>/dev/null; then
    $SUDO git clone --depth 1 "$REPO" "$INSTALL_DIR" 2>/dev/null || {
        echo "Git clone failed, trying tarball download..."
        tmpdir="$(mktemp -d)"
        curl -fsSL "${REPO}/archive/refs/heads/main.tar.gz" -o "${tmpdir}/openfilesync.tar.gz"
        $SUDO mkdir -p "$INSTALL_DIR"
        $SUDO tar xzf "${tmpdir}/openfilesync.tar.gz" -C "$INSTALL_DIR" --strip-components=1
        rm -rf "$tmpdir"
    }
else
    tmpdir="$(mktemp -d)"
    curl -fsSL "${REPO}/archive/refs/heads/main.tar.gz" -o "${tmpdir}/openfilesync.tar.gz"
    $SUDO mkdir -p "$INSTALL_DIR"
    $SUDO tar xzf "${tmpdir}/openfilesync.tar.gz" -C "$INSTALL_DIR" --strip-components=1
    rm -rf "$tmpdir"
fi

$SUDO chmod +x "${INSTALL_DIR}/bin/ofs"
$SUDO ln -sf "${INSTALL_DIR}/bin/ofs" "$BIN_LINK"

echo "Installed to ${INSTALL_DIR}"
echo "Binary linked at ${BIN_LINK}"
echo ""

# --- Post-install: rebuild filters, resync, restart service (updates only) ---

CONFIG_DIR="${HOME}/.config/openfilesync"
if [[ -f "${CONFIG_DIR}/openfilesync.conf" ]]; then
    echo "-- Existing config detected, applying updates --"

    # Clear stale lock files (ours + rclone's)
    rm -f "${HOME}/.local/share/openfilesync/lock"
    find "${HOME}/.cache/rclone/bisync/" -name '*.lck' -delete 2>/dev/null || true

    echo "Rebuilding filters..."
    "${BIN_LINK}" sync --resync 2>&1 || true
    echo ""
    echo "Reinstalling service..."
    "${BIN_LINK}" install-service 2>&1 || true
    echo ""
    echo "Update complete!"
else
    echo "Installation complete!"
    echo ""
    echo "Next step: run 'ofs init' to set up your sync."
fi
echo ""
