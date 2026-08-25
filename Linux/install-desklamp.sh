#!/usr/bin/env bash
set -e

DEVICE_NAME="Desk Corner"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/org.kde.desklamp"
CONTENTS_DIR="$PLASMOID_DIR/contents"
UI_DIR="$CONTENTS_DIR/ui"
ICONS_DIR="$CONTENTS_DIR/icons"

echo "==> 1. Checking and installing system dependencies..."

if ! command -v pip &> /dev/null && ! command -v pipx &> /dev/null; then
    echo "Installing python3-pip..."
    sudo apt update && sudo apt install -y python3-pip python3-full
fi

if ! command -v kasa &> /dev/null; then
    echo "Installing python-kasa CLI..."
    if command -v pipx &> /dev/null; then
        pipx install python-kasa
    else
        pip install --user python-kasa
    fi
fi

if ! command -v kbuildsycoca6 &> /dev/null; then
    echo "Installing plasma-workspace build utilities..."
    sudo apt update && sudo apt install -y libkf6service-bin || true
fi

echo "==> 2. Auto-detecting lamp IP address by device name '$DEVICE_NAME'..."
TARGET_IP=""

# Run kasa discover and parse for alias "Desk Corner"
DISCOVERY_OUTPUT=$(kasa discover 2>/dev/null || true)
TARGET_IP=$(echo "$DISCOVERY_OUTPUT" | grep -i "$DEVICE_NAME" -B 2 | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1 || true)

if [ -z "$TARGET_IP" ]; then
    echo "    [!] Warning: Could not locate '$DEVICE_NAME' on local subnet via kasa discover."
    echo "    [!] Falling back to default IP: 192.168.1.178"
    TARGET_IP="192.168.1.178"
else
    echo "    [+] Discovered '$DEVICE_NAME' at IP: $TARGET_IP"
fi

echo "==> 3. Creating plasmoid directory structure..."
mkdir -p "$UI_DIR" "$ICONS_DIR"

echo "==> 4. Writing metadata.json..."
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
        "Version": "1.0",
        "Website": ""
    },
    "KPackageStructure": "Plasma/Applet"
}
EOF

echo "==> 5. Writing contents/icons/desklamp.svg..."
cat << 'EOF' > "$ICONS_DIR/desklamp.svg"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48">
  <path d="M12 2v2.5M4.93 4.93l1.77 1.77M2 12h2.5M4.93 19.07l1.77-1.77M19.07 4.93l-1.77 1.77M22 12h-2.5M19.07 19.07l-1.77-1.77" 
        stroke="#ffffff" stroke-width="2" stroke-linecap="round"/>
  <path d="M9 18h6m-5 3h4m-3-16a6 6 0 0 1 6 6c0 2.22-1.21 4.16-3 5.2V17a1 1 0 0 1-1 1h-4a1 1 0 0 1-1-1v-1.8C8.21 15.16 7 13.22 7 11a6 6 0 0 1 6-6z" 
        fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M10 12l2-3 2 3" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
EOF

