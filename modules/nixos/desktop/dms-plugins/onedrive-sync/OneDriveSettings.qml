import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root

    pluginId: "onedriveSync"

    StyledText {
        width: parent.width
        text: "OneDrive Sync Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Intervals apply after the shell restarts. The convergence check runs 'onedrive --display-sync-status', which costs one API call and scans the sync directory, so keep it on a slow cadence."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "pollInterval"
        label: "Service liveness poll interval"
        description: "How often to ask systemd whether the onedrive service is running."
        defaultValue: 15
        minimum: 5
        maximum: 120
        unit: "sec"
    }

    SliderSetting {
        settingKey: "checkInterval"
        label: "Convergence check interval"
        description: "How often to run a full sync-status check against Microsoft OneDrive."
        defaultValue: 300
        minimum: 120
        maximum: 1800
        unit: "sec"
    }

    StringSetting {
        settingKey: "onedrivePath"
        label: "onedrive binary"
        description: "Command or path used to query sync status. Leave empty to use the Nix store binary bundled with this plugin."
        placeholder: "(bundled onedrive)"
        defaultValue: ""
    }
}
