import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    pluginId: "argbFans"

    StyledText {
        width: parent.width
        text: "Fan & ARGB Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Intervals apply after the shell restarts. The color, brightness, scope and on/off state persist on their own (in ~/.local/state/argb-fans) and survive shell restarts."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "fanPollInterval"
        label: "Fan readout poll interval"
        description: "How often to read RPM and duty from the NCT6798 (hwmon sysfs, essentially free)."
        defaultValue: 3
        minimum: 2
        maximum: 10
        unit: "sec"
    }

    SliderSetting {
        settingKey: "keepAliveInterval"
        label: "ARGB keep-alive interval"
        description: "Static fills fade after ~1-2 minutes when the LED engine sleeps; the widget re-strobes the fill on this cadence."
        defaultValue: 45
        minimum: 20
        maximum: 120
        unit: "sec"
    }

    StringSetting {
        settingKey: "fanctlPath"
        label: "ene-fanctl binary"
        description: "Command or path used to drive the ARGB controller. Leave empty to use the Nix store binary bundled with this plugin."
        placeholder: "(bundled ene-fanctl)"
        defaultValue: ""
    }
}
