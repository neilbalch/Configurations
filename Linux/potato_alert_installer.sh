#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/opt/PotatoAlert"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
TMP_DIR=$(mktemp -d)

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "Downloading latest PotatoAlert Linux release..."
# GitHub's /releases/latest/download/ redirects to the newest asset with that exact name
curl -L -o "$TMP_DIR/PotatoAlert.zip" \
  "https://github.com/razaqq/PotatoAlert/releases/latest/download/PotatoAlert_linux.zip"

echo "Extracting..."
unzip -q "$TMP_DIR/PotatoAlert.zip" -d "$TMP_DIR"

# Clean install into a user-local directory (avoids needing root)
mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$DESKTOP_DIR"
rm -rf "$INSTALL_DIR"/*
cp -a "$TMP_DIR/PotatoAlert" "$INSTALL_DIR/"

# Symlink so the binary is on PATH without copying it into ~/bin
ln -sf "$INSTALL_DIR/PotatoAlert" "$BIN_DIR/PotatoAlert"
chmod +x "$BIN_DIR/PotatoAlert"

# .desktop file is what KDE scans to populate the menu and KRunner
cat > "$DESKTOP_DIR/potatoalert.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=PotatoAlert
Comment=World of Warships matchmaking monitor
Exec=$BIN_DIR/PotatoAlert
Icon=applications-games
Terminal=false
Categories=Game;Utility;
StartupWMClass=PotatoAlert
EOF

chmod +x "$DESKTOP_DIR/potatoalert.desktop"

# Rebuild KDE's application cache so the new .desktop file is noticed immediately
# (Plasma 6 uses kbuildsycoca6; older Plasma 5 used kbuildsycoca5)
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental &>/dev/null || true
command -v kbuildsycoca5 >/dev/null && kbuildsycoca5 --noincremental &>/dev/null || true

echo "Done. PotatoAlert is now available in your menu and PATH."
