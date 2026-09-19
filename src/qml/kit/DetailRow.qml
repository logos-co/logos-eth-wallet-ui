import QtQuick 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// A label and its value on one line, the value right-aligned.
RowLayout {
    id: row
    property string label: ""
    property string value: ""
    property bool mono: false
    property color valueColor: Theme.palette.text

    Layout.fillWidth: true
    spacing: Theme.spacing.medium

    LogosText {
        text: row.label
        textFormat: Text.PlainText
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
        Layout.preferredWidth: 132
    }
    Item { Layout.fillWidth: true }
    LogosText {
        textFormat: Text.PlainText
        text: row.value
        color: row.valueColor
        font.family: row.mono ? Theme.typography.mono : Theme.typography.publicSans
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
    }
}
