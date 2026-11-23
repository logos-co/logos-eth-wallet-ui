import QtQuick 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "roster.js" as Roster

// Every signer holding an account, as short tags in the Activity / Keycard style: bold coloured
// text, no border, no dot. Green = can sign now, grey = not connected. A Keycard Shell that isn't
// plugged in is left out (it adds nothing to read); an absent card reads as a grey "Keycard".
Flow {
    id: chips
    property var holders: []
    property string namePrefix: ""
    spacing: Theme.spacing.small

    // When something can sign the account now, a device that isn't connected adds nothing.
    readonly property bool anyLive: (holders || []).some(function (h) { return h && h.presence !== "absent" })
    readonly property var shown: (holders || []).filter(function (h) {
        if (!h || h.presence !== "absent") return true
        return !chips.anyLive && h.kind !== "keycard_shell"
    })

    Repeater {
        model: chips.shown
        delegate: LogosText {
            objectName: chips.namePrefix + "Chip_" + index
            text: Roster.shortHolderName(modelData)
            textFormat: Text.PlainText
            font.weight: Theme.typography.weightBold
            font.pixelSize: Theme.typography.secondaryText
            color: modelData.presence === "absent" ? Theme.palette.textSecondary
                 : modelData.presence === "on_demand" ? Theme.palette.info
                 : Theme.palette.success
            Accessible.name: Roster.holderName(modelData) + (Roster.holderState(modelData) ? ", " + Roster.holderState(modelData) : "")
        }
    }
}
