#!/usr/bin/env bash
# Download and install the free (lite) DaVinci Resolve Linux build.
#
# Blackmagic does not publish a stable file URL. The script asks their version
# API for the current free Linux build, posts the download form, and fetches
# the signed zip URL from that response. The name, email, and address below
# are placeholders so the form accepts the request. They are not an account.
#
# The .run installer is an AppImage. Ubuntu 26.04 ships the libraries it needs
# under t64 package names, and its package check still looks for the old names,
# so the installer is started with SKIP_PACKAGE_CHECK=1. Do not install the
# "fuse" package: it replaces FUSE 3 and can remove kubuntu-desktop.
#
# Leave /opt/resolve/libs alone. This machine's manual install runs with the
# bundled glib still in place.

set -euo pipefail

version_url="https://www.blackmagicdesign.com/api/support/latest-stable-version/davinci-resolve/linux"
refer_id="dfd43085ef224766b06b579ce8a6d097"
user_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
# Reserved example address. 202-555-0194 is a fictional NANP number.
registration='{"firstname":"Linux","lastname":"User","email":"resolve@example.com","phone":"202-555-0194","country":"us","street":"1 Market St","state":"California","city":"San Francisco","product":"DaVinci Resolve"}'

force=false
local_file=""
work=""

usage() {
    cat <<'EOF'
Usage: install-davinci-resolve.sh [--force] [--file ZIP_OR_RUN]

  Downloads the latest free DaVinci Resolve for Linux and runs its installer.
  Does nothing when that version is already installed.

  --force          Download and run the installer even if this version is installed
  --file PATH      Install this .zip or .run instead of downloading
EOF
}

cleanup() {
    if [[ -n "$work" && -d "$work" ]]; then
        rm -rf "$work"
    fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) force=true ;;
        --file)
            shift
            [[ $# -gt 0 ]] || { echo "[!] --file needs a path." >&2; exit 1; }
            local_file="$1"
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[!] Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "[!] The Linux build of DaVinci Resolve is x86_64 only." >&2
    exit 1
fi

if ! command -v curl >/dev/null || ! command -v python3 >/dev/null; then
    echo "[*] Installing curl and python3..."
    sudo apt update
    sudo apt install -y curl ca-certificates python3
fi

# major minor release, or empty if Resolve is not installed.
# Prints "studio" if the installed build is Studio.
installed_release() {
    local bin="/opt/resolve/bin/resolve"
    [[ -f "$bin" ]] || return 0
    python3 - "$bin" <<'PY'
import mmap, re, sys
path = sys.argv[1]
with open(path, "rb") as handle:
    mapping = mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ)
lite = re.search(br"(\d+)\.(\d+)\.(\d+)\.\d+_lite", mapping)
studio = re.search(br"(\d+)\.(\d+)\.(\d+)\.\d+_studio", mapping)
if studio and not lite:
    print("studio")
elif lite:
    print(lite.group(1).decode(), lite.group(2).decode(), lite.group(3).decode())
PY
}

echo "=== DaVinci Resolve Linux install ==="

if [[ -z "$local_file" ]]; then
    echo "[*] Checking the latest free Linux release..."
    release_json=$(curl -fsSL -A "$user_agent" -H "Accept: application/json" "$version_url")
    mapfile -t release_fields < <(printf '%s' "$release_json" | python3 -c '
import json, sys
linux = json.load(sys.stdin)["linux"]
print(int(linux["major"]))
print(int(linux["minor"]))
print(int(linux["releaseNum"]))
print(int(linux["build"]))
print(linux["downloadId"])
')
    latest_major=${release_fields[0]}
    latest_minor=${release_fields[1]}
    latest_release=${release_fields[2]}
    latest_build=${release_fields[3]}
    download_id=${release_fields[4]}
    if (( latest_release == 0 )); then
        latest_label="${latest_major}.${latest_minor}"
    else
        latest_label="${latest_major}.${latest_minor}.${latest_release}"
    fi
    echo "[*] Latest free release: ${latest_label} build ${latest_build}"

    installed=$(installed_release || true)
    if [[ "$installed" == "studio" ]]; then
        echo "[!] DaVinci Resolve Studio is installed. This script only downloads the free edition." >&2
        exit 1
    fi
    if [[ -n "$installed" && "$force" != true ]]; then
        read -r inst_major inst_minor inst_release <<<"$installed"
        inst_label="${inst_major}.${inst_minor}.${inst_release}"
        if (( inst_major == latest_major && inst_minor == latest_minor && inst_release == latest_release )); then
            echo "[✓] DaVinci Resolve ${inst_label} is already installed."
            exit 0
        fi
        if (( inst_major > latest_major \
            || (inst_major == latest_major && inst_minor > latest_minor) \
            || (inst_major == latest_major && inst_minor == latest_minor && inst_release > latest_release) )); then
            echo "[✓] Installed DaVinci Resolve ${inst_label} is newer than ${latest_label}. Use --force to reinstall."
            exit 0
        fi
        echo "[*] Installed version is ${inst_label}."
    fi
fi

echo "[*] Installing libraries..."
sudo apt update
sudo apt install -y libfuse2t64 libapr1t64 libaprutil1t64 libasound2t64 libglib2.0-0t64 curl unzip ca-certificates python3

work=$(mktemp -d /var/tmp/davinci-resolve.XXXXXX)

run=""
if [[ -n "$local_file" ]]; then
    [[ -f "$local_file" ]] || { echo "[!] File not found: $local_file" >&2; exit 1; }
    case "$local_file" in
        *.zip)
            echo "[*] Unpacking $local_file"
            unzip -q "$local_file" -d "$work"
            ;;
        *.run) run="$local_file" ;;
        *) echo "[!] --file must be a .zip or a .run installer." >&2; exit 1 ;;
    esac
