import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "roster.js" as Roster

// One wallet, as the Signer, Keycard and Keys apps show it: its name and Wallet ID (the master
// fingerprint), the app's lines and strips, then one row per account. Each app brings its own
// actions: beside the title, in a strip, on each row, and at the bottom.
Frame {
    id: card
    property string namePrefix: ""
    property string title: ""
    // The wallet's id, shown once it is a known wallet: its BIP32 master fingerprint. Empty until
    // accounts are added, so the Wallet ID row only appears for a known wallet.
    property string walletId: fingerprint
    // The name this property had before; an app that still sets it gets the same row.
    property string fingerprint: ""
    // The keyUid this wallet is recognized by, shown in the Wallet ID tooltip.
    property string walletIdFull: ""
    // Icons for the inline edit (rename) and trash (forget) controls beside the title.
    property url editIcon: ""
    property url trashIcon: ""
    // A lock glyph shown before the name while the wallet is locked.
    property url lockIcon: ""
    // Beside the actions at the top, as "Unlocked".
    property string stateText: ""
    // Who holds it, or how it unlocks.
    property var lines: []
    // A device in use, a phrase kept here, a warning: [{ id, text, warn, actions }].
    property var strips: []
    property bool locked: false
    property string lockedText: "Locked · its ID and accounts show once you unlock it in the Signer app."
    property string emptyText: "No accounts yet."
    // Entries as the roster gives them, plus `firstAddress` for Bitcoin; shown in a fixed order.
    property var accounts: []
    // Labels, or { id, label, enabled, tip }. accountActions may be a function of the entry.
    property var actions: []
    property var lockedActions: []
    property var accountActions: []
    property var leftActions: []
    property var rightActions: []
    // The app's own items, as an inline editor, go above the bottom actions.
    default property alias content: extraArea.data

    signal action(string id)
    signal stripAction(int index, string id)
    signal accountAction(string id, var entry)
    signal copied(string value)

    readonly property var rows: Roster.sortAccounts(accounts)
    readonly property var bottomLeft: Roster.actions(leftActions)
    readonly property var bottomRight: Roster.actions(rightActions)
    // Add accounts becomes a full-width button under the connection; rename/forget become the edit
    // and trash icons beside the name; anything else (e.g. Verify) stays in the top row.
    readonly property var allActions: Roster.actions(card.actions)
    // Opt-in, as the icons are: with `primaryAdd` the `add` action is the card's full-width primary
    // button; without it, it stays a text button with the others. Its object name is
    // `<prefix>Action_add` either way, so specs that click it keep working.
    property bool primaryAdd: false
    // Renaming doesn't need the keys: the Signer keeps the pencil on a locked wallet.
    property bool editWhileLocked: false
    readonly property var addAction: primaryAdd ? allActions.filter(function (a) { return a.id === "add" })[0] || null : null
    // Rename and forget become icons by the title only when the app passes the icons.
    readonly property var editAction: editIcon.toString() ? allActions.filter(function (a) { return a.id === "rename" })[0] || null : null
    readonly property var trashAction: trashIcon.toString() ? allActions.filter(function (a) { return a.id === "forget" || a.id === "removewallet" })[0] || null : null
    readonly property var otherActions: allActions.filter(function (a) { return a !== card.addAction && a !== card.editAction && a !== card.trashAction })

    objectName: namePrefix + "Card"
    padding: Theme.spacing.medium
    background: Rectangle {
        radius: 6
        color: Theme.palette.backgroundMuted
        border.color: Theme.palette.border
        border.width: 1
    }

    component ActionButton: LogosButton {
        required property var spec
        property string prefix: card.namePrefix
        objectName: prefix + "Action_" + Roster.actionName(spec)
        text: spec.label
        enabled: spec.enabled
        LogosToolTip { text: spec.tip; visible: hovered && spec.tip.length > 0; delay: 400 }
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    // A lock glyph before the name on a locked wallet, so its state reads at a glance.
                    LogosIcon {
                        objectName: card.namePrefix + "LockIcon"
                        visible: card.locked && card.lockIcon != ""
                        Layout.alignment: Qt.AlignVCenter
                        width: 16; height: 16
                        source: card.lockIcon
                        color: Theme.palette.textSecondary
                    }
                    LogosText {
                        objectName: card.namePrefix + "Title"
                        Layout.fillWidth: false
                        Layout.maximumWidth: card.width * 0.62
                        text: card.title
                        textFormat: Text.PlainText
                        font.bold: true
                        font.pixelSize: Theme.typography.subtitleText
                        elide: Text.ElideRight
                    }
                    LogosIconButton {
                        objectName: card.namePrefix + "Edit"
                        visible: !!card.editAction && (!card.locked || card.editWhileLocked)
                        enabled: !card.editAction || card.editAction.enabled !== false
                        flat: true; size: 28; iconSize: 16
                        iconSource: card.editIcon
                        iconColor: hovered ? Theme.palette.text : Theme.palette.textTertiary
                        onClicked: if (card.editAction) card.action(card.editAction.id)
                        LogosToolTip { text: "Edit name"; visible: parent.hovered; delay: 400 }
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    visible: card.walletId.length > 0 && !card.locked
                    spacing: 6
                    LogosText {
                        Layout.alignment: Qt.AlignBaseline
                        text: "Wallet ID"
                        color: Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    LogosText {
                        objectName: card.namePrefix + "WalletId"
                        Layout.alignment: Qt.AlignBaseline
                        text: card.walletId
                        textFormat: Text.PlainText
                        color: Theme.palette.textSecondary
                        font.family: Theme.typography.mono
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    // The full identity and the cross-check fingerprint, kept off the always-on
                    // line: the keyUid is the wallet's identity; the BIP32 master fingerprint is
                    // the short form the Signer/Keys and hardware wallets show, once accounts load.
                    HoverHandler { id: walletIdHover }
                    ToolTip {
                        text: "The master fingerprint of the wallet's keys, the same ID every Logos wallet app shows."
                            + (card.walletIdFull.length > 0 ? "\nkeyUid: " + card.walletIdFull : "")
                        visible: walletIdHover.hovered
                        delay: 400
                    }
                }
                Repeater {
                    model: card.lines
                    delegate: LogosText {
                        required property var modelData
                        required property int index
                        objectName: card.namePrefix + "Line_" + index
                        Layout.fillWidth: true
                        text: Roster.text(modelData)
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                }
            }
            LogosText {
                objectName: card.namePrefix + "State"
                visible: text.length > 0
                Layout.alignment: Qt.AlignTop
                text: card.stateText
                textFormat: Text.PlainText
            }
            Repeater {
                model: card.otherActions
                delegate: Item {
                    id: oa
                    required property var modelData
                    objectName: card.namePrefix + "Action_" + Roster.actionName(modelData)
                    enabled: modelData.enabled
                    // The button's click, for whatever holds the action by its object name.
                    function clicked() { if (enabled) card.action(oa.modelData.id) }
                    Layout.alignment: Qt.AlignTop
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
                        onClicked: card.action(oa.modelData.id)
                        LogosToolTip { text: oa.modelData.tip || oa.modelData.label.replace("…", ""); visible: parent.hovered; delay: 400 }
                    }
                    LogosButton {
                        id: oaText
                        visible: oa.modelData.icon.length === 0
                        anchors.fill: parent
                        text: oa.modelData.label
                        enabled: oa.modelData.enabled
                        Component.onCompleted: if ("compact" in this) this["compact"] = true
                        onClicked: card.action(oa.modelData.id)
                    }
                }
            }
            LogosIconButton {
                objectName: card.namePrefix + "Forget"
                // Shown whenever a Forget action is offered, locked wallets included: a locked wallet
                // whose card was reset or lost must be removable from the list. (The action itself is
                // only offered for wallets committed on this computer.)
                visible: !!card.trashAction
                enabled: !card.trashAction || card.trashAction.enabled !== false
                Layout.alignment: Qt.AlignTop
                flat: true; size: 28; iconSize: 16
                iconSource: card.trashIcon
                iconColor: hovered ? Theme.palette.text : Theme.palette.textTertiary
                onClicked: if (card.trashAction) card.action(card.trashAction.id)
                LogosToolTip { text: "Forget wallet"; visible: parent.hovered; delay: 400 }
            }
        }

        Repeater {
            model: card.strips
            delegate: Rectangle {
                id: strip
                required property var modelData
                required property int index
                // Named by its id when it has one, so a strip's name doesn't shift with the others.
                readonly property string key: Roster.text(modelData && modelData.id) || String(index)
                readonly property string prefix: card.namePrefix + "Strip_" + key + "_"
                objectName: card.namePrefix + "Strip_" + key
                Layout.fillWidth: true
                // Single-line device strips share one fixed height so a strip with an action button
                // (e.g. "Card administration") is no taller than one without (a LogosButton forces a
                // 44 px min, which otherwise inflated only the button rows). A wrapping strip (a
                // multi-line warning) keeps its natural height.
                readonly property bool wrapping: !!(modelData && modelData.warn)
                // At least 40, and taller when its text wraps (a long reader name at a narrow width).
                implicitHeight: wrapping ? (stripRow.implicitHeight + 2 * Theme.spacing.small)
                                         : Math.max(40, stripRow.implicitHeight + 2 * Theme.spacing.small)
                radius: 6
                color: Theme.palette.backgroundSecondary
                RowLayout {
                    id: stripRow
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacing.medium
                    anchors.rightMargin: Theme.spacing.small
                    spacing: Theme.spacing.small
                    // A device strip leads with a green tag (e.g. "Shell USB", "Card reader") so a
                    // live connection reads at a glance; the detail that follows stays secondary.
                    readonly property string stripTag: Roster.text(strip.modelData && strip.modelData.tag)
                    LogosText {
                        objectName: strip.prefix + "Tag"
                        visible: stripRow.stripTag.length > 0
                        text: stripRow.stripTag
                        textFormat: Text.PlainText
                        color: Theme.palette.success
                        font.weight: Theme.typography.weightBold
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    LogosText {
                        visible: stripRow.stripTag.length > 0
                        text: "·"
                        color: Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    LogosText {
                        objectName: strip.prefix + "Text"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: Roster.text(strip.modelData && strip.modelData.text)
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: strip.modelData && strip.modelData.warn ? Theme.palette.error : Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    Repeater {
                        model: Roster.actions(strip.modelData && strip.modelData.actions)
                        delegate: ActionButton {
                            required property var modelData
                            spec: modelData
                            prefix: strip.prefix
                            // Sized to sit inside the fixed strip height, centred, so it does not
                            // make the row taller than a button-less strip. The default vertical
                            // padding (Theme medium) is cut to match, or the label drops to the
                            // bottom of the shortened button.
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredHeight: 30
                            Layout.maximumHeight: 30
                            topPadding: Theme.spacing.tiny
                            bottomPadding: Theme.spacing.tiny
                            onClicked: card.stripAction(strip.index, spec.id)
                        }
                    }
                }
            }
        }

        LogosButton {
            objectName: card.namePrefix + "Action_add"
            visible: !!card.addAction && !card.locked
            enabled: !card.addAction || card.addAction.enabled !== false
            Layout.fillWidth: true
            variant: LogosButton.Variant.Primary
            text: card.addAction ? card.addAction.label : "Add accounts"
            onClicked: if (card.addAction) card.action(card.addAction.id)
        }

        RowLayout {
            visible: card.locked
            Layout.fillWidth: true
            LogosText {
                objectName: card.namePrefix + "Locked"
                Layout.fillWidth: true
                text: card.lockedText
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Theme.palette.textSecondary
            }
            Repeater {
                model: Roster.actions(card.lockedActions)
                delegate: ActionButton {
                    required property var modelData
                    spec: modelData
                    // Unlock is the one thing to do on a locked wallet: give it primary weight.
                    variant: LogosButton.Variant.Primary
                    onClicked: card.action(spec.id)
                }
            }
        }

        LogosText {
            objectName: card.namePrefix + "Empty"
            visible: !card.locked && card.rows.length === 0 && card.emptyText.length > 0
            text: card.emptyText
            color: Theme.palette.textSecondary
        }

        ColumnLayout {
            visible: !card.locked && card.rows.length > 0
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            Repeater {
                model: card.rows
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    radius: 6
                    color: acctHover.hovered ? Theme.palette.backgroundTertiary : Theme.palette.backgroundSecondary
                    Behavior on color { ColorAnimation { duration: 120 } }
                    implicitHeight: acct.implicitHeight + 2 * Theme.spacing.small
                    HoverHandler { id: acctHover }
                    AccountDetails {
                        id: acct
                        objectName: card.namePrefix + "Account_" + index
                        namePrefix: card.namePrefix + "Account_" + index + "_"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacing.medium
                        anchors.rightMargin: Theme.spacing.small
                        entry: modelData
                        actions: card.accountActions
                        editIcon: card.editIcon
                        trashIcon: card.trashIcon
                        onAction: function (id, entry) { card.accountAction(id, entry) }
                        onCopied: function (v) { card.copied(v) }
                    }
                }
            }
        }

        ColumnLayout {
            id: extraArea
            objectName: card.namePrefix + "Content"
            Layout.fillWidth: true
            spacing: Theme.spacing.small
        }

        RowLayout {
            visible: card.bottomLeft.length + card.bottomRight.length > 0
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            Repeater {
                model: card.bottomLeft
                delegate: ActionButton {
                    required property var modelData
                    spec: modelData
                    onClicked: card.action(spec.id)
                }
            }
            Item { Layout.fillWidth: true }
            Repeater {
                model: card.bottomRight
                delegate: ActionButton {
                    required property var modelData
                    spec: modelData
                    onClicked: card.action(spec.id)
                }
            }
        }
    }
}
