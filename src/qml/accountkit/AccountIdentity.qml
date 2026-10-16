import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "roster.js" as Roster

// One account, as every app shows it: the account itself (an EVM name and address, or a
// Bitcoin name, script type and number), the wallet it comes from, and the signers holding it.
Item {
    id: identity
    property var entry: null
    property string namePrefix: ""
    property string placeholder: "Select an account"
    // An EVM address with a copy button beside it.
    property bool copyable: false
    // 1: the account alone; 2: and its wallet; 3: and its signers.
    property int lines: 3
    signal copied(string value)

    readonly property bool bitcoin: Roster.isBitcoin(entry)
    implicitHeight: column.implicitHeight
    implicitWidth: 320

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            LogosText {
                objectName: identity.namePrefix + "Name"
                visible: text.length > 0
                // The address, the script type and the number never give way to a long name.
                Layout.maximumWidth: Math.max(0, identity.width - tail.implicitWidth - 12)
                text: identity.entry ? Roster.name(identity.entry) : identity.placeholder
                textFormat: Text.PlainText
                elide: Text.ElideRight
            }
            RowLayout {
                id: tail
                spacing: 6
                visible: identity.entry !== null
                LogosText {
                    objectName: identity.namePrefix + "Address"
                    visible: !identity.bitcoin
                    text: identity.entry ? Roster.shortAddress(identity.entry.address) : ""
                    textFormat: Text.PlainText
                    color: Theme.palette.textSecondary
                    font.family: Theme.typography.mono
                    font.pixelSize: Theme.typography.secondaryText
                    // Already shortened in the middle: trimming it again would match thousands.
                    elide: Text.ElideNone
                }
                LogosCopyButton {
                    objectName: identity.namePrefix + "Copy"
                    visible: identity.copyable && !identity.bitcoin
                    value: identity.entry ? Roster.text(identity.entry.address) : ""
                    ToolTip.text: "Copy address"
                    ToolTip.visible: hovered
                    ToolTip.delay: 400
                    onCopied: function (v) { identity.copied(v) }
                }
                LogosBadge {
                    objectName: identity.namePrefix + "Type"
                    visible: identity.bitcoin
                    text: Roster.scriptType(identity.entry)
                    color: Theme.palette.textSecondary
                }
                LogosText {
                    objectName: identity.namePrefix + "Account"
                    visible: text.length > 0
                    text: Roster.accountText(identity.entry)
                    textFormat: Text.PlainText
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }
            }
            Item { Layout.fillWidth: true }
        }

        LogosText {
            objectName: identity.namePrefix + "Wallet"
            visible: identity.entry !== null && identity.lines >= 2
            Layout.fillWidth: true
            text: Roster.walletLine(identity.entry)
            textFormat: Text.PlainText
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
            elide: Text.ElideRight
        }

        SignerChips {
            objectName: identity.namePrefix + "Signers"
            visible: identity.entry !== null && holders.length > 0 && identity.lines >= 3
            Layout.fillWidth: true
            namePrefix: identity.namePrefix
            holders: identity.entry && identity.entry.holders ? identity.entry.holders : []
        }
    }
}
