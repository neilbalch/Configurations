#!/usr/bin/env bash
set -euo pipefail

# The kasa CLI is safe as a single, waited-for command. Plasma's executable
# DataSource is not: disconnectSource() SIGTERMs kasa mid-TCP, and sliders
# spawned overlapping processes. desklamp.py wraps `kasa --type bulb command`
# with a lock; the QML waits for exit code before disconnecting.

DEVICE_NAME="Desk Corner"
FALLBACK_IP="192.168.1.178"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_HELPER="$HERE/desklamp.py"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/org.kde.desklamp"
CONTENTS_DIR="$PLASMOID_DIR/contents"
UI_DIR="$CONTENTS_DIR/ui"
ICONS_DIR="$CONTENTS_DIR/icons"
SCRIPTS_DIR="$CONTENTS_DIR/scripts"
HELPER="$SCRIPTS_DIR/desklamp.py"
JSON_PY="$(command -v python3)"

echo "==> 1. Checking dependencies..."
if [ ! -f "$SRC_HELPER" ]; then
    echo "    [!] Missing $SRC_HELPER"
    exit 1
fi
if [ -z "$JSON_PY" ]; then
    echo "    [!] python3 is required"
    exit 1
fi
if ! command -v kbuildsycoca6 &> /dev/null; then
    echo "Installing plasma-workspace build utilities..."
    sudo apt update && sudo apt install -y libkf6service-bin || true
fi

echo "==> 2. Creating plasmoid directory structure..."
mkdir -p "$UI_DIR" "$ICONS_DIR" "$SCRIPTS_DIR"
rm -f "$UI_DIR"/gemini-code-*.txt

echo "==> 3. Installing desklamp helper..."
install -m 755 "$SRC_HELPER" "$HELPER"

echo "==> 4. Locating '$DEVICE_NAME'..."
TARGET_IP=""
TARGET_MAC=""

json_ok() {
    printf '%s' "${1:-}" | "$JSON_PY" -c "
import json, sys
raw = sys.stdin.read().strip()
try:
    d = json.loads(raw)
except Exception:
    sys.exit(1)
sys.exit(0 if d.get('ok') else 1)
"
}

json_field() {
    printf '%s' "${1:-}" | "$JSON_PY" -c "import json,sys; print(json.loads(sys.stdin.read()).get('$2',''))"
}

GET_JSON="$("$HELPER" --host "$FALLBACK_IP" get 2>/dev/null || true)"
if json_ok "${GET_JSON:-}" && printf '%s' "$GET_JSON" | "$JSON_PY" -c "
import json,sys
d=json.loads(sys.stdin.read())
sys.exit(0 if '$DEVICE_NAME'.lower() in str(d.get('alias','')).lower() else 1)
"; then
    TARGET_IP="$FALLBACK_IP"
    TARGET_MAC="$(json_field "$GET_JSON" mac)"
    echo "    [+] '$DEVICE_NAME' answered get_sysinfo at $TARGET_IP"
else
    echo "    [.] $FALLBACK_IP did not identify as '$DEVICE_NAME'; using fallback (no kasa discover)."
    TARGET_IP="$FALLBACK_IP"
fi

echo "==> 5. Writing metadata.json..."
cat << 'EOF' > "$PLASMOID_DIR/metadata.json"
{
    "KPlugin": {
        "Authors": [
            {
                "Name": "Neil"
            }
        ],
        "Category": "Utilities",
        "Description": "Control TP-Link Kasa Desk Lamp (LB120)",
        "Icon": "lightbulb",
        "Id": "org.kde.desklamp",
        "Name": "Desk Lamp Control",
        "Version": "1.2",
        "Website": ""
    },
    "KPackageStructure": "Plasma/Applet",
    "X-Plasma-API-Minimum-Version": "6.0"
}
EOF

echo "==> 6. Writing contents/icons/desklamp.svg..."
cat << 'EOF' > "$ICONS_DIR/desklamp.svg"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48">
  <path d="M12 2v2.5M4.93 4.93l1.77 1.77M2 12h2.5M4.93 19.07l1.77-1.77M19.07 4.93l-1.77 1.77M22 12h-2.5M19.07 19.07l-1.77-1.77"
        stroke="#ffffff" stroke-width="2" stroke-linecap="round"/>
  <path d="M9 18h6m-5 3h4m-3-16a6 6 0 0 1 6 6c0 2.22-1.21 4.16-3 5.2V17a1 1 0 0 1-1 1h-4a1 1 0 0 1-1-1v-1.8C8.21 15.16 7 13.22 7 11a6 6 0 0 1 6-6z"
        fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M10 12l2-3 2 3" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
