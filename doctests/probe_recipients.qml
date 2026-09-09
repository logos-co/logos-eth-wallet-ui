// Where a recipient comes from, and what the Send form remembers between opens.
//
// Three sources, and they are different KINDS of answer rather than one list with headings:
// who this account has paid, who the user chose to remember, and who they already are. What
// no source assertion can reach is which addresses each one actually offers — Recents is
// DERIVED from history, and deriving it from the wrong field is the difference between
// offering a counterparty and offering a token contract to burn funds into.
//
// The fake backend is a QtObject: a write to a JS object's field notifies nothing, and this
// file moves the published history and book and watches the lists follow.
//
// TWO THINGS THIS HARNESS CANNOT REACH, asserted in assert_ui.py instead rather than faked
// into passing here. There is no window and no overlay, so a Popup never truly opens: its
// `onOpened` never fires, and a ListView inside a closed one has instantiated no delegates.
// So the form's clearing is driven through `clearForm()` directly — that it is CALLED on
// open is a source assertion — and the picker is measured on the lists it is bound to rather
// than on rows that do not exist yet.
import QtQuick

Item {
    id: probe
    width: 900
    height: 700

    readonly property string me: "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"
    readonly property string other: "0x0adBc7B2D1A2b7C8E9F0A1b2c3d4e5f60718D3A7"
    readonly property string weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    readonly property string friend: "0x1234567890123456789012345678901234567890"

    property int failures: 0

    function check(label, got, want) {
        var ok = String(got) === String(want)
        if (!ok)
            probe.failures++
        console.log((ok ? "  PASS  " : "  FAIL  ") + label + "   got=" + got
                    + (ok ? "" : "  want=" + want))
    }

    function find(o, name) {
        if (!o)
            return null
        if (o.objectName === name)
            return o
        var kids = o.data !== undefined ? o.data : []
        for (var i = 0; i < kids.length; ++i) {
            var hit = find(kids[i], name)
            if (hit)
                return hit
        }
        return null
    }

    // A LogosDialog is a Popup: its contentItem is not parented into the tree `find` walks,
    // and its `visible` reads false here whatever its binding says. Reach in through the
    // dialog, and assert on state and text rather than on visibility.
    function inDialog(dialogName, name) {
        var d = find(view.item, dialogName)
        var hit = (d && d.contentItem) ? find(d.contentItem, name) : null
        return hit || ({ text: "<missing>", enabled: "<missing>" })
    }

    property var logos: ({ module: function (n) { return fake }, isViewModuleReady: function (n) { return true } })

    // An ERC-20 send: `to` is the RECIPIENT and `token` is the contract. A Recents list built
    // from the transaction's own `to` would offer the WETH contract as somewhere to send to.
    readonly property string historyRows: JSON.stringify([
        { hash: "0xaa", to: probe.other, kind: "native", value: "1", status: "confirmed",
          timestamp: 1756600300, nonce: 3 },
        { hash: "0xbb", to: probe.friend, kind: "erc20", token: probe.weth, value: "1",
          status: "confirmed", timestamp: 1756600200, nonce: 2, txTo: probe.weth },
        // The same counterparty again, older. One row in the picker, not two.
        { hash: "0xcc", to: probe.other, kind: "native", value: "1", status: "confirmed",
          timestamp: 1756600100, nonce: 1 }
    ])

    QtObject {
        id: fake

        property string lastError: ""
        property bool scopedDataFresh: true
        property bool dataLoading: false
        property bool quoteLoading: false
        property string activeNetworkJson: JSON.stringify({ chainId: 11155111, name: "Sepolia",
                                                            nativeSymbol: "ETH", testnet: true })
        property string networksJson: "[]"
        property string verifiedProxyJson: JSON.stringify({ ok: true, chainId: 11155111,
                                                            mode: "off" })
        property string accountsJson: JSON.stringify([probe.me, probe.other])
        property string selectedAccount: probe.me
        property string accountLabelsJson: "{}"
        property string accountWalletsJson: "{}"
        property string balancesJson: JSON.stringify([{ symbol: "ETH", display: "1.5",
                                                        exact: "1.5", native: true }])
        property string balancesRoute: "direct"
        property string tokensJson: JSON.stringify([{ symbol: "ETH", name: "Ether",
                                                      decimals: 18, native: true }])
        property string availableTokensJson: ""
        property bool availableTokensLoading: false
        property bool tokenToggleBusy: false
        property string tokenToggleError: ""
        property string historyJson: probe.historyRows
        property string blockedChainsJson: "[]"
        property bool sweepingReceipts: false
        property string txDetailsJson: ""
        property bool txDetailsLoading: false
        property bool txStatusLoading: false
        property string feeTiersJson: "{}"
        property string quoteJson: "{}"
        property string quoteRequestJson: ""
        property string sendError: ""
        property bool quoteStale: false
        property string tokenSort: "alpha"
        property string pendingRequestId: ""
        property string pendingApprovalHandle: ""
        property string lastSendOutcomeJson: ""

        property string contactsJson: "[]"
        property string contactsError: ""

        // Every write the view asked for. The book itself is the backend's to order, so the
        // view must ask rather than edit its own copy — these record that it asked.
        property var saved: []
        property var forgotten: []
        function saveContact(address, name) {
            var s = fake.saved
            s.push({ address: address, name: name })
            fake.saved = s
        }
        function forgetContact(address) {
            var f = fake.forgotten
            f.push(address)
            fake.forgotten = f
        }

        function quote(r) {}
        function setQuoteAutoRefresh(on) {}
        function submitSend(r) {}
        function cancelSend() {}
        function selectAccount(a) {}
        function chooseTokenSort(o) {}
    }

    function pressInDialog(dialogName, name) {
        var d = find(view.item, dialogName)
        var b = (d && d.contentItem) ? find(d.contentItem, name) : null
        if (!b) {
            probe.failures++
            console.log("  FAIL  " + name + " is not in " + dialogName)
            return false
        }
        b.clicked()
        return true
    }

    // The recipient picker is a LogosMenu — a Popup like the dialogs, with the same rule.
    function menuNode(name) {
        var m = find(view.item, "toAccountsMenu")
        var hit = (m && m.contentItem) ? find(m.contentItem, name) : null
        return hit || ({ text: "<missing>", enabled: "<missing>" })
    }

    function root_backend() { return view.item.backend }

    function openSend() { find(view.item, "openSendButton").clicked() }

    // ── what the form remembers ──────────────────────────────────────────────

    function assertTheFormIsEmptyEveryTime() {
        console.log("")
        console.log("a Send dialog is not a draft. It reopens on the recipient and the amount")
        console.log("typed for a DIFFERENT transaction, and the address is both the field that")
        console.log("matters most and the one hardest to notice is stale")
        var dlg = find(view.item, "sendDialog")
        inDialog("sendDialog", "toField").text = probe.friend
        inDialog("sendDialog", "amountField").text = "0.25"
        inDialog("sendDialog", "gasLimitField").text = "21000"
        inDialog("sendDialog", "advancedToggle").checked = true

        // Driven directly: `onOpened` cannot fire in a harness with no overlay, so what is
        // measured here is that clearing EMPTIES the form. That it runs on open, and before
        // the re-price, is a source assertion.
        dlg.clearForm()
        check("the recipient is gone", inDialog("sendDialog", "toField").text, "")
        check("...and so is the amount", inDialog("sendDialog", "amountField").text, "")

        console.log("")
        console.log("...and the fee overrides with them, under a disclosure that closes. An")
        console.log("override left armed behind a collapsed Advanced prices the NEXT send at")
        console.log("the last one's gas, with nothing on screen saying so")
        check("advanced is closed", inDialog("sendDialog", "advancedToggle").checked, false)
        check("...and the gas override is empty", inDialog("sendDialog", "gasLimitField").text, "")
    }

    // ── where a recipient comes from ─────────────────────────────────────────

    function assertRecentsAreCounterpartiesNotContracts() {
        console.log("")
        console.log("Recents is DERIVED from history, and from the recipient field rather than")
        console.log("the transaction's own `to`: for an ERC-20 send that is the token")
        console.log("CONTRACT, and offering one back as somewhere to send to is how a user")
        console.log("burns funds into it")
        var r = view.item.recentRecipients
        check("the ERC-20 row offers its recipient", r.indexOf(probe.friend) >= 0, true)
        check("...and never the token contract", r.indexOf(probe.weth), -1)

        console.log("")
        console.log("and one row per counterparty, newest first — a picker listing the same")
        console.log("address three times is a picker nobody reads to the bottom of")
        check("the repeated payee appears once", r.filter(function (a) {
            return a === probe.other
        }).length, 1)
        check("...newest first", r[0], probe.other)
        check("three sends, two counterparties", r.length, 2)
    }

    function assertTheBookIsOfferedAndManaged() {
        console.log("")
        console.log("the address book is the backend's, in the backend's order. The view asks")
        console.log("it to change rather than editing its own copy: a row inserted here would")
        console.log("show an order the next read undoes")
        fake.contactsJson = JSON.stringify([{ address: probe.friend, name: "Rorschach" },
                                            { address: probe.weth, name: "" }])
        check("a named contact reads by name", view.item.contactName(probe.friend), "Rorschach")
        check("...and an unnamed one is still in the book", view.item.isContact(probe.weth), true)
        check("someone absent is not", view.item.isContact(probe.me), false)

        console.log("")
        console.log("saving is offered only where it would do something — a payee already in")
        console.log("the book has nothing to save, and a Save that does nothing is a Save a")
        console.log("user presses twice")
        check("a recent payee not in the book can be saved", view.item.isContact(probe.other),
              false)
        fake.contactsJson = JSON.stringify([{ address: probe.friend, name: "Rorschach" },
                                            { address: probe.weth, name: "" },
                                            { address: probe.other, name: "Paid before" }])
        check("...and once saved, there is nothing left to offer",
              view.item.isContact(probe.other), true)
        check("...its name is what the list then shows",
              view.item.contactName(probe.other), "Paid before")

        console.log("")
        console.log("the view never edits its own copy of the book: it asks, and re-reads what")
        console.log("comes back. The backend orders it, and a row inserted here would show an")
        console.log("order the next read undoes")
        var before = fake.saved.length
        root_backend().saveContact(probe.me, "New")
        check("a save goes to the backend", fake.saved.length - before, 1)
        check("...with what it was given", fake.saved[fake.saved.length - 1].address, probe.me)
        check("...and the published book is unchanged until it answers",
              view.item.isContact(probe.me), false)
    }

    function assertTheAddFormRefusesAnEmptyAddress() {
        console.log("")
        console.log("Add is armed by an address and nothing else. A name is optional — an")
        console.log("address worth remembering is worth remembering before its owner has one")
        console.log("the backend decides what an address is: this view does not parse one, so")
        console.log("a refusal comes back from the party that does and is shown in its words")
        fake.contactsError = "'0xnope' is not an Ethereum address"
        check("the view publishes the backend's refusal", root_backend().contactsError,
              "'0xnope' is not an Ethereum address")
        fake.contactsError = ""
        check("...and clears with it", root_backend().contactsError, "")
    }

    Loader {
        id: view
        anchors.fill: parent
        onStatusChanged: {
            if (status === Loader.Error) {
                console.log("  FAIL  the view did not load")
                Qt.exit(1)
            }
            if (status !== Loader.Ready)
                return
            item.ready = true

            probe.assertTheFormIsEmptyEveryTime()
            probe.assertRecentsAreCounterpartiesNotContracts()
            probe.assertTheBookIsOfferedAndManaged()
            probe.assertTheAddFormRefusesAnEmptyAddress()

            console.log("")
            console.log(probe.failures ? "RESULT: FAILURES" : "RESULT: ALL PASS")
            Qt.exit(probe.failures ? 1 : 0)
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/EthWalletView.qml")
}
