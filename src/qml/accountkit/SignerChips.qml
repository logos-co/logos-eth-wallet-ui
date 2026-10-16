import QtQuick 2.15
import Logos.Controls
import Logos.Theme
import "roster.js" as Roster

// Every signer holding an account, in the signer manager's order: the keystore, connected
// devices, QR wallets, then the ones that aren't connected.
Flow {
    id: chips
    property var holders: []
    property string namePrefix: ""
    spacing: Theme.spacing.tiny

    Repeater {
        model: chips.holders
        delegate: LogosBadge {
            objectName: chips.namePrefix + "Chip_" + index
            text: Roster.chip(modelData)
            color: modelData.presence === "absent" ? Theme.palette.textSecondary
                 : modelData.presence === "on_demand" ? Theme.palette.info
                 : Theme.palette.success
            Accessible.name: Roster.holderName(modelData) + (Roster.holderState(modelData) ? ", " + Roster.holderState(modelData) : "")
        }
    }
}
