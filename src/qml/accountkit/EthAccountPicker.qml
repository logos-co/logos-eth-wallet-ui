import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "roster.js" as Roster

// A fork of AccountPicker for the Ethereum wallet: a compact one-line selector, plus a trailing
// "locked wallets" block inside the dropdown so the locked wallets are reachable from the same
// control (instead of a separate top banner) whenever at least one account is already unlocked.
// The shared AccountPicker is left untouched.
LogosComboBox {
    id: picker
    property var entries: []
    property string currentKey: ""
    property string placeholder: "Select an account"
    property var canPick: function (entry) { return true }
    property bool copyable: false
    // The closed control shows one line (name + short address); the rows show all three.
    property int selectedLines: 1
    // The locked wallets (signer manager's wallets() filtered to locked), shown as a footer.
    property var lockedWallets: []
    signal picked(var entry)
    signal copied(string value)
    signal unlock(var seeds)

    readonly property var currentEntry: currentIndex >= 0 && currentIndex < entries.length ? entries[currentIndex] : null

    function syncIndex() { currentIndex = Roster.indexOf(entries, currentKey) }
    Component.onCompleted: { syncIndex(); if (popupListView) popupListView.footer = lockedFooter }
    onModelChanged: syncIndex()
    onCurrentKeyChanged: syncIndex()
    onActivated: function (index) { picker.picked(picker.entries[index]); picker.syncIndex() }

    model: entries
    implicitHeight: selectedLines >= 3 ? 96 : selectedLines === 2 ? 64 : 44
    leftPadding: 12
    rightPadding: 36
    topPadding: 6
    bottomPadding: 6
    displayText: currentEntry ? Roster.summary(currentEntry) : placeholder
    Accessible.name: displayText
    ToolTip.visible: hovered && currentEntry !== null
    ToolTip.text: displayText

    contentItem: AccountIdentity {
        entry: picker.currentEntry
        namePrefix: picker.objectName + "Selected"
        placeholder: picker.placeholder
        copyable: picker.copyable
        lines: picker.selectedLines
        onCopied: function (v) { picker.copied(v) }
    }

    delegate: ItemDelegate {
        id: row
        required property var modelData
        required property int index
        objectName: picker.objectName + "Row_" + index
        width: picker.popupListView ? picker.popupListView.width : picker.width
        height: 96
        leftPadding: 12
        rightPadding: 12
        enabled: picker.canPick(modelData)
        opacity: enabled ? 1 : 0.5
        highlighted: picker.highlightedIndex === index
        Accessible.name: Roster.summary(modelData)
        background: Rectangle {
            color: row.highlighted || row.hovered ? Theme.palette.surface : "transparent"
        }
        HoverHandler { cursorShape: row.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        contentItem: AccountIdentity {
            entry: row.modelData
            namePrefix: picker.objectName + "Row_" + row.index
            copyable: picker.copyable
            onCopied: function (v) { picker.copied(v) }
        }
    }

    // Trailing "locked wallets" block, below the account rows. Zero height when nothing is locked.
    Component {
        id: lockedFooter
        Item {
            width: picker.popupListView ? picker.popupListView.width : picker.width
            visible: picker.lockedWallets.length > 0
            implicitHeight: visible ? footerCol.implicitHeight + 2 * Theme.spacing.small : 0
            Rectangle { anchors.fill: parent; color: Theme.palette.backgroundSecondary; visible: parent.visible }
            Rectangle { width: parent.width; height: 1; color: Theme.palette.borderSubtle; visible: parent.visible }
            ColumnLayout {
                id: footerCol
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: 12; rightMargin: 12 }
                spacing: Theme.spacing.small
                // One block per device app, so a Keycard wallet points at the Keycard app and a
                // Keystore wallet at the Keystore app, instead of one generic "Signer" bucket.
                Repeater {
                    model: Roster.lockedByDevice(picker.lockedWallets)
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2
                        LogosText {
                            objectName: picker.objectName + "LockedTitle_" + modelData.device.replace(/\s+/g, "")
                            Layout.fillWidth: true
                            text: modelData.count === 1 ? "1 " + modelData.device + " wallet is locked"
                                                        : modelData.count + " " + modelData.device + " wallets are locked"
                            color: Theme.palette.text
                            font.weight: Theme.typography.weightBold
                        }
                        LogosText {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: modelData.hint
                            color: Theme.palette.textSecondary
                            font.pixelSize: Theme.typography.secondaryText
                        }
                        LogosButton {
                            objectName: picker.objectName + "FooterUnlock_" + modelData.device.replace(/\s+/g, "")
                            Layout.topMargin: Theme.spacing.tiny
                            text: "Unlock"
                            onClicked: {
                                picker.unlock(modelData.seeds)
                                picker.popup.close()
                            }
                        }
                    }
                }
            }
        }
    }
}
