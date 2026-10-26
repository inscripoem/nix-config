// Fan & ARGB control widget for DankMaterialShell.
//
// Two tabs over two hardware chains on the Maxsun MS-Terminator B760M D4:
//   ARGB — ENE 6K7750 USB controller driven by the ene-fanctl CLI. The
//     chip's hidraw interface is a decoy; ene-fanctl speaks raw vendor
//     control transfers. Static fills fade after ~1-2 minutes (the LED
//     engine sleeps), so a keep-alive Timer re-strokes the fill while
//     the lights are on. Group 0 is the 128-LED fan ring chain; "All"
//     also covers the two status LEDs and the 6 accent-strip LEDs.
//   Fan — NCT6798 (nct6775), pwm2 = CPU_FAN with every case fan in
//     series. Reads come from hwmon sysfs; writes go through the
//     privileged fan-set@<duty>.service template (polkit allows wheel
//     to start exactly that unit), which clamps duty to >= 25%.
//
// Widget state (on/off, hue/sat/val, brightness, scope) persists as one
// line in ~/.local/state/argb-fans/ and is re-applied on shell start —
// plugin settings are read-only inside widgets, so the widget owns this
// file. "@enefanctl@" is substituted with the absolute store path at
// build time (see dms-shell.nix).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "argb-fans"

    property string fanctlBin: pluginData.fanctlPath || "@enefanctl@"
    readonly property string stateDir: (Quickshell.env("HOME") || "") + "/.local/state/argb-fans"
    readonly property int keepAliveMs: (pluginData.keepAliveInterval ?? 45) * 1000
    readonly property int fanPollMs: (pluginData.fanPollInterval ?? 3) * 1000

    // ARGB state. hue/sat/val are the source of truth; brightness
    // scales the RGB at send time.
    property bool lightsOn: false
    property real hue: 0.72
    property real sat: 1.0
    property real val: 1.0
    property int brightness: 100  // 10..100 %
    property int scope: 0  // 0 = fan group, 1 = all groups

    // Fan state; -1 = nct6798 absent or not read yet.
    property int fanRpm: -1
    property int fanDuty: -1

    // Duty intent from the slider, in percent. Root-level Process and
    // Timer objects cannot reference ids inside popoutContent (QML ids
    // are scoped to their Component), so the debounced commit reads
    // this instead of the slider directly.
    property int pendingDuty: 61

    readonly property var presets: [
        "FF5252", "FF9800", "FFD600", "69F0AE", "00E5FF",
        "448AFF", "7C4DFF", "FF4081", "FFFFFF"
    ]

    function padByte(n) {
        n = Math.max(0, Math.min(255, Math.round(n)));
        return ("0" + n.toString(16)).slice(-2).toUpperCase();
    }

    // HSV -> scaled hex (brightness factor applied here). Channel
    // order R,G,B here; ene-fanctl's fill takes a plain RRGGBB and
    // knows the chip's R,B,G RAM order itself.
    function effectiveHex() {
        var f = brightness / 100;
        var h = hue, s = sat, v = val * f;
        var i = Math.floor(h * 6);
        var fr = h * 6 - i;
        var p = v * (1 - s), q = v * (1 - fr * s), t = v * (1 - (1 - fr) * s);
        var r = 0, g = 0, b = 0;
        switch (((i % 6) + 6) % 6) {
            case 0: r = v; g = t; b = p; break;
            case 1: r = q; g = v; b = p; break;
            case 2: r = p; g = v; b = t; break;
            case 3: r = p; g = q; b = v; break;
            case 4: r = t; g = p; b = v; break;
            case 5: r = v; g = p; b = q; break;
        }
        return padByte(r * 255) + padByte(g * 255) + padByte(b * 255);
    }

    function hexToHsv(h) {
        var r = parseInt(h.substr(0, 2), 16) / 255;
        var g = parseInt(h.substr(2, 2), 16) / 255;
        var b = parseInt(h.substr(4, 2), 16) / 255;
        var mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
        var hh = 0;
        if (d > 0) {
            if (mx === r) hh = ((g - b) / d + 6) % 6;
            else if (mx === g) hh = (b - r) / d + 2;
            else hh = (r - g) / d + 4;
            hh /= 6;
        }
        return [hh, mx === 0 ? 0 : d / mx, mx];
    }

    function applyColor() {
        if (!lightsOn || fillProc.running)
            return;
        fillProc.command = [
            "sh", "-c",
            "'" + fanctlBin + "' fill " + (scope === 0 ? "0" : "all") + " " + effectiveHex() + " 2>&1"
        ];
        fillProc.running = true;
    }

    function lightsOff() {
        lightsOn = false;
        if (!offProc.running) {
            offProc.command = ["sh", "-c", "'" + fanctlBin + "' off all 2>&1"];
            offProc.running = true;
        }
        saveState();
    }

    function saveState() {
        if (saveProc.running)
            return;
        saveProc.command = [
            "sh", "-c",
            "mkdir -p '" + stateDir + "' && echo '" + (lightsOn ? "on" : "off") + " "
            + hue.toFixed(3) + " " + sat.toFixed(3) + " " + val.toFixed(3) + " "
            + brightness + " " + scope + "' > '" + stateDir + "/state'"
        ];
        saveProc.running = true;
    }

    function loadState() {
        if (loadProc.running)
            return;
        loadProc.running = true;
    }

    function setFanDutyPct(pct) {
        var duty = Math.round(255 * pct / 100);
        duty = Math.max(64, Math.min(255, duty));
        fanDuty = duty;
        if (fanSetProc.running)
            return;
        fanSetProc.command = ["systemctl", "start", "fan-set@" + duty];
        fanSetProc.running = true;
    }

    Component.onCompleted: {
        loadState();
        fanReadProc.running = true;
    }

    Process {
        id: fillProc

        stdout: SplitParser {
            onRead: line => { }
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                ToastService.showError("ARGB write failed — is the ENE controller on USB?");
        }
    }

    Process {
        id: offProc

        onExited: exitCode => {
            if (exitCode !== 0)
                ToastService.showError("ARGB off command failed");
        }
    }

    Process {
        id: saveProc
    }

    Process {
        id: loadProc

        command: ["sh", "-c", "cat '" + root.stateDir + "/state' 2>/dev/null"]

        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split(/\s+/);
                if (p.length < 6 || (p[0] !== "on" && p[0] !== "off"))
                    return;
                root.hue = parseFloat(p[1]);
                root.sat = parseFloat(p[2]);
                root.val = parseFloat(p[3]);
                root.brightness = parseInt(p[4]);
                root.scope = parseInt(p[5]);
                if (p[0] === "on")
                    root.lightsOn = true;
            }
        }

        onExited: {
            // Restore after a shell restart only once the state is in.
            if (root.lightsOn)
                root.applyColor();
        }
    }

    Process {
        id: fanReadProc

        command: [
            "sh", "-c",
            "for d in /sys/class/hwmon/hwmon*; do " +
            "if [ \"$(cat \"$d/name\" 2>/dev/null)\" = \"nct6798\" ]; then " +
            "echo \"$(cat \"$d/fan2_input\") $(cat \"$d/pwm2\")\"; exit 0; fi; " +
            "done; exit 1"
        ]

        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split(/\s+/);
                if (p.length >= 2) {
                    root.fanRpm = parseInt(p[0]);
                    root.fanDuty = parseInt(p[1]);
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.fanRpm = -1;
                root.fanDuty = -1;
            }
        }
    }

    Process {
        id: fanSetProc

        onExited: exitCode => {
            if (exitCode !== 0)
                ToastService.showError("Fan duty write failed (fan-set@.service)");
        }
    }

    Timer {
        // Re-stroke static fills so they survive the LED engine's
        // ~1-2 min sleep. Also self-heals after suspend (controller
        // drops off USB; the next tick re-fills once it re-enumerates).
        interval: root.keepAliveMs
        running: root.lightsOn
        repeat: true
        onTriggered: root.applyColor()
    }

    Timer {
        id: commitTimer
        interval: 400
        onTriggered: {
            if (root.lightsOn)
                root.applyColor();
            root.saveState();
        }
    }

    Timer {
        id: dutyCommitTimer
        interval: 600
        onTriggered: root.setFanDutyPct(root.pendingDuty)
    }

    Timer {
        interval: root.fanPollMs
        running: true
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            if (!fanReadProc.running)
                fanReadProc.running = true;
        }
    }

    horizontalBarPill: Component {
        DIcon {
            name: "palette"
            size: root.iconSize
            color: root.lightsOn ? Theme.primary : Theme.surfaceVariantText
        }
    }

    verticalBarPill: Component {
        DIcon {
            name: "palette"
            size: root.iconSize
            color: root.lightsOn ? Theme.primary : Theme.surfaceVariantText
        }
    }

    popoutWidth: 380
    popoutHeight: 560

    popoutContent: Component {
        PopoutComponent {
            id: popoutRoot

            headerText: "Fan & ARGB"
            detailsText: ""
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - popoutRoot.headerHeight - Theme.spacingXL

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingM

                    // Control values are pushed imperatively (never bound)
                    // so drags cannot fight a binding. This block lives
                    // inside popoutContent because the control ids are
                    // only visible in this Component's scope.
                    Component.onCompleted: {
                        svPicker.hue = root.hue;
                        svPicker.saturation = root.sat;
                        svPicker.value = root.val;
                        hueSlider.value = Math.round(root.hue * 360);
                        brightnessSlider.value = root.brightness;
                        if (root.fanDuty >= 0)
                            dutySlider.value = Math.round(root.fanDuty / 255 * 100);
                    }

                    Connections {
                        target: root

                        function onHueChanged() {
                            svPicker.hue = root.hue;
                        }

                        function onSatChanged() {
                            svPicker.saturation = root.sat;
                        }

                        function onValChanged() {
                            svPicker.value = root.val;
                        }

                        function onBrightnessChanged() {
                            brightnessSlider.value = root.brightness;
                        }

                        // Equality-guarded so a push never re-triggers the
                        // slider handler (which would commit in a loop).
                        function onFanDutyChanged() {
                            if (root.fanDuty < 0)
                                return;
                            var pct = Math.round(root.fanDuty / 255 * 100);
                            if (!dutySlider.isDragging && dutySlider.value !== pct)
                                dutySlider.value = pct;
                        }
                    }

                    DTabBar {
                        id: tabs
                        Layout.fillWidth: true
                        model: [
                            { text: "ARGB", icon: "palette" },
                            { text: "Fan", icon: "mode_fan" }
                        ]
                        onTabClicked: index => tabs.currentIndex = index
                    }

                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: tabs.currentIndex

                        // ---- ARGB tab ----
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingM

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingM

                                DSaturationValuePicker {
                                    id: svPicker
                                    Layout.preferredWidth: 180
                                    Layout.preferredHeight: 180
                                    onColorChanged: (s, v) => {
                                        root.sat = s;
                                        root.val = v;
                                        commitTimer.restart();
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingS

                                    StyledText {
                                        text: "Color"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }

                                    StyledRect {
                                        width: 44
                                        height: 44
                                        radius: 22
                                        color: "#" + root.effectiveHex()
                                        border.color: Theme.outlineStrong
                                        border.width: 1
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "#" + root.effectiveHex()
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        elide: Text.ElideRight
                                    }

                                    Item { Layout.fillHeight: true }

                                    StyledText {
                                        text: "Scope"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }

                                    Row {
                                        spacing: Theme.spacingS

                                        Repeater {
                                            model: ["Fans", "All"]

                                            StyledRect {
                                                width: 64
                                                height: 30
                                                radius: Theme.cornerRadius
                                                color: scopeArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                                                border.color: root.scope === index ? Theme.primary : Theme.outlineStrong
                                                border.width: root.scope === index ? 2 : 1

                                                StyledText {
                                                    anchors.centerIn: parent
                                                    text: modelData
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    color: Theme.surfaceText
                                                }

                                                MouseArea {
                                                    id: scopeArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.scope = index;
                                                        commitTimer.restart();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Hue spectrum strip + slider.
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Repeater {
                                    model: 12

                                    StyledRect {
                                        Layout.preferredWidth: 1
                                        Layout.fillWidth: true
                                        height: 6
                                        radius: 2
                                        color: Qt.hsla(index / 12, 1, 0.5, 1)
                                    }
                                }
                            }

                            DSlider {
                                id: hueSlider
                                Layout.fillWidth: true
                                minimum: 0
                                maximum: 360
                                onSliderValueChanged: {
                                    root.hue = Math.max(0, Math.min(360, value)) / 360;
                                    svPicker.hue = root.hue;
                                    commitTimer.restart();
                                }
                            }

                            StyledText {
                                text: "Brightness"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            DSlider {
                                id: brightnessSlider
                                Layout.fillWidth: true
                                minimum: 10
                                maximum: 100
                                unit: "%"
                                onSliderValueChanged: {
                                    root.brightness = Math.round(value);
                                    commitTimer.restart();
                                }
                            }

                            Row {
                                Layout.fillWidth: true
                                spacing: Theme.spacingS

                                Repeater {
                                    model: root.presets

                                    StyledRect {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: "#" + modelData
                                        border.color: presetArea.containsMouse ? Theme.primary : Theme.outlineStrong
                                        border.width: 1

                                        MouseArea {
                                            id: presetArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var hsv = root.hexToHsv(modelData);
                                                root.hue = hsv[0];
                                                root.sat = hsv[1];
                                                root.val = hsv[2];
                                                commitTimer.restart();
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingM

                                DButton {
                                    Layout.fillWidth: true
                                    text: root.lightsOn ? "Re-apply" : "Lights on"
                                    onClicked: {
                                        root.lightsOn = true;
                                        root.applyColor();
                                        root.saveState();
                                    }
                                }

                                DButton {
                                    Layout.fillWidth: true
                                    text: "Off"
                                    onClicked: root.lightsOff()
                                }
                            }
                        }

                        // ---- Fan tab ----
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingM

                            RowLayout {
                                Layout.fillWidth: true

                                StyledText {
                                    text: "CPU fan"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }

                                Item { Layout.fillWidth: true }

                                StyledText {
                                    text: root.fanRpm >= 0 ? root.fanRpm + " RPM" : "nct6798 not found"
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.Bold
                                    color: root.fanRpm >= 0 ? Theme.surfaceText : Theme.error
                                }
                            }

                            StyledText {
                                text: root.fanDuty >= 0
                                    ? "Duty " + Math.round(root.fanDuty / 255 * 100) + "%"
                                    : "Duty unknown"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            DSlider {
                                id: dutySlider
                                Layout.fillWidth: true
                                minimum: 25
                                maximum: 100
                                unit: "%"
                                onSliderValueChanged: {
                                    root.pendingDuty = Math.round(value);
                                    dutyCommitTimer.restart();
                                }
                            }

                            DButton {
                                Layout.fillWidth: true
                                text: "Back to default 61%"
                                onClicked: {
                                    root.pendingDuty = 61;
                                    root.setFanDutyPct(61);
                                    dutySlider.value = 61;
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: "Writes go through the privileged fan-set@.service (duty floor 25%). The board EC also drives this channel; if the value snaps back, the EC is overriding it."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }
}
