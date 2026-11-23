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

    spacing: Theme.spacing.medium

    LogosText {
        visible: picker.label.length > 0
        text: picker.label
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
    }
    // A choice of one, so radio buttons, not three buttons that read as actions. The label is part
    // of the control, so a click on it selects too. checked is driven by `tier` (checkable off, as
    // the Signer's unlock-way picker does) so a click can't break the binding.
    Repeater {
        model: [["slow", "tierSlow"], ["normal", "tierNormal"], ["fast", "tierFast"]]
        LogosRadioButton {
            objectName: modelData[1]
            text: Fees.tierName(modelData[0])
            checkable: false
            checked: picker.tier === modelData[0]
            onClicked: picker.tier = modelData[0]
        }
    }
}
