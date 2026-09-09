#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/mmhfarooque/chipsailing-cs9711-fingerprint-linux.git"
BUILD_DIR=$(mktemp -d -t cs9711-build-XXXXXX)

# Clean up temporary cloned files on exit
trap 'echo "==> Cleaning up build workspace..."; rm -rf "$BUILD_DIR"' EXIT

echo "==> Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y \
    git pkg-config \
    libglib2.0-dev libgusb-dev libgudev-1.0-dev libpixman-1-dev libnss3-dev \
    libopencv-dev libopencv-features2d-dev fprintd libpam-fprintd python3-gi gir1.2-gtk-4.0

echo "==> Cloning CS9711 repository into temporary location..."
git clone --depth 1 "$REPO_URL" "$BUILD_DIR/src"

cd "$BUILD_DIR/src"
chmod +x install.sh setup-gui.sh 2>/dev/null || true

echo "==> Executing upstream installer script..."
./install.sh

if [ -f "./setup-gui.sh" ]; then
    echo "==> Setting up GTK4 configuration GUI..."
    sudo ./setup-gui.sh || true
fi

echo "==> Setting udev permissions for CS9711 (2541:0236)..."
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="2541", ATTR{idProduct}=="0236", MODE="0664", GROUP="plugdev", TAG+="uaccess"' | sudo tee /etc/udev/rules.d/70-cs9711-fingerprint.rules > /dev/null

echo "==> Linking libfprint to system path..."
PATCHED_LIB=$(find /usr/local/lib -name "libfprint-2.so.2*" 2>/dev/null | head -n 1)
if [[ -n "$PATCHED_LIB" ]]; then
    sudo ln -sf "$PATCHED_LIB" /usr/lib/x86_64-linux-gnu/libfprint-2.so.2
fi

echo "==> Creating OpenCV .413 ABI compatibility symlinks..."
for lib in /usr/lib/x86_64-linux-gnu/libopencv_*.so.4.10.0; do
    if [ -f "$lib" ]; then
        base=$(echo "$lib" | sed 's/\.so\.4\.10\.0//')
        sudo ln -sf "$lib" "${base}.so.413"
    fi
done

echo "==> Refreshing dynamic library cache and restarting fprintd..."
sudo ldconfig
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo systemctl restart fprintd

echo "==> Installation complete!"

