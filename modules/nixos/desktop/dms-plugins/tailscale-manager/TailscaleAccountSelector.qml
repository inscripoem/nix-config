import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets

// Account source selector: trigger row + popup list.
//
// Each option is { owner: string, count: int, label: string } where label
// is optional (owner "" = all accounts). The device count is rendered as a
// separate right-aligned text with a smaller size and muted color, so it
// stays visible even when a long login name overflows and elides — unlike
// a "(N)" suffix inside the label string, which ElideRight would clip away.
Item {
    id: root

    property var options: []          // [{ owner, count, label? }]
    property string current: ""       // selected owner; "" = all accounts
    readonly property string allAccountsLabel: "All Accounts"

    signal selectionChanged(string owner)

    readonly property int totalCount: {
        var total = 0;
        for (var i = 0; i < options.length; i++)
            total += options[i].count;
        return total;
    }

    function labelFor(owner) {
        if (owner === "") return allAccountsLabel;
        for (var i = 0; i < options.length; i++) {
            if (options[i].owner === owner)
                return options[i].label || options[i].owner;
        }
        return owner;
    }

    function countFor(owner) {
        if (owner === "") return totalCount;
        for (var i = 0; i < options.length; i++) {
            if (options[i].owner === owner) return options[i].count;
        }
        return 0;
    }

    width: 400
    height: selectorRow.height

    Rectangle {
        id: selectorRow
        width: parent.width
        height: 40
        radius: Theme.cornerRadius
        color: selectorMouseArea.containsMouse ? Theme.surfaceHover : Theme.surfaceContainerHighest

        Row {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingS
            anchors.rightMargin: Theme.spacingS
            spacing: Theme.spacingS

            DankIcon {
                id: filterIcon
                name: "filter_list"
                size: Theme.iconSize - 8
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.labelFor(root.current)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - filterIcon.width - countText.width - dropIcon.width - parent.spacing * 3
            }

            StyledText {
                id: countText
                text: root.countFor(root.current)
                font.pixelSize: 11
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            DankIcon {
                id: dropIcon
                name: "expand_more"
                size: Theme.iconSize - 8
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: selectorMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: accountPopup.open()
        }
    }

    Popup {
        id: accountPopup
        x: 0
        y: selectorRow.height + Theme.spacingXS
        width: root.width
        height: Math.min(accountListCol.implicitHeight + Theme.spacingS * 2, 360)
        padding: 0
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
            radius: Theme.cornerRadius
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.08)
            border.width: 1
        }

        contentItem: DankFlickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: accountListCol.implicitHeight
            clip: true

            Column {
                id: accountListCol
                x: Theme.spacingS
                width: parent.width - Theme.spacingS * 2
                spacing: 1

                Repeater {
                    // "" (all accounts) first, then one entry per owner.
                    model: [{ "owner": "", "count": root.totalCount }].concat(root.options)

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool isSelected: modelData.owner === root.current
                        width: parent.width
                        height: 34
                        radius: Theme.cornerRadius
                        color: isSelected
                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                            : (accountItemMouseArea.containsMouse
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                                : "transparent")

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingS
                            anchors.rightMargin: Theme.spacingS
                            spacing: Theme.spacingS

                            DankIcon {
                                id: checkIcon
                                name: "check"
                                size: 14
                                color: Theme.primary
                                visible: parent.parent.isSelected
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: root.labelFor(modelData.owner)
                                font.pixelSize: Theme.fontSizeSmall
                                color: parent.parent.isSelected ? Theme.primary : Theme.surfaceText
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - checkIcon.width - row2Count.width - parent.spacing * 2
                            }

                            StyledText {
                                id: row2Count
                                text: modelData.count
                                font.pixelSize: 11
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: accountItemMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectionChanged(modelData.owner);
                                accountPopup.close();
                            }
                        }
                    }
                }
            }
        }
    }
}