echo "==> 6. Writing contents/ui/main.qml with resolved IP ($TARGET_IP)..."
cat << EOF > "$UI_DIR/main.qml"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    property string targetIp: "$TARGET_IP"
    property string deviceName: "$DEVICE_NAME"
    property bool isConnected: false
    property bool isScanning: false

    property string powerStateText: "Unknown"
    property string reportedBrightnessText: "--%"
    property string reportedTempText: "--K"

    property int currentBrightness: 100
    property int currentTemp: 3710

    property string pendingCommand: ""

    Plasmoid.title: "Desk Lamp Control"

    Timer {
        id: scanTimeoutTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.isScanning) {
                root.isScanning = false;
            }
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
            var output = data["stdout"] || "";
            var exitCode = data["exit code"];

            root.isScanning = false;
            scanTimeoutTimer.stop();

            if (sourceName.indexOf("state") !== -1) {
                if (exitCode === 0 && output.length > 0) {
                    root.isConnected = true;
                    
                    var stateMatch = output.match(/Device state:\s*(True|False)/i);
                    if (stateMatch) {
                        root.powerStateText = (stateMatch[1].toLowerCase() === "true") ? "ON" : "OFF";
                    }

                    var brightMatch = output.match(/Brightness(?:\s*\([^)]+\))?:\s*([0-9]+)/i);
                    if (brightMatch) {
                        var valBright = parseInt(brightMatch[1]);
                        root.reportedBrightnessText = valBright + "%";
                        root.currentBrightness = valBright;
                    }

                    var tempMatch = output.match(/Color\s*temperature(?:\s*\([^)]+\))?:\s*([0-9]+)/i);
                    if (tempMatch) {
                        var valTemp = parseInt(tempMatch[1]);
                        root.reportedTempText = valTemp + "K";
                        root.currentTemp = valTemp;
                    }
                } else {
                    root.isConnected = false;
                    root.powerStateText = "N/A";
                    root.reportedBrightnessText = "--%";
                    root.reportedTempText = "--K";
                }
            }

            disconnectSource(sourceName);
        }
    }

    Timer {
        id: cmdTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (root.pendingCommand !== "") {
                executableDataSource.exec(root.pendingCommand);
                root.pendingCommand = "";
            }
        }
    }

    function sendDebouncedCmd(cmd) {
        root.pendingCommand = cmd;
        cmdTimer.restart();
    }

    Component.onCompleted: {
        root.checkConnection();
    }

    onExpandedChanged: {
        if (expanded) {
            root.checkConnection();
        }
    }

    function checkConnection() {
        root.isScanning = true;
        scanTimeoutTimer.restart();
        executableDataSource.exec("kasa --host " + root.targetIp + " state");
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

    fullRepresentation: Item {
        Layout.minimumWidth: 290
        Layout.preferredWidth: 300
        Layout.maximumWidth: 310
        Layout.minimumHeight: 310
        Layout.preferredHeight: 320

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 115
                color: root.isConnected ? "#1e3a1e" : "#3a1e1e"
                radius: 6
                border.color: root.isConnected ? "#2e6b2e" : "#6b2e2e"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true

                        PlasmaComponents.Label {
                            text: root.isScanning ? "Status: Checking..." : (root.isConnected ? "Status: Connected" : "Status: Disconnected")
                            font.bold: true
                            color: root.isConnected ? "#66ff66" : "#ff6666"
                            Layout.fillWidth: true
                        }

                        PlasmaComponents.Button {
                            icon.name: "view-refresh"
                            text: ""
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            onClicked: root.checkConnection()
                        }
                    }

                    PlasmaComponents.Label {
                        text: "Name: " + root.deviceName
                        font.pointSize: 9
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    PlasmaComponents.Label {
                        text: "IP: " + root.targetIp
                        font.pointSize: 8
                        opacity: 0.8
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    PlasmaComponents.Label {
                        text: "Reported: State: " + root.powerStateText + " | Bright: " + root.reportedBrightnessText + " | Temp: " + root.reportedTempText
                        font.pointSize: 8
                        font.bold: true
                        color: "#aaffaa"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
            }

            PlasmaComponents.Button {
                text: "Toggle On/Off (" + root.powerStateText + ")"
                Layout.fillWidth: true
                enabled: root.isConnected
                onClicked: {
                    executableDataSource.exec("kasa --host " + root.targetIp + " toggle");
                    root.checkConnection();
                }
            }

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    text: "Brightness"
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: Math.round(brightSlider.value) + "%"
                    font.bold: true
                }
            }

            PlasmaComponents.Slider {
                id: brightSlider
                from: 1
                to: 100
                value: root.currentBrightness
                Layout.fillWidth: true
                enabled: root.isConnected
                onMoved: {
                    var val = Math.round(value);
                    root.currentBrightness = val;
                    root.reportedBrightnessText = val + "%";
                    root.sendDebouncedCmd("kasa --host " + root.targetIp + " brightness " + val);
                }
            }

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    text: "Color Temperature"
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: Math.round(tempSlider.value) + "K"
                    font.bold: true
                }
            }

            PlasmaComponents.Slider {
                id: tempSlider
                from: 2700
                to: 6500
                value: root.currentTemp
                Layout.fillWidth: true
                enabled: root.isConnected
                onMoved: {
                    var val = Math.round(value);
                    root.currentTemp = val;
                    root.reportedTempText = val + "K";
                    root.sendDebouncedCmd("kasa --host " + root.targetIp + " temperature " + val);
                }
            }
        }
    }
}
EOF

echo "==> 7. Rebuilding system service cache..."
kbuildsycoca6 --noincremental

echo "==> 8. Restarting Plasma shell..."
killall -9 plasmashell 2>/dev/null || true
plasmashell --replace &

echo "Done! Searching by device name '$DEVICE_NAME' resolved IP to $TARGET_IP."