EOF

echo "==> 7. Writing contents/ui/main.qml (host $TARGET_IP)..."
cat << EOF > "$UI_DIR/main.qml"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    property string helper: "$HELPER"
    property string targetIp: "$TARGET_IP"
    property string targetMac: "$TARGET_MAC"
    property string deviceName: "$DEVICE_NAME"

    property bool isConnected: false
    property bool isScanning: false
    property bool busy: false
    property bool dragging: false

    property string powerStateText: "Unknown"
    property string reportedBrightnessText: "--%"
    property string reportedTempText: "--K"
    property string lastError: ""

    property int currentBrightness: 100
    property int currentTemp: 3710

    property var cmdQueue: []
    property string pendingAction: ""
    property int pendingValue: 0

    preferredRepresentation: compactRepresentation
    Plasmoid.title: "Desk Lamp Control"

    function applyPayload(payload) {
        if (!payload || payload.ok !== true) {
            root.isConnected = false;
            root.powerStateText = "N/A";
            if (payload && payload.error)
                root.lastError = payload.error;
            return;
        }
        root.isConnected = true;
        root.lastError = "";
        root.powerStateText = payload.on ? "ON" : "OFF";
        if (typeof payload.brightness === "number") {
            root.reportedBrightnessText = payload.brightness + "%";
            if (!root.dragging)
                root.currentBrightness = payload.brightness;
        }
        if (typeof payload.color_temp === "number" && payload.color_temp > 0) {
            root.reportedTempText = payload.color_temp + "K";
            if (!root.dragging)
                root.currentTemp = payload.color_temp;
        }
        if (payload.mac)
            root.targetMac = payload.mac;
    }

    function enqueue(action, value) {
        var cmd = root.helper + " --host " + root.targetIp + " " + action;
        if (action === "brightness" || action === "temperature")
            cmd += " " + value;

        var next = [];
        for (var i = 0; i < root.cmdQueue.length; i++) {
            var existing = root.cmdQueue[i];
            var drop = false;
            if (action === "brightness" && existing.indexOf(" brightness ") !== -1)
                drop = true;
            if (action === "temperature" && existing.indexOf(" temperature ") !== -1)
                drop = true;
            if (action === "get" && existing.indexOf(" get") !== -1)
                drop = true;
            if (!drop)
                next.push(existing);
        }
        next.push(cmd);
        root.cmdQueue = next;
        pump();
    }

    function pump() {
        if (root.busy)
            return;
        if (root.cmdQueue.length === 0)
            return;
        root.busy = true;
        var cmd = root.cmdQueue[0];
        var rest = [];
        for (var i = 1; i < root.cmdQueue.length; i++)
            rest.push(root.cmdQueue[i]);
        root.cmdQueue = rest;
        commandWatchdog.restart();
        executableDataSource.exec(cmd);
    }

    function sendDebounced(action, value) {
        root.pendingAction = action;
        root.pendingValue = value;
        cmdTimer.restart();
    }

    function flushSlider(action, value) {
        cmdTimer.stop();
        root.pendingAction = "";
        enqueue(action, value);
    }

    function checkConnection() {
        root.isScanning = true;
        enqueue("get");
    }

    Timer {
        id: cmdTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (root.pendingAction !== "") {
                enqueue(root.pendingAction, root.pendingValue);
                root.pendingAction = "";
            }
        }
    }

    Timer {
        id: commandWatchdog
        interval: 12000
        repeat: false
        onTriggered: {
            // Do not disconnectSource here: that SIGTERMs kasa mid-TCP and
            // knocks the LB120 off Wi-Fi. Let the process finish on its own.
            root.isScanning = false;
            root.lastError = "Timed out waiting for the lamp";
        }
    }

    Plasma5Support.DataSource {
        id: executableDataSource
        engine: "executable"
        connectedSources: []

        function exec(cmd) {
            connectSource(cmd);
        }

        onNewData: function(sourceName, data) {
            // kasa prints before it exits (e.g. discovery). Disconnecting on
            // the first chunk SIGTERMs the TCP session and crashes the bulb.
            var exitCode = data["exit code"];
            if (exitCode === undefined || exitCode === "" || exitCode === null)
                return;

            commandWatchdog.stop();
            var output = (data["stdout"] || "").trim();
            var payload = null;
            try {
                payload = JSON.parse(output);
            } catch (e) {
                payload = { ok: false, error: output || (data["stderr"] || "bad helper output") };
            }
            root.applyPayload(payload);
            root.isScanning = false;
            disconnectSource(sourceName);
            root.busy = false;
            pump();
        }
    }

    onExpandedChanged: {
        if (expanded)
            root.checkConnection();
    }

    compactRepresentation: PlasmaComponents.ItemDelegate {
        id: compactDelegate

        contentItem: Image {
            source: Qt.resolvedUrl("../icons/desklamp.svg")
            fillMode: Image.PreserveAspectFit
            sourceSize.width: compactDelegate.width
            sourceSize.height: compactDelegate.height
        }

        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: implicitHeight
        Layout.preferredHeight: implicitHeight
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 1
                    text: Plasmoid.title
                    elide: Text.ElideRight
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    text: "Refresh"
                    display: AbstractButton.IconOnly
                    enabled: !root.busy
                    onClicked: root.checkConnection()

                    PlasmaComponents.ToolTip {
                        text: parent.text
                    }
                }
            }
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.75
                text: "Local on/off, brightness, and color temperature for the TP-Link Kasa LB120 on this network."
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: "Device"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: root.isConnected ? "network-connect" : "network-disconnect"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: root.isScanning ? "Checking…" : (root.isConnected ? "Connected" : "Disconnected")
                        color: root.isConnected ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    }
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    opacity: 0.75
                    text: root.deviceName + " · LB120"
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    opacity: 0.75
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: root.targetIp + (root.targetMac !== "" ? " · " + root.targetMac : "")
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    visible: root.lastError !== ""
                    wrapMode: Text.Wrap
                    color: Kirigami.Theme.negativeTextColor
                    text: root.lastError
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: "Power"
                }

                PlasmaComponents.Switch {
                    checked: root.powerStateText === "ON"
                    enabled: root.isConnected && !root.busy
                    onClicked: root.enqueue("toggle")
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: "Brightness"
                    }

                    PlasmaComponents.Label {
                        opacity: 0.75
                        text: Math.round(brightSlider.value) + "%"
                    }
                }

                PlasmaComponents.Slider {
                    id: brightSlider
                    Layout.fillWidth: true
                    from: 1
                    to: 100
                    value: root.currentBrightness
                    enabled: root.isConnected
                    onPressedChanged: {
                        root.dragging = pressed;
                        if (!pressed)
                            root.flushSlider("brightness", Math.round(value));
                    }
                    onMoved: {
                        var val = Math.round(value);
                        root.currentBrightness = val;
                        root.reportedBrightnessText = val + "%";
                        root.sendDebounced("brightness", val);
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: "Color temperature"
                    }

                    PlasmaComponents.Label {
                        opacity: 0.75
                        text: Math.round(tempSlider.value) + "K"
                    }
                }

                PlasmaComponents.Slider {
                    id: tempSlider
                    Layout.fillWidth: true
                    from: 2700
                    to: 6500
                    value: root.currentTemp
                    enabled: root.isConnected
                    onPressedChanged: {
                        root.dragging = pressed;
                        if (!pressed)
                            root.flushSlider("temperature", Math.round(value));
                    }
                    onMoved: {
                        var val = Math.round(value);
                        root.currentTemp = val;
                        root.reportedTempText = val + "K";
                        root.sendDebounced("temperature", val);
                    }
                }
            }
        }
    }
}
EOF

echo "==> 8. Rebuilding system service cache..."
if command -v kbuildsycoca6 &> /dev/null; then
    kbuildsycoca6 --noincremental
fi

echo "==> 9. Restarting Plasma shell so the widget reloads..."
if command -v kquitapp6 &> /dev/null; then
    kquitapp6 plasmashell || true
    sleep 1
    plasmashell --replace >/dev/null 2>&1 &
    disown || true
else
    killall plasmashell 2>/dev/null || true
    plasmashell --replace >/dev/null 2>&1 &
    disown || true
fi

echo "Done. Widget talks to $TARGET_IP via $HELPER (kasa --type bulb for get/toggle; one-shot XOR for sliders)."
echo "Test helper: $HELPER --host $TARGET_IP get"
echo "Preview: plasmoidviewer -a $PLASMOID_DIR"
