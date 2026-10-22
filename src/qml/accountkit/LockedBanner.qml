import QtQuick 2.15
import Logos.Controls
import "roster.js" as Roster

// The wallets still locked in the Signer app, whose accounts the app can't show yet. Unlock asks
// for them: the app raises `logos.unlock` with `{ seeds }`.
LogosNotice {
    id: banner
    // The signer manager's `wallets()`: [{ seed, name, locked, kinds, privateName? }].
    property var wallets: []
    property string namePrefix: ""
    readonly property var locked: Roster.lockedWallets(wallets)
    signal unlock(var seeds)

    objectName: namePrefix + "LockedBanner"
    shown: locked.length > 0
    title: Roster.lockedTitle(locked)
    message: locked.length > 1 ? "Their accounts show here once you unlock them in the Signer app."
                               : "Its accounts show here once you unlock it in the Signer app."
    actions: [
        LogosButton {
            objectName: banner.namePrefix + "UnlockButton"
            text: "Unlock"
            onClicked: banner.unlock(banner.locked.map(function (w) { return w.seed }))
        }
    ]
}
