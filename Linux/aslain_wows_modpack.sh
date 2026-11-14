#!/usr/bin/env bash
# aslain_wows_modpack.sh
# Automatically downloads the latest classic Aslain's World of Warships modpack installer
# (only if a newer version is available) and launches it in the Wine/Proton prefix
# of the Steam WoWs install.
#
# Usage:
#   ./aslain_wows_modpack.sh              # download if newer, then launch
#   ./aslain_wows_modpack.sh --check      # only report whether an update exists
#   ./aslain_wows_modpack.sh --cleanup    # also delete older local installers after a successful update
#   ./aslain_wows_modpack.sh --mod-manager  # use the new Mod Manager instead of the classic installer
#
# Environment overrides:
#   ASLAIN_DOWNLOAD_DIR   (default: $HOME/Downloads)
#   WINEPREFIX            (if set, skips auto-detection)
#   ASLAIN_CLEANUP=1      (same as --cleanup)
#
# Exit codes:
#   0  success (installer launched, or already up to date in --check mode)
#   1  error
#   2  update available (only in --check mode)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
FORUM_URL="https://aslain.com/index.php?/topic/2020-download-%E2%98%85-world-of-warships-%E2%98%85-modpack/"
MOD_MANAGER_URL="https://repo.aslain.com/wows_modmanager/Aslain_WoWs_Mod_Manager_Setup.exe"
DOWNLOAD_DIR="${ASLAIN_DOWNLOAD_DIR:-$HOME/Downloads}"
CLEANUP="${ASLAIN_CLEANUP:-0}"
CHECK_ONLY=0
USE_MOD_MANAGER=0
PARTIAL_DOWNLOAD=""

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)       CHECK_ONLY=1; shift ;;
        --cleanup)     CLEANUP=1; shift ;;
        --mod-manager) USE_MOD_MANAGER=1; shift ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Aslain Modpack" "$@" || true
    fi
}

die() {
    echo "Error: $*" >&2
    notify "Aslain modpack" "Error: $*"
    exit 1
}

# Extract sortable version: Aslains_WoWs_Modpack_Installer_v.15.10.0_08.exe -> 15.10.0.08
extract_version() {
    local name="$1"
    echo "$name" | sed -E 's/.*_v\.([0-9.]+)_([0-9]+)\.exe$/\1.\2/'
}

