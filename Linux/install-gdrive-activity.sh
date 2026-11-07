#!/usr/bin/env bash
# Install the Google Drive activity plasmoid.
#
# The widget reads ~/.local/share/rclone/logs/audit.log (the file written by
# setup-gdrive-sync.sh) and lists recent uploads, downloads, and removals.
# Add it to the panel, beside the clock. The system tray does not accept a
# widget dropped onto it; that drop freezes the panel editor.
#
# Usage: install-gdrive-activity.sh [--restart]
#   --restart   reload Plasma so a widget that is already loaded picks up
#               the new files. The first install does not need this.

set -euo pipefail

RESTART=0
for arg in "$@"; do
    case "$arg" in
        --restart) RESTART=1 ;;
        --no-restart) RESTART=0 ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--restart]"
            echo "Install the Google Drive activity widget."
            echo "  --restart   reload Plasma after installing"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 2
            ;;
    esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_HELPER="$HERE/gdrive-activity.py"
SRC_QML="$HERE/gdrive-activity.qml"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/org.kde.gdriveactivity"
CONTENTS_DIR="$PLASMOID_DIR/contents"
UI_DIR="$CONTENTS_DIR/ui"
SCRIPTS_DIR="$CONTENTS_DIR/scripts"
HELPER="$SCRIPTS_DIR/gdrive-activity.py"
AUDIT_LOG="$HOME/.local/share/rclone/logs/audit.log"
LOCAL_DIR="$HOME/GoogleDrive"

echo "==> 1. Checking dependencies..."
if [ ! -f "$SRC_HELPER" ]; then
    echo "    [!] Missing $SRC_HELPER"
    exit 1
fi
if [ ! -f "$SRC_QML" ]; then
    echo "    [!] Missing $SRC_QML"
    exit 1
fi
if ! command -v python3 >/dev/null; then
    echo "    [!] python3 is required"
    exit 1
fi
if ! command -v kbuildsycoca6 >/dev/null; then
    echo "Installing plasma-workspace build utilities..."
    sudo apt update && sudo apt install -y libkf6service-bin || true
fi

echo "==> 2. Checking the activity helper..."
python3 -m py_compile "$SRC_HELPER"
python3 "$SRC_HELPER" --selftest

echo "==> 3. Creating plasmoid directory structure..."
mkdir -p "$UI_DIR" "$SCRIPTS_DIR" "$CONTENTS_DIR/config"

echo "==> 4. Installing helper and interface..."
install -m 755 "$SRC_HELPER" "$HELPER"
install -m 644 "$SRC_QML" "$UI_DIR/main.qml"

echo "==> 5. Writing metadata.json..."
cat << 'EOF' > "$PLASMOID_DIR/metadata.json"
{
    "KPlugin": {
        "Authors": [
            {
                "Name": "Neil"
            }
        ],
        "Category": "Online Services",
        "Description": "Recent Google Drive uploads and downloads from the rclone sync log",
        "Icon": "folder-cloud",
        "Id": "org.kde.gdriveactivity",
        "Name": "Google Drive",
        "Version": "1.1"
    },
    "KPackageStructure": "Plasma/Applet",
    "X-Plasma-API-Minimum-Version": "6.0"
}
EOF

echo "==> 6. Writing contents/config/main.xml..."
cat << EOF > "$CONTENTS_DIR/config/main.xml"
<?xml version="1.0" encoding="UTF-8"?>
<kcfg xmlns="http://www.kde.org/standards/kcfg/1.0"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.kde.org/standards/kcfg/1.0
      http://www.kde.org/standards/kcfg/1.0/kcfg.xsd">
  <kcfgfile name=""/>
  <group name="General">
    <entry name="auditLog" type="String">
      <label>rclone bisync audit log</label>
      <default>$AUDIT_LOG</default>
    </entry>
    <entry name="localDir" type="String">
      <label>Local Google Drive folder</label>
      <default>$LOCAL_DIR</default>
    </entry>
    <entry name="maxEvents" type="Int">
      <label>How many completed changes to show</label>
      <default>30</default>
    </entry>
  </group>
</kcfg>
EOF

echo "==> 7. Rebuilding the Plasma service cache..."
if command -v kbuildsycoca6 >/dev/null; then
    kbuildsycoca6 --noincremental
fi

if [ "$RESTART" -eq 1 ]; then
    echo "==> 8. Restarting Plasma shell so the widget reloads..."
    if command -v kquitapp6 >/dev/null; then
        kquitapp6 plasmashell || true
        sleep 1
        plasmashell --replace >/dev/null 2>&1 &
        disown || true
    else
        killall plasmashell 2>/dev/null || true
        plasmashell --replace >/dev/null 2>&1 &
        disown || true
    fi
else
    echo "==> 8. Leaving Plasma running."
fi

echo ""
echo "Installed org.kde.gdriveactivity"
echo "  Helper:  $HELPER"
echo "  Log:     $AUDIT_LOG"
echo "  Folder:  $LOCAL_DIR"
echo ""
echo "Add it from the panel: enter edit mode, choose Add Widgets, and drop"
echo "Google Drive on an empty part of the panel, next to the clock."
echo "Do not drop it on the system tray. That drop freezes the panel editor."
if [ "$RESTART" -eq 0 ]; then
    echo "If the new entry is missing, run:  $(basename "$0") --restart"
fi
echo "Preview: plasmoidviewer -a $PLASMOID_DIR"
echo "Test helper: $HELPER"
