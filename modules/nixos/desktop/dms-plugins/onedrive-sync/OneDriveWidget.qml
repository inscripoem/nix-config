// OneDrive sync status widget for DankMaterialShell.
//
// Bar pill is a bare cloud icon; clicking opens a popout with the status
// breakdown. Data sources:
//   1. `~/.config/onedrive/monitor-status.json` — the official machine-
//      readable interface published by monitor mode (onedrive >= 2.5.12).
//      Probed at runtime; when present it is the sole status source and
//      the probe below never runs. Re-read on the liveness cadence.
//   2. `systemctl --user is-active onedrive` — liveness, cheap, fast cadence.
//   3. `onedrive --display-sync-status` — convergence probe for clients
//      without monitor-status.json (2.5.11): one API call and a full
//      sync_dir filesystem scan per run (~10s), so it runs on a slow
//      cadence only. This is a no-sync operation: it queries a dry-run copy
//      of items.sqlite3 and never touches the singleton lock, so it is safe
//      alongside the running monitor. On 2.5.11 it can crash on nameless
//      delta tombstones (upstream bug) — rendered as the "error" state.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "onedrive-sync"

    // "@onedrive@" is substituted with the absolute store path at build time
    // (see dms-shell.nix): the DMS session PATH does not reliably carry the
    // per-user profile bin dir, so a bare "onedrive" lookup can fail.
    property string onedriveBin: pluginData.onedrivePath || "@onedrive@"
    readonly property int livenessInterval: (pluginData.pollInterval ?? 15) * 1000
    readonly property int checkInterval: (pluginData.checkInterval ?? 300) * 1000
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string syncDir: homeDir + "/OneDrive"
    readonly property string statusFilePath: homeDir + "/.config/onedrive/monitor-status.json"

    // Runtime state.
    property bool serviceActive: false
    // unknown|stopped|synced|syncing|pending|offline|error
    property string syncState: "unknown"
    property date lastCheck: new Date(0)
    property bool checking: false
    // Set while the JSON source is live; probe-only counters below.
    property bool statusFileAlive: false
    property int lastCycleFailures: 0

    readonly property string iconName: {
        if (checking || syncState === "syncing")
            return "sync";
        if (syncState === "stopped")
            return "cloud_off";
        if (syncState === "synced")
            return "cloud_done";
        if (syncState === "pending")
            return "cloud_sync";
        if (syncState === "offline" || syncState === "error")
            return "cloud_off";
        return "cloud";
    }

    readonly property color iconColor: {
        if (syncState === "synced")
            return Theme.primary;
        if (syncState === "offline" || syncState === "error")
            return Theme.error;
        if (syncState === "stopped" || syncState === "unknown")
            return Theme.surfaceVariantText;
        return Theme.surfaceText;
    }

    readonly property string stateText: {
        if (checking)
            return "Checking";
        if (syncState === "stopped")
            return "Stopped";
        if (syncState === "synced")
            return "Synced";
        if (syncState === "syncing")
            return "Syncing";
        if (syncState === "pending")
            return "Pending";
        if (syncState === "offline")
            return "Offline";
        if (syncState === "error")
            return "Check failed";
        return "Unknown";
    }

    readonly property string stateMessage: {
        if (checking)
            return "Querying Microsoft OneDrive…";
        if (syncState === "stopped")
            return "The onedrive service is not running.";
        if (syncState === "synced") {
            if (statusFileAlive)
                return "The last monitor cycle completed successfully.";
            return "Your local directory matches the data online.";
        }
        if (syncState === "syncing")
            return "A sync cycle is in progress.";
        if (syncState === "pending") {
            if (statusFileAlive)
                return "The last cycle finished with " + lastCycleFailures
                       + " failed item(s); they will be retried.";
            return "There are changes waiting to be synced.";
        }
        if (syncState === "offline")
            return "Microsoft OneDrive is not reachable.";
        if (syncState === "error") {
            if (statusFileAlive)
                return "The last cycle did not complete cleanly. Check the service journal.";
            return "The status query itself failed (known onedrive 2.5.11 bug with nameless delta items). The monitor may still be syncing fine.";
        }
        return "Waiting for the first sync cycle to complete.";
    }

    readonly property string lastCheckedText: {
        if (lastCheck.getTime() === 0)
            return "never";
        return relativeTime(lastCheck) + " (" + Qt.formatDateTime(lastCheck, "HH:mm") + ")";
    }

    readonly property var detailRows: {
        var rows = [
            {
                label: "Service",
                value: serviceActive ? "Running" : "Stopped"
            },
            {
                label: "Sync directory",
                value: "~/OneDrive"
            },
            {
                label: statusFileAlive ? "Last successful cycle" : "Last checked",
                value: lastCheckedText
            }
        ];
        if (statusFileAlive)
            rows.push({
                label: "Status source",
                value: "monitor-status.json"
            });
        return rows;
    }

    function relativeTime(d) {
        var minutes = Math.floor((Date.now() - d.getTime()) / 60000);
        if (minutes < 1)
            return "just now";
        if (minutes < 60)
            return minutes + "m ago";
        var hours = Math.floor(minutes / 60);
        if (hours < 24)
            return hours + "h ago";
        return Math.floor(hours / 24) + "d ago";
    }

    // Timestamps in the status file carry microsecond precision that JS
    // Date cannot parse; truncate the fractional part before converting.
    function parseTs(s) {
        if (!s || s === "")
            return null;
        var normalized = s.replace(/\.\d+/, "");
        var d = new Date(normalized);
        return isNaN(d.getTime()) ? null : d;
    }

    function runLiveness() {
        if (livenessProc.running)
            return;
        livenessProc.running = true;
    }

    function runStatusCheck() {
        // If the official status file exists (onedrive >= 2.5.12), it owns
        // the status and the probe never runs.
        if (statusFileAlive)
            return;
        if (!serviceActive || statusProc.running)
            return;
        checking = true;
        statusProc.lines = [];
        statusProc.command = ["sh", "-c", onedriveBin + " --display-sync-status 2>&1"];
        statusProc.running = true;
    }

    function checkStatusFile() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + statusFilePath);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4)
                return;
            if (!xhr.responseText) {
                statusFileAlive = false;
                return;
            }
            try {
                var data = JSON.parse(xhr.responseText);
                statusFileAlive = true;
                serviceActive = true;
                syncState = jsonToState(data);
                var ok = parseTs(data.sync && data.sync.last_successful_sync_at);
                if (ok)
                    lastCheck = ok;
            } catch (e) {
                statusFileAlive = false;
            }
        };
        xhr.send();
    }

    // Map the 2.5.12 monitor-status document onto this widget's states.
    // Field semantics per upstream docs: process.state is syncing|idle|
    // degraded; sync.last_cycle.result is success|partial_failure|
    // service_unreachable|time_unsafe|interrupted|never_run.
    function jsonToState(data) {
        var reach = data.conditions && data.conditions.onedrive_reachability;
        if (reach === "unreachable")
            return "offline";
        if (data.process && data.process.state === "syncing")
            return "syncing";
        var lc = (data.sync && data.sync.last_cycle) || {};
        lastCycleFailures = (lc.download_failures || 0)
            + (lc.upload_failures || 0)
            + (lc.recycle_bin_failures || 0);
        switch (lc.result) {
            case "success":
                return "synced";
            case "partial_failure":
                return "pending";
            case "service_unreachable":
                return "offline";
            case "time_unsafe":
            case "interrupted":
                return "error";
            default:
                // never_run or absent: monitor just started, first cycle
                // has not finished yet.
                return "unknown";
        }
    }

    Component.onCompleted: {
        runLiveness();
        checkStatusFile();
    }

    Process {
        id: livenessProc

        command: ["systemctl", "--user", "is-active", "onedrive"]
        stdout: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    root.serviceActive = (line.trim() === "active");
            }
        }

        onExited: {
            if (!root.serviceActive) {
                root.syncState = "stopped";
            } else if (root.syncState === "stopped" || root.syncState === "unknown") {
                root.runStatusCheck();
            }
            root.checkStatusFile();
        }
    }

    Process {
        id: statusProc

        property var lines: []

        stdout: SplitParser {
            onRead: line => statusProc.lines.push(line)
        }

        onExited: exitCode => {
            const out = statusProc.lines.join("\n");
            root.checking = false;
            root.lastCheck = new Date();
            const reached = out.indexOf("Successfully reached") !== -1;
            const noPending = out.indexOf("no pending changes") !== -1;
            // The 2.5.11 status query can crash parsing a delta item without
            // a "name" key (JSONException, exit 1) — that is a probe error,
            // not evidence of pending work.
            if (!reached)
                root.syncState = "offline";
            else if (exitCode !== 0)
                root.syncState = "error";
            else if (noPending)
                root.syncState = "synced";
            else
                root.syncState = "pending";
        }
    }

    Timer {
        interval: root.livenessInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.runLiveness()
    }

    Timer {
        interval: root.checkInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.runStatusCheck()
    }

    horizontalBarPill: Component {
        DankIcon {
            name: root.iconName
            size: root.iconSize
            color: root.iconColor
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: root.iconName
            size: root.iconSize
            color: root.iconColor
        }
    }

    popoutWidth: 340
    popoutHeight: 280

    popoutContent: Component {
        PopoutComponent {
            id: popoutRoot

            headerText: "OneDrive Sync"
            detailsText: ""
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - popoutRoot.headerHeight - popoutRoot.detailsHeight - Theme.spacingXL

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingM

                    Row {
                        id: heroRow
                        width: parent.width
                        spacing: Theme.spacingM

                        DankIcon {
                            name: root.iconName
                            size: 36
                            color: root.iconColor
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: heroRow.width - 36 - Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingXS

                            StyledText {
                                text: root.stateText
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: root.iconColor
                            }

                            StyledText {
                                width: parent.width
                                text: root.stateMessage
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.withAlpha(Theme.outlineStrong, 0.35)
                    }

                    Repeater {
                        model: root.detailRows

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM

                            StyledText {
                                width: 150
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                width: parent.width - 150 - Theme.spacingM
                                text: modelData.value
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        StyledRect {
                            width: (parent.width - Theme.spacingM) / 2
                            height: 40
                            radius: Theme.cornerRadius
                            color: openArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            border.color: Theme.outlineStrong
                            border.width: 1

                            StyledText {
                                anchors.centerIn: parent
                                text: "Open folder"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                            }

                            MouseArea {
                                id: openArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Quickshell.execDetached(["xdg-open", root.syncDir]);
                                    popoutRoot.closePopout();
                                }
                            }
                        }

                        // The manual probe only exists for the pre-2.5.12
                        // fallback; with monitor-status.json live the file is
                        // refreshed by the monitor itself.
                        StyledRect {
                            visible: !root.statusFileAlive
                            width: (parent.width - Theme.spacingM) / 2
                            height: 40
                            radius: Theme.cornerRadius
                            color: refreshArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            border.color: Theme.outlineStrong
                            border.width: 1

                            StyledText {
                                anchors.centerIn: parent
                                text: root.checking ? "Checking…" : "Refresh now"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                            }

                            MouseArea {
                                id: refreshArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root.checking
                                onClicked: {
                                    root.runStatusCheck();
                                    ToastService.showInfo("OneDrive: convergence check started");
                                    popoutRoot.closePopout();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