# Prefer a Proton wine binary that matches the prefix when possible
find_wine() {
    local candidates=()
    local proton_root

    # Common Proton locations
    for proton_root in \
        "$HOME/.local/share/Steam/steamapps/common"/Proton* \
        "$HOME/.steam/steam/steamapps/common"/Proton* \
        /usr/share/steam/compatibilitytools.d/Proton* \
        "$HOME/.local/share/Steam/compatibilitytools.d"/Proton*; do
        if [[ -x "${proton_root}/dist/bin/wine" ]]; then
            candidates+=("${proton_root}/dist/bin/wine")
        fi
    done

    # Prefer the newest-looking Proton (simple lexical sort usually works for Proton X.Y)
    if [[ ${#candidates[@]} -gt 0 ]]; then
        printf '%s\n' "${candidates[@]}" | sort -V | tail -n1
        return
    fi

    # Fallback to system wine
    if command -v wine >/dev/null 2>&1; then
        command -v wine
        return
    fi

    die "Could not find a wine binary (neither Proton nor system wine)."
}

# Auto-detect Steam library and World of Warships AppID / prefix
find_wows_prefix() {
    local steam_roots=()
    local library_paths=()
    local manifest
    local appid

    # Common Steam root locations
    for root in \
        "$HOME/.local/share/Steam" \
        "$HOME/.steam/steam" \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" \
        /usr/share/steam; do
        if [[ -d "$root/steamapps" ]]; then
            steam_roots+=("$root")
        fi
    done

    [[ ${#steam_roots[@]} -gt 0 ]] || return 1

    # Collect library folders (main + additional from libraryfolders.vdf)
    for root in "${steam_roots[@]}"; do
        library_paths+=("$root/steamapps")
        local vdf="$root/steamapps/libraryfolders.vdf"
        if [[ -f "$vdf" ]]; then
            # Extract "path" entries
            while IFS= read -r line; do
                path=$(echo "$line" | sed -E 's/.*"path"[[:space:]]+"([^"]+)".*/\1/; s/.*"path"[[:space:]]+([^[:space:]]+).*/\1/')
                if [[ -n "$path" && -d "$path/steamapps" ]]; then
                    library_paths+=("$path/steamapps")
                fi
            done < <(grep -E '"path"' "$vdf" || true)
        fi
    done

    # Deduplicate
    mapfile -t library_paths < <(printf '%s\n' "${library_paths[@]}" | sort -u)

    # Scan appmanifests for World of Warships
    for lib in "${library_paths[@]}"; do
        [[ -d "$lib" ]] || continue
        for manifest in "$lib"/appmanifest_*.acf; do
            [[ -f "$manifest" ]] || continue
            if grep -qiE '"name"[[:space:]]+"World of Warships"' "$manifest"; then
                appid=$(basename "$manifest" | sed -E 's/appmanifest_([0-9]+)\.acf/\1/')
                if [[ -n "$appid" ]]; then
                    # compatdata lives inside the steamapps directory
                    local prefix="$lib/compatdata/$appid/pfx"
                    if [[ -d "$prefix" ]]; then
                        echo "$prefix"
                    else
                        # Return the expected path even if the prefix doesn't exist yet
                        echo "$prefix"
                    fi
                    return 0
                fi
            fi
        done
    done

    return 1
}

cleanup_partial() {
    if [[ -n "$PARTIAL_DOWNLOAD" && -f "$PARTIAL_DOWNLOAD" ]]; then
        echo "Cleaning up partial download: $PARTIAL_DOWNLOAD" >&2
        rm -f "$PARTIAL_DOWNLOAD"
    fi
}
trap cleanup_partial EXIT

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
mkdir -p "$DOWNLOAD_DIR"

# Auto-detect prefix unless the user explicitly set WINEPREFIX
if [[ -z "${WINEPREFIX+x}" ]]; then
    DETECTED_PREFIX=$(find_wows_prefix || true)
    if [[ -n "$DETECTED_PREFIX" ]]; then
        WINEPREFIX="$DETECTED_PREFIX"
        echo "Auto-detected WoWs prefix: $WINEPREFIX"
    else
        echo "Warning: Could not auto-detect World of Warships prefix. Falling back to default." >&2
        WINEPREFIX="$HOME/.local/share/Steam/steamapps/compatdata/552990/pfx"
    fi
else
    echo "Using user-supplied WINEPREFIX: $WINEPREFIX"
fi

WINE_BIN=$(find_wine)
echo "Using wine: $WINE_BIN"

# --- Fetch page -----------------------------------------------------------
echo "Fetching latest modpack info from Aslain's forum..."
HTML=$(curl -fsSL --compressed "$FORUM_URL") || die "Failed to fetch forum page."

# Extract SHA if present (used for both classic and as a sanity check)
PAGE_SHA=$(echo "$HTML" | grep -oE 'SHA-256[[:space:]]*:[[:space:]]*[a-fA-F0-9]{64}' | head -n1 | grep -oE '[a-fA-F0-9]{64}' || true)

# --- Decide which installer -----------------------------------------------
if [[ "$USE_MOD_MANAGER" -eq 1 ]]; then
    DOWNLOAD_URL="$MOD_MANAGER_URL"
    FILENAME="Aslain_WoWs_Mod_Manager_Setup.exe"
    REMOTE_VER="mod-manager"
    echo "Mode: new Mod Manager"
else
    DOWNLOAD_URL=$(echo "$HTML" | grep -oE 'https://filez\.aslain\.com/Aslains_WoWs_Modpack_Installer_[^"[:space:]]+\.exe' | head -n1)
    [[ -n "$DOWNLOAD_URL" ]] || die "Could not find the classic modpack installer download link on the page."
    FILENAME=$(basename "$DOWNLOAD_URL")
    REMOTE_VER=$(extract_version "$FILENAME")
    echo "Mode: classic installer"
    echo "Latest installer on page: $FILENAME (version $REMOTE_VER)"
fi

DEST="$DOWNLOAD_DIR/$FILENAME"

# --- Find newest local classic installer (ignored for mod-manager) --------
LOCAL_CANDIDATE=""
LOCAL_VER=""
if [[ "$USE_MOD_MANAGER" -eq 0 ]]; then
    while IFS= read -r -d '' f; do
        base=$(basename "$f")
        ver=$(extract_version "$base")
        [[ -n "$ver" ]] || continue
        if [[ -z "$LOCAL_VER" ]] || [[ "$(printf '%s\n%s\n' "$LOCAL_VER" "$ver" | sort -V | tail -n1)" == "$ver" ]]; then
            LOCAL_VER="$ver"
            LOCAL_CANDIDATE="$f"
        fi
    done < <(find "$DOWNLOAD_DIR" -maxdepth 1 -name 'Aslains_WoWs_Modpack_Installer_v.*.exe' -print0 2>/dev/null || true)

    if [[ -n "$LOCAL_CANDIDATE" ]]; then
        echo "Newest local installer: $(basename "$LOCAL_CANDIDATE") (version $LOCAL_VER)"
    fi
fi

# --- Decide whether to download -------------------------------------------
NEED_DOWNLOAD=1
if [[ "$USE_MOD_MANAGER" -eq 0 && -n "$LOCAL_CANDIDATE" ]]; then
    HIGHER=$(printf '%s\n%s\n' "$LOCAL_VER" "$REMOTE_VER" | sort -V | tail -n1)
    if [[ "$HIGHER" == "$LOCAL_VER" ]]; then
        NEED_DOWNLOAD=0
        DEST="$LOCAL_CANDIDATE"
        echo "Local version is up to date or newer."
    else
        echo "Remote version is newer."
    fi
elif [[ "$USE_MOD_MANAGER" -eq 1 && -f "$DEST" ]]; then
    NEED_DOWNLOAD=0
    echo "Mod Manager already present locally."
fi

# --- Check-only mode ------------------------------------------------------
if [[ "$CHECK_ONLY" -eq 1 ]]; then
    if [[ "$NEED_DOWNLOAD" -eq 0 ]]; then
        echo "Already up to date."
        notify "Aslain modpack" "Already up to date."
        exit 0
    else
        echo "Update available: $FILENAME"
        notify "Aslain modpack" "Update available: $FILENAME"
        exit 2
    fi
fi

# --- Download if needed ---------------------------------------------------
if [[ "$NEED_DOWNLOAD" -eq 1 ]]; then
    echo "Downloading $DOWNLOAD_URL"
    echo " -> $DEST"
    PARTIAL_DOWNLOAD="$DEST"
    if ! curl -fL --retry 3 --retry-delay 2 --progress-bar -C - -o "$DEST" "$DOWNLOAD_URL"; then
        die "Download failed."
    fi
    PARTIAL_DOWNLOAD=""   # success, don't delete on exit
    echo "Download finished."
else
    echo "Skipping download."
fi

# --- SHA-256 verification (always, when we have a hash) -------------------
if [[ -n "$PAGE_SHA" && "$USE_MOD_MANAGER" -eq 0 ]]; then
    echo "Verifying SHA-256..."
    ACTUAL_SHA=$(sha256sum "$DEST" | awk '{print $1}')
    if [[ "${ACTUAL_SHA,,}" != "${PAGE_SHA,,}" ]]; then
        echo "SHA-256 mismatch!" >&2
        echo "Expected: $PAGE_SHA" >&2
        echo "Actual:   $ACTUAL_SHA" >&2
        if [[ "$NEED_DOWNLOAD" -eq 1 ]]; then
            rm -f "$DEST"
            die "Downloaded file failed verification."
        else
            echo "Local file failed verification. Will re-download." >&2
            rm -f "$DEST"
            PARTIAL_DOWNLOAD="$DEST"
            curl -fL --retry 3 --retry-delay 2 --progress-bar -o "$DEST" "$DOWNLOAD_URL" || die "Re-download failed."
            PARTIAL_DOWNLOAD=""
            ACTUAL_SHA=$(sha256sum "$DEST" | awk '{print $1}')
            [[ "${ACTUAL_SHA,,}" == "${PAGE_SHA,,}" ]] || die "Re-downloaded file still failed verification."
        fi
    fi
    echo "SHA-256 verified."
elif [[ "$USE_MOD_MANAGER" -eq 0 ]]; then
    echo "Warning: No SHA-256 found on the page; skipping verification."
fi

# --- Optional cleanup of older classic installers -------------------------
if [[ "$CLEANUP" -eq 1 && "$USE_MOD_MANAGER" -eq 0 && -f "$DEST" ]]; then
    echo "Cleaning up older installers..."
    while IFS= read -r -d '' f; do
        if [[ "$f" != "$DEST" ]]; then
            echo "  removing $(basename "$f")"
            rm -f "$f"
        fi
    done < <(find "$DOWNLOAD_DIR" -maxdepth 1 -name 'Aslains_WoWs_Modpack_Installer_v.*.exe' -print0 2>/dev/null || true)
fi

# --- Sanity checks before launch ------------------------------------------
[[ -d "$WINEPREFIX" ]] || die "Wine prefix not found at $WINEPREFIX (is WoWs installed via Steam?)"

# Abort if the game appears to be running
if pgrep -f -i 'WorldOfWarships' >/dev/null 2>&1; then
    die "World of Warships appears to be running. Please close the game before running the installer."
fi

# --- Launch ---------------------------------------------------------------
echo "Launching installer..."
echo "  wine:       $WINE_BIN"
echo "  prefix:     $WINEPREFIX"
echo "  installer:  $DEST"
notify "Aslain modpack" "Launching installer..."

# Clear the EXIT trap so we don't delete a good file
trap - EXIT

exec env WINEPREFIX="$WINEPREFIX" "$WINE_BIN" "$DEST"
