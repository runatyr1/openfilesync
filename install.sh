#!/usr/bin/env bash
# OpenFileSync installer
# Usage: curl -fsSL https://get.openfilesync.runatyr.dev/ | bash

set -euo pipefail

REPO="https://github.com/runatyr/openfilesync"
INSTALL_DIR="/usr/local/share/openfilesync"
BIN_LINK="/usr/local/bin/openfilesync"

echo "OpenFileSync Installer"
echo "======================"
echo ""

# Check for root (needed for /usr/local install)
if [[ $EUID -ne 0 ]]; then
    SUDO="sudo"
    echo "Will use sudo for installation to ${INSTALL_DIR}"
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

echo "-- Installing openfilesync --"

if [[ -d "$INSTALL_DIR" ]]; then
    echo "Updating existing installation..."
    $SUDO rm -rf "$INSTALL_DIR"
fi

# Clone or download
if command -v git &>/dev/null; then
    $SUDO git clone --depth 1 "$REPO" "$INSTALL_DIR" 2>/dev/null || {
        # Fallback: download tarball
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

$SUDO chmod +x "${INSTALL_DIR}/bin/openfilesync"
$SUDO ln -sf "${INSTALL_DIR}/bin/openfilesync" "$BIN_LINK"

echo "Installed to ${INSTALL_DIR}"
echo "Binary linked at ${BIN_LINK}"
echo ""

# --- Done ---

echo "Installation complete!"
echo ""
echo "Next step: run 'openfilesync init' to set up your sync."
echo ""
