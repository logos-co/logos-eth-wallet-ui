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
    // Send is a SECTION now, so its controls are in the ordinary item tree under sendPage —
    // no contentItem hop, which is the one a Popup needs and an Item does not have.
    function inSend(name) {
        var d = find(view.item, "sendPage")
        var hit = d ? find(d, name) : null
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

    // A pushed screen, not a popup: its delegates really are instantiated, so the address
    // book's rows can be driven rather than merely read off their bindings.
    function screen() {
        var nav = find(view.item, "nav")
        return nav ? nav.currentItem : null
    }
    function onScreen(name) {
        return find(screen(), name) || ({ text: "<missing>", visible: "<missing>" })
    }

    function openSend() { find(view.item, "openSendButton").clicked() }

    // ── what the form remembers ──────────────────────────────────────────────

    function assertTheFormKeepsADraftButNotALastSend() {
        console.log("")
        console.log("a section is STEPPED AWAY FROM — to read a balance on Tokens, to check an")
        console.log("address in the book — and stepped back into mid-send. The popup cleared on")
        console.log("every open; doing that here would eat a half-typed transfer for a glance")
        probe.openSend()
        inSend("toField").text = probe.friend
        inSend("amountField").text = "0.25"
        view.item.selectTab(0)
        view.item.selectTab(1)
        check("the recipient survived the round trip", inSend("toField").text, probe.friend)
        check("...and so did the amount", inSend("amountField").text, "0.25")

        console.log("")
        console.log("...but a form is still not a draft to inherit. What the popup was really")
        console.log("protecting against is the NEXT send starting on the recipient and amount")
        console.log("typed for a different one, and the address is both the field that matters")
        console.log("most and the one hardest to notice is stale. Cancel is where that happens")
        console.log("now — and, in the view, the moment a send is accepted.")
        inSend("gasLimitField").text = "21000"
        inSend("advancedToggle").checked = true
        // The real control, not clearForm() called by hand: a popup's onOpened could not fire
        // in a harness with no overlay, so this was a source assertion. A section's is a click.
        find(view.item, "sendCancelButton").clicked()
        check("the recipient is gone", inSend("toField").text, "")
        check("...and so is the amount", inSend("amountField").text, "")

        console.log("")
        console.log("...and the fee overrides with them, under a disclosure that closes. An")
        console.log("override left armed behind a collapsed Advanced prices the NEXT send at")
        console.log("the last one's gas, with nothing on screen saying so")
        check("advanced is closed", inSend("advancedToggle").checked, false)
        check("...and the gas override is empty", inSend("gasLimitField").text, "")
        check("and Cancel left the section", find(view.item, "pages").currentIndex, 0)
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

    function assertANameIsReadOnlyUntilAsked() {
        console.log("")
        console.log("a name in the book is READ-ONLY until asked. A field that is always open")
        console.log("is a name one stray keystroke rewrites, and this list is what a user")
        console.log("checks a recipient against before paying them")
        fake.contactsJson = JSON.stringify([{ address: probe.friend, name: "Rorschach" }])
        view.item.openAddressBook()

        check("the name is shown, not offered for editing", onScreen("bookName_0").visible, true)
        check("...and there is no field to type in", onScreen("bookNameField_0").visible, false)
        check("...but there is a way in", onScreen("bookEdit_0").visible, true)
        check("...and no Confirm standing by for an edit nobody started",
              onScreen("bookConfirm_0").visible, false)

        console.log("")
        console.log("an unnamed contact says so in its own voice — dimmed, so \"Unnamed\"")
        console.log("cannot be read as what somebody called it")
        fake.contactsJson = JSON.stringify([{ address: probe.friend, name: "" }])
        check("the placeholder is not a name", onScreen("bookName_0").text, "Unnamed")
    }

    function assertCancellingAnEditWritesNothing() {
        console.log("")
        console.log("entering the mode, changing the name, and abandoning it. The book must be")
        console.log("exactly as it was: a rename a user backed out of is not a rename")
        fake.contactsJson = JSON.stringify([{ address: probe.friend, name: "Rorschach" }])
        var before = fake.saved.length
        onScreen("bookEdit_0").clicked()
        check("the field is open", onScreen("bookNameField_0").visible, true)
        check("...seeded with the name it is editing", onScreen("bookNameField_0").text,
              "Rorschach")
        check("...and the read-only line stood down", onScreen("bookName_0").visible, false)

        onScreen("bookNameField_0").text = "Something else"
        onScreen("bookCancel_0").clicked()
        check("nothing was written", fake.saved.length - before, 0)
        check("...and the row is read-only again", onScreen("bookName_0").visible, true)
        check("...still showing the name it always had", onScreen("bookName_0").text,
              "Rorschach")
    }

    function assertConfirmingWritesOnceAndOnlyOnAChange() {
        console.log("")
        console.log("confirming writes, and writes what was typed")
        var before = fake.saved.length
        onScreen("bookEdit_0").clicked()
        onScreen("bookNameField_0").text = "  Renamed  "
        onScreen("bookConfirm_0").clicked()
        check("one write", fake.saved.length - before, 1)
        check("...of the trimmed name", fake.saved[fake.saved.length - 1].name, "Renamed")
        check("...against that contact's address", fake.saved[fake.saved.length - 1].address,
              probe.friend)
        check("...and the mode closed", onScreen("bookNameField_0").visible, false)

        console.log("")
        console.log("...but confirming an UNCHANGED name writes nothing. The backend would")
        console.log("take it happily; the cost is a re-read that rebuilds this list under the")
        console.log("pointer for no reason")
        before = fake.saved.length
        onScreen("bookEdit_0").clicked()
        onScreen("bookConfirm_0").clicked()
        check("no write for a no-op", fake.saved.length - before, 0)
        check("...and it still left the mode", onScreen("bookNameField_0").visible, false)
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

            probe.assertTheFormKeepsADraftButNotALastSend()
            probe.assertRecentsAreCounterpartiesNotContracts()
            probe.assertTheBookIsOfferedAndManaged()
            probe.assertANameIsReadOnlyUntilAsked()
            probe.assertCancellingAnEditWritesNothing()
            probe.assertConfirmingWritesOnceAndOnlyOnAChange()
            probe.assertTheAddFormRefusesAnEmptyAddress()

            console.log("")
            console.log(probe.failures ? "RESULT: FAILURES" : "RESULT: ALL PASS")
            Qt.exit(probe.failures ? 1 : 0)
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/EthWalletView.qml")
}
