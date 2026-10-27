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
    // static | breathing | rainbow | meteor | thermal. Animations run as
    // a foreground child of ene-fanctl's anim-daemon engine
    // (software-driven, per-frame LED RAM writes; the chip's own hardware
    // effects are not yet reverse-engineered upstream). Thermal maps the
    // hotter of CPU package / NVMe composite onto green→red.
    property string pattern: "static"

    // 50..200 (%), scales animation frame rate and meteor pace.
    property int animSpeedPct: 100

    // Thermal inputs, refreshed by the fan poll (-1 = sensor absent).
    property int cpuTempC: -1
    property int nvmeTempC: -1

    // Double-confirm latch for the low-prominence restore button.
    property bool restoreArmed: false

    // Physical calibration, script-settable via DMS plugin settings
    // (~/.config/dms/plugin_settings.json) — the chip cannot report
    // either number (it publishes header capacity only, and daisy
    // chained fans are one wire). 0/absent = auto: rainbow spans the
    // whole header, meteor falls back to the upstream 16-per-fan
    // convention. Wrong values are cosmetic only.
    readonly property int fanLedCount: parseInt(pluginData.fanLedCount) || 0
    readonly property int fanCount: Math.max(1, parseInt(pluginData.fanCount) || 1)

    // Fan state; -1 = nct6798 absent or not read yet.
    property int fanRpm: -1
    property int fanDuty: -1

    readonly property var presets: [
        "FF5252", "FF9800", "FFD600", "69F0AE", "00E5FF",
        "448AFF", "7C4DFF", "FF4081", "FFFFFF"
    ]

    readonly property var patterns: [
        { key: "static", label: "Static" },
        { key: "breathing", label: "Breathe" },
        { key: "rainbow", label: "Rainbow" },
        { key: "meteor", label: "Meteor" },
        { key: "thermal", label: "Thermal" }
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

    // Thermal heat-map: the hotter of CPU package / NVMe composite maps
    // onto hue 120° (green, ≤45°C) → 0° (red, ≥70°C). Returns the
    // current color when no sensor has been read yet.
    function thermalHex() {
        var t = -1;
        if (cpuTempC >= 0)
            t = cpuTempC;
        if (nvmeTempC > t)
            t = nvmeTempC;
        if (t < 0)
            return effectiveHex();
        var lo = 45, hi = 70;
        var k = Math.max(0, Math.min(1, (t - lo) / (hi - lo)));
        var h = (1 - k) / 3;
        var i = Math.floor(h * 6);
        var fr = h * 6 - i;
        var v = 1, p = 0, q = v * (1 - fr), w = v * fr;
        var r = 0, g = 0, b = 0;
        switch (((i % 6) + 6) % 6) {
            case 0: r = v; g = w; b = p; break;
            case 1: r = q; g = v; b = p; break;
            case 2: r = p; g = v; b = w; break;
            case 3: r = p; g = q; b = v; break;
            case 4: r = w; g = p; b = v; break;
            case 5: r = v; g = p; b = q; break;
        }
        return padByte(r * 255) + padByte(g * 255) + padByte(b * 255);
    }

    // The DDropdown shipped inside dux-shell 2.0.0 speaks label-string
    // semantics (options/currentValue/valueChanged carry display labels;
    // the optionValues key mapping is a newer main-branch addition), so
    // map between labels and pattern keys here.
    function patternLabel(k) {
        for (var i = 0; i < patterns.length; i++)
            if (patterns[i].key === k)
                return patterns[i].label;
        return patterns[0].label;
    }

    function patternKeyFromLabel(label) {
        for (var i = 0; i < patterns.length; i++)
            if (patterns[i].label === label)
                return patterns[i].key;
        return "static";
    }

    function patternHex() {
        return pattern === "thermal" ? thermalHex() : effectiveHex();
    }

    function fillWith(hex) {
        if (!lightsOn || fillProc.running)
            return;
        fillProc.command = [
            "sh", "-c",
            "'" + fanctlBin + "' fill " + (scope === 0 ? "0" : "all") + " " + hex + " 2>&1"
        ];
        fillProc.running = true;
    }

    function applyColor() {
        fillWith(patternHex());
    }

    // Animations run as a long-lived foreground child (anim-daemon).
    // pendingAfterKill holds the action to dispatch once killProc has
    // reaped the current daemon: "" | "off" | "restore" | a pattern key.
    property string pendingAfterKill: ""

    function animCommand() {
        var hz = Math.max(5, Math.round(20 * animSpeedPct / 100));
        var mhz = Math.max(10, Math.round(60 * animSpeedPct / 100));
        var speed = animSpeedPct / 100;
        if (pattern === "breathing")
            return ["sh", "-c",
                "'" + fanctlBin + "' anim-daemon breathing " + hz
                + " --colors " + effectiveHex() + " 2>&1"];
        if (pattern === "rainbow") {
            // Auto (no --leds) spans the whole header, so any physical
            // LED count is covered; calibration just tightens the loop.
            // The daemon generates its own colors (upstream ignores
            // --colors there), so brightness reaches it as --scale,
            // applied on the patched fanctl's HSV value channel.
            var r = "'" + fanctlBin + "' anim-daemon rainbow " + hz
                + " --scale " + (brightness / 100);
            if (fanLedCount > 0)
                r += " --leds " + fanLedCount;
            return ["sh", "-c", r + " 2>&1"];
        }
        // Meteor segments per fan, so it needs the calibration; the
        // 16-per-fan fallback is upstream's own convention. Same
        // --scale story as rainbow: the daemon paints with its own
        // palette, so brightness must be handed over explicitly.
        var leds = fanLedCount > 0 ? fanLedCount : 16 * fanCount;
        return ["sh", "-c",
            "'" + fanctlBin + "' anim-daemon meteor " + mhz
            + " --leds " + leds + " --fans " + fanCount
            + " --scale " + (brightness / 100)
            + " --speed " + speed + " 2>&1"];
    }

    function stopAnim(next) {
        pendingAfterKill = next;
        if (!killProc.running)
            killProc.running = true;
    }

    function dispatchAfterKill() {
        var next = pendingAfterKill;
        pendingAfterKill = "";
        if (next === "")
            return;
        if (next === "off") {
            if (!offProc.running) {
                offProc.command = ["sh", "-c", "'" + fanctlBin + "' off all 2>&1"];
                offProc.running = true;
            }
            return;
        }
        if (next === "restore") {
            runRestore();
            return;
        }
        if (!root.lightsOn)
            return;
        if (next === "static" || next === "thermal") {
            applyColor();
            return;
        }
        animProc.command = animCommand();
        animProc.running = true;
    }

    function applyPattern() {
        if (!lightsOn)
            return;
        if (pattern === "static" || pattern === "thermal") {
            if (animProc.running)
                stopAnim(pattern);
            else
                applyColor();
            return;
        }
        if (animProc.running) {
            stopAnim(pattern);
        } else {
            animProc.command = animCommand();
            animProc.running = true;
        }
    }

    function lightsOff() {
        lightsOn = false;
        if (animProc.running) {
            stopAnim("off");
        } else if (!offProc.running) {
            offProc.command = ["sh", "-c", "'" + fanctlBin + "' off all 2>&1"];
            offProc.running = true;
        }
        saveState();
    }

    function saveState() {
        if (saveProc.running)
            return;
        var line = (lightsOn ? "on" : "off") + " "
            + hue.toFixed(3) + " " + sat.toFixed(3) + " " + val.toFixed(3) + " "
            + brightness + " " + scope + " " + pattern + " " + animSpeedPct;
        if (fanManual)
            line += " m" + manualDuty;
        saveProc.command = [
            "sh", "-c",
            "mkdir -p '" + stateDir + "' && echo '" + line + "' > '" + stateDir + "/state'"
        ];
        saveProc.running = true;
    }

    // Guarded one-time LED RAM snapshot (create-if-missing) taken before
    // this widget's first write of the session, so the quiet restore
    // button has something to go back to. Note the first-ever capture on
    // this machine holds the all-off state left by the 2026-10-26 live
    // test — a true factory restore is a power cycle away.
    function startBackup() {
        if (backupProc.running)
            return;
        backupProc.command = [
            "sh", "-c",
            "mkdir -p '" + stateDir + "' && [ -f '" + stateDir + "/led-ram-backup.json' ]"
            + " || '" + fanctlBin + "' backup '" + stateDir + "/led-ram-backup.json'"
        ];
        backupProc.running = true;
    }

    function runRestore() {
        if (restoreProc.running)
            return;
        restoreProc.command = [
            "sh", "-c",
            "'" + fanctlBin + "' restore '" + stateDir + "/led-ram-backup.json' 2>&1"
        ];
        restoreProc.running = true;
    }

    function doRestore() {
        restoreArmed = false;
        lightsOn = false;
        if (animProc.running) {
            stopAnim("restore");
        } else {
            runRestore();
        }
        saveState();
    }

    function loadState() {
        if (loadProc.running)
            return;
        loadProc.running = true;
    }

    // Fan control model: the slider expresses DESIRE only and is enabled
    // just in manual mode — hardware readings never drive it. Board mode
    // shows the live duty in the status line and releases the chip to its
    // own closed loop (fan-set@auto). manualDuty is persisted (token 9,
    // "m<pct>") exclusively through user actions, so a BIOS-curve machine
    // stays curve-driven across reboots.
    property bool fanManual: false
    property int manualDuty: 61

    // Animation speed applies to the three animation patterns only; the
    // slider stays mounted and grays out for static/thermal.
    readonly property bool speedActive: pattern !== "static" && pattern !== "thermal"

    // The picked color only drives static and breathing. Rainbow and
    // meteor derive their own hues, and thermal's color is intrinsic
    // (temperature maps green->red). The color controls gray out when
    // they have no effect instead of hiding (no layout jumps).
    readonly property bool colorActive: pattern === "static"
        || pattern === "breathing"

    function setFanDutyPct(pct) {
        var duty = Math.round(255 * pct / 100);
        duty = Math.max(64, Math.min(255, duty));
        manualDuty = pct;
        fanDuty = duty;
        saveState();
        if (fanSetProc.running)
            return;
        fanSetProc.command = ["systemctl", "start", "fan-set@" + duty];
        fanSetProc.running = true;
    }

    function setFanManual(on) {
        fanManual = on;
        if (on) {
            // Take over from what the fan is doing right now, so the
            // slider starts at reality instead of jumping it. The popout
            // side mirrors manualDuty into the slider (ids inside
            // popoutContent are not visible from here).
            if (fanDuty >= 0)
                manualDuty = Math.max(25, Math.min(100, Math.round(fanDuty / 255 * 100)));
            setFanDutyPct(manualDuty);
        } else if (!fanSetProc.running) {
            // Release the chip to its own closed loop.
            fanSetProc.command = ["systemctl", "start", "fan-set@auto"];
            fanSetProc.running = true;
        }
        saveState();
    }

    Component.onCompleted: {
        // Backup guard first, then state restore chains off its exit so
        // the snapshot can never capture one of our own fills.
        startBackup();
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

    // Long-lived animation child. NEVER stopped via Quickshell signals:
    // live testing showed daemons surviving running=false — five orphans
    // ended up fighting over the controller, wedging every command. All
    // stops go through killProc (pkill keyed on the unique store path,
    // [a] bracket so the pattern cannot match its own shell), and the
    // follow-up action dispatches only after the reaping finished.
    Process {
        id: animProc

        onExited: {
            // Our own kills route through killProc (pendingAfterKill set);
            // only silent deaths — USB drop, crash — land here.
            if (!root.lightsOn || root.pendingAfterKill !== "")
                return;
            ToastService.showError("ARGB animation stopped unexpectedly");
        }
    }

    Process {
        id: killProc

        command: ["sh", "-c",
            "pkill -f 'ene-fanctl [a]nim-daemon' 2>/dev/null; sleep 0.3; " +
            "pkill -9 -f 'ene-fanctl [a]nim-daemon' 2>/dev/null; true"]

        onExited: root.dispatchAfterKill()
    }

    Process {
        id: saveProc
    }

    // One-time LED RAM snapshot; state restore chains off its exit.
    Process {
        id: backupProc

        onExited: root.loadState()
    }

    Process {
        id: restoreProc

        onExited: exitCode => {
            if (exitCode !== 0)
                ToastService.showError("Vendor lighting restore failed (no backup?)");
            else
                ToastService.showInfo("ARGB: vendor lighting restored");
        }
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
                root.pattern = p.length >= 7 && root.patterns.some(pp => pp.key === p[6])
                    ? p[6]
                    : "static";
                var sp = p.length >= 8 ? parseInt(p[7]) : 100;
                root.animSpeedPct = sp >= 50 && sp <= 200 ? sp : 100;
                // Token 9 "m<pct>" = manual fan mode at pct; absent =
                // board control (a bare number from the older format
                // maps to manual as well).
                var t9 = p.length >= 9 ? p[8] : "";
                var md = parseInt(t9.replace("m", ""));
                root.fanManual = t9 !== "";
                root.manualDuty = md >= 25 && md <= 100 ? md : 61;
                root.lightsOn = (p[0] === "on");
            }
        }

        onExited: {
            // Desired state gets re-applied so reality catches up: the
            // anim daemon died with the shell (parking the LEDs dark),
            // static fills faded, pwm resets to the BIOS curve on boot.
            // A power cycle restores lights and duty within seconds of
            // the shell starting; the pill never lies because it tracks
            // what we actively drive, not a probe snapshot.
            if (root.lightsOn)
                root.applyPattern();
            if (root.fanManual)
                root.setFanDutyPct(root.manualDuty);
        }
    }

    // One poll feeds both tabs: "F <rpm> <pwm>" from nct6798 and
    // "T <cpuMillideg> <nvmeMillideg>" from coretemp/nvme (absent
    // sensors stay -1). Prefixed lines keep the parser unambiguous.
    Process {
        id: fanReadProc

        command: [
            "sh", "-c",
            "cpu=-1; nv=-1; " +
            "for d in /sys/class/hwmon/hwmon*; do " +
            "n=$(cat \"$d/name\" 2>/dev/null); " +
            "case \"$n\" in " +
            "nct6798) echo \"F $(cat \"$d/fan2_input\" 2>/dev/null) $(cat \"$d/pwm2\" 2>/dev/null)\";; " +
            "coretemp) cpu=$(cat \"$d/temp1_input\" 2>/dev/null || echo -1);; " +
            "nvme) nv=$(cat \"$d/temp1_input\" 2>/dev/null || echo -1);; " +
            "esac; done; echo \"T $cpu $nv\"; exit 0"
        ]

        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split(/\s+/);
                if (p[0] === "F" && p.length >= 3) {
                    root.fanRpm = parseInt(p[1]);
                    root.fanDuty = parseInt(p[2]);
                } else if (p[0] === "T" && p.length >= 3) {
                    var cpu = parseInt(p[1]);
                    var nv = parseInt(p[2]);
                    root.cpuTempC = cpu > 0 ? Math.round(cpu / 1000) : -1;
                    root.nvmeTempC = nv > 0 ? Math.round(nv / 1000) : -1;
                }
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
        // Animations keep themselves alive (they strobe every frame),
        // so this only runs for the static pattern.
        interval: root.keepAliveMs
        running: root.lightsOn && root.pattern === "static"
        repeat: true
        onTriggered: root.applyColor()
    }

    // Thermal repaint: fresh color every 2s, which doubles as its own
    // keep-alive (well inside the ~1-2 min LED sleep window).
    Timer {
        interval: 2000
        running: root.lightsOn && root.pattern === "thermal"
        repeat: true
        onTriggered: root.applyColor()
    }

    Timer {
        id: commitTimer
        interval: 400
        onTriggered: {
            if (root.lightsOn)
                root.applyPattern();
            root.saveState();
        }
    }

    Timer {
        id: dutyCommitTimer
        interval: 600
        onTriggered: {
            if (root.fanManual)
                root.setFanDutyPct(root.manualDuty);
        }
    }

    Timer {
        id: rearmTimer
        interval: 4000
        onTriggered: root.restoreArmed = false
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
            name: "mode_fan"
            size: root.iconSize
            color: root.lightsOn ? Theme.primary : Theme.surfaceVariantText
        }
    }

    verticalBarPill: Component {
        DIcon {
            name: "mode_fan"
            size: root.iconSize
            color: root.lightsOn ? Theme.primary : Theme.surfaceVariantText
        }
    }

    // 400 matches the shell's own default popout width (DPopout). The
    // visible card is 400 - 2*16 content padding = 368; content budget
    // 344 after margins. The picker row's hard minimum (180 + 12 + 136
    // scope chips = 328) needs that slack — at 380 the budget was 324
    // and the row pushed everything 4px past the clip.
    popoutWidth: 400
    // Fixed 790: fits the fully expanded tab (pattern/brightness/speed/
    // scope/custom color/presets/buttons/restore, ~750 of chrome+content).
    // An adaptive write-back (popoutHeight from measured content) froze
    // the whole shell — the write resizes the window, some child's
    // implicit height shifts a pixel, sync fires again: a synchronous
    // signal loop. Do not reintroduce.
    popoutHeight: 790

    popoutContent: Component {
        PopoutComponent {
            id: popoutRoot

            headerText: "Fan & ARGB"
            detailsText: ""
            showCloseButton: true

            Item {
                id: outerItem
                width: parent.width
                implicitHeight: root.popoutHeight - popoutRoot.headerHeight - Theme.spacingXL

                ColumnLayout {
                    id: outerCol
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
                        speedSlider.value = root.animSpeedPct;
                        if (root.fanDuty >= 0)
                            dutySlider.value = root.manualDuty;
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

                        function onAnimSpeedPctChanged() {
                            speedSlider.value = root.animSpeedPct;
                        }

                        // Hardware readings never enter the slider — the
                        // status line owns live values; the slider holds
                        // desire only.
                    }

                    DTabBar {
                        id: tabs
                        // This Column is a plain positioning container, not
                        // a Layout: Layout.* attached props are ignored
                        // here, so widths must be explicit. Without them
                        // StackLayout defaults to its widest implicit child
                        // (the Fan tab note text, several hundred px) and
                        // everything clips at the popout's right edge.
                        width: parent.width
                        model: [
                            { text: "ARGB", icon: "palette" },
                            { text: "Fan", icon: "mode_fan" }
                        ]
                        onTabClicked: index => tabs.currentIndex = index
                    }

                    StackLayout {
                        id: tabStack
                        width: parent.width
                        height: parent.height - tabs.height - parent.spacing
                        currentIndex: tabs.currentIndex

                        // ---- ARGB tab ----
                        // Scrollable: the tab holds more rows than the
                        // fixed-height popout can always show; without this
                        // the bottom rows (presets, buttons, restore) spill
                        // past the popout's lower edge.
                        Flickable {
                            id: argbFlick
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            // Flickable's default implicitHeight is 0 —
                            // StackLayout reads the current page's implicit
                            // height to size the content-driven popout, so
                            // without this the whole tab collapses to zero
                            // and every control stacks in one spot.
                            implicitHeight: argbCol.implicitHeight
                            contentWidth: width
                            contentHeight: argbCol.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds

                            // Layout wrapper for every control below.
                            // MISSING WRAPPER = the great collapse: without
                            // this ColumnLayout the controls are unmanaged
                            // Flickable children and all pile up at (0,0).
                            ColumnLayout {
                                id: argbCol
                                width: parent.width
                                spacing: Theme.spacingS

                            StyledText {
                                text: "Pattern"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            DDropdown {
                                Layout.fillWidth: true
                                // Layouts treat implicitWidth as the minimum
                                // unless zeroed; without this the dropdown
                                // and the DSliders below overflow the popout.
                                Layout.minimumWidth: 0
                                Layout.rightMargin: Theme.spacingS
                                options: root.patterns.map(p => p.label)
                                currentValue: root.patternLabel(root.pattern)
                                onValueChanged: value => {
                                    root.pattern = root.patternKeyFromLabel(value);
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
                                Layout.minimumWidth: 0
                                Layout.rightMargin: Theme.spacingS
                                minimum: 10
                                maximum: 100
                                unit: "%"
                                onSliderValueChanged: {
                                    root.brightness = Math.round(value);
                                    commitTimer.restart();
                                }
                            }

                            StyledText {
                                text: "Animation speed"
                                opacity: root.speedActive ? 1 : 0.4
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            DSlider {
                                id: speedSlider
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.rightMargin: Theme.spacingS
                                enabled: root.speedActive
                                opacity: root.speedActive ? 1 : 0.4
                                minimum: 50
                                maximum: 200
                                unit: "%"
                                onSliderValueChanged: {
                                    root.animSpeedPct = Math.round(value);
                                    commitTimer.restart();
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingM

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

                            StyledText {
                                text: "Custom color"
                                opacity: root.colorActive ? 1 : 0.4
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                opacity: root.colorActive ? 1 : 0.4
                                enabled: root.colorActive
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
                                        Layout.minimumWidth: 0
                                        text: "#" + root.effectiveHex()
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                opacity: root.colorActive ? 1 : 0.4
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
                                Layout.minimumWidth: 0
                                Layout.rightMargin: Theme.spacingS
                                enabled: root.colorActive
                                opacity: root.colorActive ? 1 : 0.4
                                minimum: 0
                                maximum: 360
                                onSliderValueChanged: {
                                    root.hue = Math.max(0, Math.min(360, value)) / 360;
                                    svPicker.hue = root.hue;
                                    commitTimer.restart();
                                }
                            }

                            StyledText {
                                text: "Presets"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
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
                                id: btnRow
                                Layout.fillWidth: true
                                spacing: Theme.spacingM

                                // StyledRect buttons, not DButton: DButton
                                // pins its own implicit width as an internal
                                // minimum that external Layout.minimumWidth
                                // cannot override, so two side-by-side
                                // fillWidth buttons held the row at ~450px
                                // and the Off button clipped at the popout
                                // edge. Same pattern as the onedrive plugin.
                                StyledRect {
                                    id: lightsBtn
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    height: 40
                                    radius: Theme.cornerRadius
                                    color: lightsArea.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                                    border.color: Theme.outlineStrong
                                    border.width: 1

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: root.lightsOn ? "Re-apply" : "Lights on"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        color: Theme.onPrimary
                                    }

                                    MouseArea {
                                        id: lightsArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.lightsOn = true;
                                            root.applyPattern();
                                            root.saveState();
                                        }
                                    }
                                }

                                StyledRect {
                                    id: offBtn
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    height: 40
                                    radius: Theme.cornerRadius
                                    color: offArea.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                                    border.color: Theme.outlineStrong
                                    border.width: 1

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: "Off"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        color: Theme.onPrimary
                                    }

                                    MouseArea {
                                        id: offArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.lightsOff()
                                    }
                                }
                            }

                            // Deliberately quiet: low-prominence, double-
                            // confirm, auto-rearms after 4s. Restores the
                            // one-time LED RAM snapshot (see startBackup).
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.restoreArmed
                                    ? "Click again to restore vendor lighting"
                                    : "Restore vendor lighting"
                                font.pixelSize: Theme.fontSizeSmall
                                font.underline: restoreArea.containsMouse
                                color: root.restoreArmed
                                    ? Theme.error
                                    : (restoreArea.containsMouse ? Theme.surfaceText : Theme.surfaceVariantText)

                                MouseArea {
                                    id: restoreArea
                                    anchors.fill: parent
                                    anchors.margins: -Theme.spacingS
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!root.restoreArmed) {
                                            root.restoreArmed = true;
                                            rearmTimer.restart();
                                        } else {
                                            root.doRestore();
                                        }
                                    }
                                }
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

                            // Live status line — the only place hardware
                            // readings are shown. Source is honest: Board
                            // until manual takes over.
                            StyledText {
                                Layout.fillWidth: true
                                text: root.fanRpm < 0
                                    ? "nct6798 not found — is nct6775 loaded?"
                                    : (root.fanManual ? "Manual" : "Board")
                                      + " · duty " + Math.round(root.fanDuty / 255 * 100) + "%"
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.fanRpm < 0 ? Theme.error : Theme.surfaceVariantText
                            }

                            Row {
                                spacing: Theme.spacingS

                                Repeater {
                                    model: [
                                        { key: false, label: "Board" },
                                        { key: true, label: "Manual" }
                                    ]

                                    StyledRect {
                                        width: 84
                                        height: 30
                                        radius: Theme.cornerRadius
                                        color: fanCtlArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                                        border.color: root.fanManual === modelData.key ? Theme.primary : Theme.outlineStrong
                                        border.width: root.fanManual === modelData.key ? 2 : 1

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceText
                                        }

                                        MouseArea {
                                            id: fanCtlArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.setFanManual(modelData.key);
                                                dutySlider.value = root.manualDuty;
                                            }
                                        }
                                    }
                                }
                            }

                            DSlider {
                                id: dutySlider
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.rightMargin: Theme.spacingS
                                enabled: root.fanManual
                                opacity: root.fanManual ? 1 : 0.4
                                minimum: 25
                                maximum: 100
                                unit: "%"
                                onSliderValueChanged: {
                                    root.manualDuty = Math.round(value);
                                    dutyCommitTimer.restart();
                                }
                            }

                            StyledRect {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                height: 40
                                opacity: root.fanManual ? 1 : 0.4
                                radius: Theme.cornerRadius
                                color: defaultDutyArea.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                                border.color: Theme.outlineStrong
                                border.width: 1

                                StyledText {
                                    anchors.centerIn: parent
                                    text: "Back to default 61%"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: Theme.onPrimary
                                }

                                MouseArea {
                                    id: defaultDutyArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: root.fanManual
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.setFanDutyPct(61);
                                        dutySlider.value = 61;
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: "Manual writes go through the privileged fan-set@.service (duty floor 25%); Board releases the chip to its own closed loop (fan-set@auto)."
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
