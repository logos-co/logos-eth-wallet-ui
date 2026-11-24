import QtQuick 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "fees.js" as Fees

// Low / Market / Fast. The values are fee_module's own: slow, normal, fast.
RowLayout {
    id: picker
    property string tier: "normal"
    // An optional caption on the left, for a picker sitting in a list of figures.
    property string label: ""

    spacing: Theme.spacing.tiny

    LogosText {
        visible: picker.label.length > 0
        text: picker.label
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
    }
    Repeater {
        model: [["slow", "tierSlow"], ["normal", "tierNormal"], ["fast", "tierFast"]]
        LogosButton {
            objectName: modelData[1]
            text: Fees.tierName(modelData[0])
            variant: picker.tier === modelData[0] ? LogosButton.Variant.Primary : LogosButton.Variant.Secondary
            onClicked: picker.tier = modelData[0]
        }
    }
}