else
    echo "[*] Requesting the download link..."
    download_url=$(curl -fsSL \
        -A "$user_agent" \
        -H "Accept: application/json, text/plain, */*" \
        -H "Origin: https://www.blackmagicdesign.com" \
        -H "Content-Type: application/json;charset=UTF-8" \
        -H "Referer: https://www.blackmagicdesign.com/support/download/${refer_id}/Linux" \
        --data-ascii "$registration" \
        "https://www.blackmagicdesign.com/api/register/us/download/${download_id}")
    download_url=${download_url//$'\r'/}
    download_url=${download_url//$'\n'/}
    download_url=${download_url#\"}
    download_url=${download_url%\"}
    if [[ "$download_url" != https://* ]]; then
        echo "[!] Blackmagic did not return a download URL." >&2
        printf '%s\n' "$download_url" >&2
        exit 1
    fi

    avail_kb=$(df -Pk "$work" | awk 'NR==2 {print $4}')
    if (( avail_kb < 12 * 1024 * 1024 )); then
        echo "[!] Need at least 12 GB free on /var/tmp for the download and the unpacked installer." >&2
        exit 1
    fi

    zip_name=${download_url%%\?*}
    zip_name=${zip_name##*/}
    [[ -n "$zip_name" ]] || zip_name="DaVinci_Resolve_Linux.zip"
    archive="$work/$zip_name"
    echo "[*] Downloading ${zip_name}"
    curl -fL --retry 3 --retry-delay 5 -C - -o "$archive" "$download_url"
    echo "[*] Unpacking ${zip_name}"
    unzip -q "$archive" -d "$work"
fi

if [[ -z "$run" ]]; then
    run=$(find "$work" -type f -name 'DaVinci_Resolve_*_Linux.run' -print -quit)
fi
if [[ -z "$run" || ! -f "$run" ]]; then
    echo "[!] The archive did not contain a DaVinci Resolve .run installer." >&2
    exit 1
fi
chmod +x "$run"

if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    echo "[!] The Resolve installer opens a window. Run this from a desktop session." >&2
    exit 1
fi

echo "[*] Running the installer. Approve the prompt it opens."
SKIP_PACKAGE_CHECK=1 "$run"

echo "[✓] DaVinci Resolve installer finished."
echo "    Launch it from the menu, or run /opt/resolve/bin/resolve"
