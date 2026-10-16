import QtQuick 2.15
import QtQuick.Controls 2.15
import Logos.Controls
import Logos.Theme
import "roster.js" as Roster

// The account selector: one row per account, never one per signer. The app says which is
// selected (`currentKey`, a roster key or any holder's id) and hears `picked`; the picker
// re-asserts the app's selection after a click, so the two never disagree.
LogosComboBox {
    id: picker
    property var entries: []
    property string currentKey: ""
    property string placeholder: "Select an account"
    // Whether a row may be picked, for an app with its own reasons; every row by default.
    property var canPick: function (entry) { return true }
    property bool copyable: false
    // How much of the selected account the closed control shows, for a picker in a tight
    // header: 1 is the account alone. The rows always show all three lines.
    property int selectedLines: 3
    signal picked(var entry)
    signal copied(string value)

    readonly property var currentEntry: currentIndex >= 0 && currentIndex < entries.length ? entries[currentIndex] : null

    function syncIndex() { currentIndex = Roster.indexOf(entries, currentKey) }
    Component.onCompleted: syncIndex()
    // After the model, not the entries: ComboBox resets its index when its model is replaced.
    onModelChanged: syncIndex()
    onCurrentKeyChanged: syncIndex()
    onActivated: function (index) {
        picker.picked(picker.entries[index])
        picker.syncIndex()
    }

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
}
