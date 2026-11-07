import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    property string helper: {
        var url = String(Qt.resolvedUrl("../scripts/gdrive-activity.py"));
        if (url.indexOf("file://") === 0)
            url = decodeURIComponent(url.substring(7));
        return url;
    }
    property bool busy: false
    property bool refreshQueued: false
    property bool loaded: false
    property string currentSource: ""
    property string phase: "idle"
    property string message: "Checking…"
    property string detail: ""
    property string localDir: ""
    property var rows: []

    readonly property color statusColor: {
        if (!root.loaded)
            return Kirigami.Theme.textColor;
        if (root.phase === "error")
            return Kirigami.Theme.negativeTextColor;
        if (root.phase === "paused")
            return Kirigami.Theme.neutralTextColor;
        if (root.phase === "syncing")
            return Kirigami.Theme.textColor;
        return Kirigami.Theme.positiveTextColor;
    }

    // Always an icon on the panel. The list is the popup, never an in-panel view.
    // An in-panel full view during a drag makes the panel editor negotiate height forever.
    preferredRepresentation: compactRepresentation
    switchWidth: Kirigami.Units.gridUnit * 50
    switchHeight: Kirigami.Units.gridUnit * 50
    Plasmoid.title: "Google Drive"
    Plasmoid.icon: "folder-cloud"
    toolTipMainText: "Google Drive"
    toolTipSubText: root.detail !== "" ? root.message + "\n" + root.detail : root.message
    Plasmoid.status: root.phase === "error" ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.PassiveStatus

    readonly property bool panelEditing: {
        var panel = Plasmoid.containment;
        return !!(panel && panel.corona && panel.corona.editMode);
    }

    function shQuote(value) {
        return "'" + String(value).split("'").join("'\"'\"'") + "'";
    }

    function openLocal(path) {
        if (!path)
            return;
        Qt.openUrlExternally(encodeURI("file://" + path));
    }

    function refresh() {
        if (root.busy) {
            root.refreshQueued = true;
            return;
        }
        root.busy = true;
        var logPath = String(Plasmoid.configuration.auditLog || "");
        var folder = String(Plasmoid.configuration.localDir || "");
        var limit = Plasmoid.configuration.maxEvents;
        if (!limit || limit < 1)
            limit = 30;
        var cmd = root.shQuote(root.helper);
        if (logPath !== "")
            cmd += " --log " + root.shQuote(logPath);
        if (folder !== "")
            cmd += " --local " + root.shQuote(folder);
        cmd += " --limit " + limit;
        commandWatchdog.restart();
        executableDataSource.exec(cmd);
    }

    function applyPayload(payload) {
        root.loaded = true;
        if (!payload || payload.ok !== true) {
            root.phase = "error";
            root.message = (payload && payload.message) ? payload.message : "Could not read the sync log";
            root.detail = (payload && (payload.detail || payload.error)) ? (payload.detail || payload.error) : "";
            return;
        }
        root.phase = payload.phase || "idle";
        root.message = payload.message || "";
        root.detail = payload.detail || "";
        root.localDir = payload.local_dir || String(Plasmoid.configuration.localDir || "");
        var next = [];
        var active = payload.active || [];
        var events = payload.events || [];
        for (var i = 0; i < active.length; i++)
            next.push(active[i]);
        for (var j = 0; j < events.length; j++)
            next.push(events[j]);
        root.rows = next;
    }

    // Wait until the panel drop has finished. Starting the log reader in the
    // same turn as the drop stalls the panel editor.
    Timer {
        interval: 2000
        running: true
        onTriggered: {
            if (!root.panelEditing)
                root.refresh();
            pollTimer.start();
        }
    }

    Timer {
        id: pollTimer
        interval: 5000
        repeat: true
        running: false
        onTriggered: {
            if (!root.panelEditing)
                root.refresh();
        }
    }

    Timer {
        id: commandWatchdog
        interval: 8000
        repeat: false
        onTriggered: {
            if (root.currentSource !== "")
                executableDataSource.disconnectSource(root.currentSource);
            root.busy = false;
            root.loaded = true;
            root.phase = "error";
            root.message = "Timed out reading the sync log";
            root.detail = "";
            if (root.refreshQueued) {
                root.refreshQueued = false;
                root.refresh();
            }
        }
    }

    Plasma5Support.DataSource {
        id: executableDataSource
        engine: "executable"
        connectedSources: []

        function exec(cmd) {
            root.currentSource = cmd;
            connectSource(cmd);
        }

        onNewData: function(sourceName, data) {
            var exitCode = data["exit code"];
            if (exitCode === undefined || exitCode === "" || exitCode === null)
                return;
            commandWatchdog.stop();
            var output = String(data["stdout"] || "").trim();
            var payload = null;
            try {
                payload = JSON.parse(output);
            } catch (e) {
                var stderr = String(data["stderr"] || "").trim();
                payload = {
                    ok: false,
                    message: "Could not read the sync log",
                    detail: stderr || output || "Helper returned no JSON"
                };
            }
            root.applyPayload(payload);
            disconnectSource(sourceName);
            root.busy = false;
            if (root.refreshQueued) {
                root.refreshQueued = false;
                root.refresh();
            }
        }
    }

    onExpandedChanged: function(expanded) {
        // A drop on the panel ends in a click. Opening the popup while the
        // panel editor still owns the mouse freezes that editor.
        if (expanded && root.panelEditing) {
            Qt.callLater(function() { root.expanded = false; });
            return;
        }
        if (expanded)
            root.refresh();
    }

    compactRepresentation: Item {
        implicitWidth: Kirigami.Units.iconSizes.smallMedium
        implicitHeight: implicitWidth

        Kirigami.Icon {
            anchors.fill: parent
            source: "folder-cloud"
        }

        Kirigami.Icon {
            id: stateBadge
            visible: root.loaded
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.round(parent.width * 0.5)
            height: width
            source: root.phase === "error" ? "state-error"
                  : root.phase === "paused" ? "state-warning"
                  : root.phase === "syncing" ? "view-refresh"
                  : "state-ok"

            RotationAnimator on rotation {
                id: spinBadge
                running: root.phase === "syncing"
                from: 0
                to: 360
                duration: 1400
                loops: Animation.Infinite
                onRunningChanged: function() {
                    if (!spinBadge.running)
                        stateBadge.rotation = 0
                }
            }
        }

        // Left click opens the popup. Disabled during panel editing so a drop
        // is not also a click, which is what froze the editor.
        MouseArea {
            anchors.fill: parent
            enabled: !root.panelEditing
            acceptedButtons: Qt.LeftButton
            property bool wasExpanded: false
            onPressed: wasExpanded = root.expanded
            onClicked: root.expanded = !wasExpanded
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: Kirigami.Units.gridUnit * 22
        Layout.preferredHeight: Kirigami.Units.gridUnit * 28
        Layout.maximumHeight: Kirigami.Units.gridUnit * 36
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "folder-cloud"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 1
                    text: "Google Drive"
                    elide: Text.ElideRight
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    text: "Refresh"
                    display: AbstractButton.IconOnly
                    onClicked: root.refresh()

                    PlasmaComponents.ToolTip {
                        text: "Refresh"
                    }
                }
            }
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    visible: root.phase !== "syncing"
                    source: !root.loaded ? "cloudstatus"
                          : root.phase === "error" ? "state-error"
                          : root.phase === "paused" ? "state-warning"
                          : "state-ok"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    Layout.alignment: Qt.AlignTop
                }

                PlasmaComponents.BusyIndicator {
                    visible: root.phase === "syncing"
                    running: visible
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    Layout.alignment: Qt.AlignTop
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        color: root.statusColor
                        text: root.message
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        visible: root.detail !== ""
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        text: root.detail
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            PlasmaExtras.Heading {
                Layout.fillWidth: true
                level: 4
                text: "Recent activity"
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: Kirigami.Units.gridUnit * 16
                Layout.minimumHeight: Kirigami.Units.gridUnit * 10
                Layout.preferredHeight: Kirigami.Units.gridUnit * 16

                ListView {
                    id: activityList
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.rows
                    visible: root.rows.length > 0
                    spacing: Kirigami.Units.smallSpacing

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: PlasmaComponents.ItemDelegate {
                        width: activityList.width
                        hoverEnabled: true
                        onClicked: root.openLocal(modelData.open_path)

                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }

                        ToolTip.visible: hovered
                        ToolTip.delay: 400
                        ToolTip.text: modelData.path || modelData.name

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                source: modelData.icon || "cloudstatus"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                Layout.alignment: Qt.AlignVCenter
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    elide: Text.ElideMiddle
                                    maximumLineCount: 1
                                    text: modelData.name
                                }

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    opacity: 0.65
                                    font: Kirigami.Theme.smallFont
                                    text: modelData.subtitle
                                }
                            }
                        }
                    }
                }

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    visible: root.loaded && root.rows.length === 0 && root.phase !== "error"
                    opacity: 0.7
                    text: "No recent changes"
                }
            }

            PlasmaComponents.Button {
                Layout.fillWidth: true
                icon.name: "folder-open"
                text: "Open Google Drive folder"
                onClicked: {
                    var folder = root.localDir || String(Plasmoid.configuration.localDir || "");
                    root.openLocal(folder);
                }
            }
        }
    }
}
