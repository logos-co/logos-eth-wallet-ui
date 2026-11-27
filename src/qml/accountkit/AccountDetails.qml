import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "roster.js" as Roster

// One account on a wallet card: its name and number, script type, derivation path and address
// (a Bitcoin account's first receiving one), with the app's own actions for it.
Item {
    id: row
    property var entry: null
    property string namePrefix: ""
    // Labels, or { id, label, enabled, tip }; or a function of the entry that returns them.
    property var actions: []
    // Icons for the inline edit (rename) by the name and the trash (remove) at the far right.
    // Without them, rename and remove stay text buttons with the app's other actions.
    property url editIcon: ""
    property url trashIcon: ""
    signal action(string id, var entry)
    signal copied(string value)

    readonly property var shown: Roster.actions(actions, entry)
    readonly property var editAction: editIcon.toString() ? shown.filter(function (a) { return a.id === "rename" })[0] || null : null
    readonly property var removeAction: trashIcon.toString() ? shown.filter(function (a) { return a.id === "remove" })[0] || null : null
    readonly property var otherActs: shown.filter(function (a) { return a !== row.editAction && a !== row.removeAction })
    readonly property string address: Roster.rowAddress(entry)
    implicitHeight: layout.implicitHeight
    implicitWidth: 480

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.medium

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                LogosText {
                    objectName: row.namePrefix + "Name"
                    // Shrinks before the number and badges do, and never past its own text. Rounded
                    // up: the layout snaps to whole pixels, and a fraction short elides it.
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.maximumWidth: Math.ceil(implicitWidth)
                    text: Roster.rowTitle(row.entry)
                    textFormat: Text.PlainText
                    font.bold: true
                    elide: Text.ElideRight
                }
                LogosIconButton {
                    objectName: row.namePrefix + "Edit"
                    visible: !!row.editAction
                    enabled: !row.editAction || row.editAction.enabled !== false
                    flat: true; size: 24; iconSize: 13
                    iconSource: row.editIcon
                    iconColor: hovered ? Theme.palette.text : Theme.palette.textTertiary
                    onClicked: if (row.editAction) row.action(row.editAction.id, row.entry)
                    LogosToolTip { text: "Edit name"; visible: parent.hovered; delay: 400 }
                }
                RowLayout {
                    spacing: 8
                    LogosText {
                        objectName: row.namePrefix + "Id"
                        // Not shown: the derivation path below already carries the account's index,
                        // as in the Keycard app (m/84'/1'/0' is account 0).
                        visible: false
                        text: Roster.rowId(row.entry)
                        textFormat: Text.PlainText
                        color: Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    Repeater {
                        model: Roster.badges(row.entry)
                        // Tags in the Activity / Keycard style: bold text, no border.
                        delegate: LogosText {
                            required property string modelData
                            required property int index
                            objectName: row.namePrefix + "Badge_" + index
                            text: modelData
                            textFormat: Text.PlainText
                            color: Theme.palette.textSecondary
                            font.weight: Theme.typography.weightBold
                            font.pixelSize: Theme.typography.secondaryText
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                LogosText {
                    text: "Derivation path"
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosText {
                    objectName: row.namePrefix + "Path"
                    text: Roster.text(row.entry && row.entry.path) || "Unavailable"
                    textFormat: Text.PlainText
                    font.family: Theme.typography.mono
                    font.pixelSize: Theme.typography.secondaryText
                }
                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                LogosText {
                    objectName: row.namePrefix + "AddressLabel"
                    text: Roster.addressLabel(row.entry)
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosText {
                    objectName: row.namePrefix + "Address"
                    text: Roster.rowAddressText(row.entry)
                    textFormat: Text.PlainText
                    color: row.address ? Theme.palette.text : Theme.palette.textSecondary
                    font.family: row.address ? Theme.typography.mono : Theme.typography.publicSans
                    font.pixelSize: Theme.typography.secondaryText
                    // Already shortened in the middle: trimming it again would match thousands.
                    elide: Text.ElideNone
                }
                LogosCopyButton {
                    objectName: row.namePrefix + "Copy"
                    visible: row.address.length > 0
                    value: row.address
                    Accessible.name: "Copy address"
                    onCopied: function (v) { row.copied(v) }
                    LogosToolTip { text: "Copy address"; visible: parent.hovered; delay: 400 }
                }
                Item { Layout.fillWidth: true }
            }
        }

        Repeater {
            model: row.otherActs
            delegate: Item {
                    id: oa
                    required property var modelData
                    objectName: row.namePrefix + "Action_" + Roster.actionName(modelData)
                    enabled: modelData.enabled
                    // The button's click, for whatever holds the action by its object name.
                    function clicked() { if (enabled) row.action(oa.modelData.id, row.entry) }
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: modelData.icon ? 28 : oaText.implicitWidth
                    implicitHeight: modelData.icon ? 28 : oaText.implicitHeight
                    // An action with an icon is an icon button, its label the tooltip.
                    LogosIconButton {
                        visible: oa.modelData.icon.length > 0
                        anchors.fill: parent
                        flat: true; size: 28; iconSize: 16
                        enabled: oa.modelData.enabled
                        iconSource: oa.modelData.icon ? Qt.resolvedUrl(oa.modelData.icon) : ""
                        iconColor: hovered ? Theme.palette.text : Theme.palette.textTertiary
                        Accessible.name: oa.modelData.label.replace("…", "")
                        onClicked: row.action(oa.modelData.id, row.entry)
                        LogosToolTip { text: oa.modelData.tip || oa.modelData.label.replace("…", ""); visible: parent.hovered; delay: 400 }
                    }
                    LogosButton {
                        id: oaText
                        visible: oa.modelData.icon.length === 0
                        anchors.fill: parent
                        text: oa.modelData.label
                        enabled: oa.modelData.enabled
                        Component.onCompleted: if ("compact" in this) this["compact"] = true
                        onClicked: row.action(oa.modelData.id, row.entry)
                    }
                }
        }
        LogosIconButton {
            objectName: row.namePrefix + "Remove"
            visible: !!row.removeAction
            enabled: !row.removeAction || row.removeAction.enabled !== false
            Layout.alignment: Qt.AlignVCenter
            flat: true; size: 28; iconSize: 16
            iconSource: row.trashIcon
            iconColor: hovered ? Theme.palette.text : Theme.palette.textTertiary
            onClicked: if (row.removeAction) row.action(row.removeAction.id, row.entry)
            LogosToolTip {
                text: (row.removeAction && row.removeAction.tip) ? row.removeAction.tip : "Remove"
                visible: parent.hovered; delay: 400
            }
        }
    }
}
