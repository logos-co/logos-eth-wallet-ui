// Asking other apps for things, LOADED and DRIVEN, with no app, no backend and no shell.
//
// Four of this view's buttons name a CAPABILITY rather than an app, and the shell resolves
// it. None of that can be read off the source: what matters is which intent goes out, what
// travels with it, and — the part with teeth — that the six answers each land somewhere
// sensible, including the one that means "nobody can do this", which has to leave the user
// with the instruction they had before intents existed.
//
// The fake backend is a QtObject, not a plain JS object: a write to a JS object's field
// notifies nothing, and half of this file MOVES a published property and watches the view
// react. `logos` is fabricated too — its `request` records the call and PARKS the callback,
// so each answer is delivered on demand rather than by a real broker.
import QtQuick

Item {
    id: probe
    width: 900
    height: 700

    readonly property string me: "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"
    readonly property string handle: "apr_7f3c9a"
    readonly property string txHash: "0x9a3c000000000000000000000000000000000000000000000000000000000001"

    // The words the wallet showed before any of this existed. `unavailable` has to put them
    // back: the signer may simply not be installed, and a wallet that answers that with a
    // shrug has lost the only instruction it ever had.
    readonly property string oldSignerText: "Approve this transaction in the Signer app to send it."

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

    function node(name) {
        return find(view.item, name) || ({ text: "<missing>", visible: "<missing>" })
    }

    // A LogosDialog is a Popup, not an Item: its contentItem is not parented into the tree
    // `find` walks, so anything inside one is reached through the dialog itself.
    //
    // And NEVER assert a popup's `visible` here. There is no window and no overlay, so it
    // reads false whatever its binding says — an assertion on it passes for both answers and
    // measures nothing. What the view actually decides is `showOutcome`; what the user
    // actually reads is the text. Both are below; `visible` is not.
    function inDialog(dialogName, name) {
        var d = find(view.item, dialogName)
        var hit = (d && d.contentItem) ? find(d.contentItem, name) : null
        return hit || ({ text: "<missing>", visible: "<missing>" })
    }

    function press(name) {
        var b = find(view.item, name)
        if (!b) {
            probe.failures++
            console.log("  FAIL  " + name + " is not in the tree")
            return false
        }
        b.clicked()
        return true
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

    // ── the fabricated shell ──────────────────────────────────────────────────
    //
    // Every request is recorded and its callback parked. Nothing answers on its own: the
    // real broker always answers asynchronously and exactly once, and a probe that replied
    // inside `request` would prove the view works only in the one case that never happens.
    property var requests: []
    property var reply: null

    function lastRequest() {
        return probe.requests.length ? probe.requests[probe.requests.length - 1]
                                     : ({ intent: "<none>", params: {} })
    }
    function answer(res) {
        var cb = probe.reply
        probe.reply = null
        if (cb)
            cb(res)
    }

    property var logos: ({
        module: function (n) { return fake },
        request: function (intent, params, cb) {
            var r = probe.requests
            r.push({ intent: intent, params: params })
            probe.requests = r
            probe.reply = cb
        }
    })

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
        property string accountsJson: JSON.stringify([probe.me])
        property string selectedAccount: probe.me
        property string accountLabelsJson: "{}"
        property string balancesJson: "[]"
        property string balancesRoute: "direct"
        property string tokensJson: "[]"
        property string availableTokensJson: ""
        property bool availableTokensLoading: false
        property bool tokenToggleBusy: false
        property string tokenToggleError: ""
        property string historyJson: "[]"
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

        // The two the send round trip turns on.
        property string pendingRequestId: ""
        property string pendingApprovalHandle: ""
        property string lastSendOutcomeJson: ""

        function cancelSend() {}
        function selectAccount(a) {}
        function chooseTokenSort(o) {}
    }

    // ── the send round trip ───────────────────────────────────────────────────

    function assertTheHandleIsWhatTravels() {
        console.log("")
        console.log("a send waiting on a human. The handle arriving is what asks — nothing")
        console.log("here is clicked, because in the real thing nobody clicks anything: the")
        console.log("backend publishes the handle and the request follows from it")
        fake.pendingRequestId = "snd_" + probe.handle
        fake.pendingApprovalHandle = probe.handle

        check("one request went out", probe.requests.length, 1)
        check("...naming the capability, never the app", probe.lastRequest().intent,
              "evm.signing.approve")
        check("...carrying the KEYSTORE's handle", probe.lastRequest().params.handle,
              probe.handle)
        console.log("")
        console.log("and NOT the wallet's own request id. The signer is keyed on the")
        console.log("keystore's name for the record; handing it ours would make this")
        console.log("backend's id format the signer's business")
        check("the wallet id did not travel",
              probe.lastRequest().params.handle === fake.pendingRequestId, false)
        check("...nothing else went with it",
              JSON.stringify(Object.keys(probe.lastRequest().params)), "[\"handle\"]")
    }

    function assertSilenceIsTheNormalOutcome() {
        console.log("")
        console.log("the two answers that say nothing. A send is settled by send_status, not")
        console.log("by this callback — so success writes no note, and a refusal by the human")
        console.log("is the system working, not a fault to report back at them")
        probe.answer({ ok: true, data: {}, error: "" })
        check("ok leaves the screen alone", inDialog("pendingDialog", "pendingLabel").text,
              "Waiting for this transaction to be approved.")

        fake.pendingApprovalHandle = ""
        fake.pendingApprovalHandle = probe.handle
        probe.answer({ ok: false, data: undefined, error: "cancelled" })
        check("...and so does the human saying no", inDialog("pendingDialog", "pendingLabel").text,
              "Waiting for this transaction to be approved.")
    }

    function assertUnavailableRestoresTheOldInstruction() {
        console.log("")
        console.log("nobody can service it — the signer is not installed, or this host has no")
        console.log("intent router at all (ui-host, logoscore, standalone-app). The words the")
        console.log("wallet showed before intents existed have to come back")
        fake.pendingApprovalHandle = ""
        fake.pendingApprovalHandle = probe.handle
        probe.answer({ ok: false, data: undefined, error: "unavailable" })
        check("the old instruction is what is left", inDialog("pendingDialog", "pendingLabel").text,
              probe.oldSignerText)
    }

    function assertEveryOtherCodeNamesItself() {
        console.log("")
        console.log("the rest are faults, and each says which. `bad_request` is the one worth")
        console.log("telling apart: it means the payload was refused, so retrying it unchanged")
        console.log("cannot help — and both the shell and the signer can mint it")
        for (var i = 0; i < 4; ++i) {
            var code = ["timeout", "failed", "bad_request", "not_declared"][i]
            fake.pendingApprovalHandle = ""
            fake.pendingApprovalHandle = probe.handle
            probe.answer({ ok: false, data: undefined, error: code })
            check("  " + code + " is named on screen", inDialog("pendingDialog", "pendingLabel").text,
                  "Could not reach a signer (" + code + ").")
        }
    }

    function assertNoHandleAsksNothing() {
        console.log("")
        console.log("and the empty transition asks for nothing. Clearing the handle is how")
        console.log("every send ends, so a request raised on it would fire once per send")
        var before = probe.requests.length
        fake.pendingApprovalHandle = ""
        check("clearing the handle raised no request", probe.requests.length, before)
    }

    // ── the receipt ───────────────────────────────────────────────────────────

    function assertTheOutcomeExplainsTheTrip() {
        console.log("")
        console.log("answering returns the user HERE, and the waiting dialog closes in the")
        console.log("same turn. Without this the shell appears to have moved them for no")
        console.log("reason: it knows the request finished, not what finishing meant")
        fake.pendingApprovalHandle = ""
        fake.pendingRequestId = ""
        fake.lastSendOutcomeJson = JSON.stringify({ status: "broadcast", hash: probe.txHash })

        check("the receipt is up", view.item.showOutcome, true)
        check("...and says it went", inDialog("sendOutcomeDialog", "sendOutcomeLabel").text,
              "Sent to the network.")
        check("...with the hash, which is the receipt",
              inDialog("sendOutcomeDialog", "sendOutcomeHash").text, "0x9a3c0000…00000001")

        console.log("")
        console.log("a rejection lands on the same surface. The user was sent to the signer")
        console.log("and brought back; arriving with nothing on screen is the failure mode")
        fake.lastSendOutcomeJson = JSON.stringify({ status: "rejected" })
        check("the rejection is named", inDialog("sendOutcomeDialog", "sendOutcomeLabel").text,
              "The signer rejected this transaction.")
        check("...and no hash is offered for a transaction that never existed",
              inDialog("sendOutcomeDialog", "sendOutcomeHash").text, "")

        fake.lastSendOutcomeJson = JSON.stringify({ status: "failed",
                                                    reason: "nonce too low" })
        check("a failure shows the backend's own words", inDialog("sendOutcomeDialog", "sendOutcomeLabel").text,
              "nonce too low")
    }

    function assertTheReceiptCanBeReadAndDismissed() {
        console.log("")
        console.log("dismissing is per OUTCOME, not a latch: the next send publishes a new")
        console.log("one and it has to show, even when it reads the same as the last")
        fake.lastSendOutcomeJson = JSON.stringify({ status: "cancelled" })
        check("cancelling has a receipt too", inDialog("sendOutcomeDialog", "sendOutcomeLabel").text,
              "This send was cancelled.")
        probe.pressInDialog("sendOutcomeDialog", "sendOutcomeDismiss")
        check("...which can be dismissed", view.item.showOutcome, false)

        console.log("")
        console.log("and a second identical outcome is NOT swallowed. submitSend clears the")
        console.log("published outcome as it starts, which is also what forgets the dismissal")
        fake.lastSendOutcomeJson = ""
        fake.lastSendOutcomeJson = JSON.stringify({ status: "cancelled" })
        check("the same outcome again still shows", view.item.showOutcome, true)
        probe.pressInDialog("sendOutcomeDialog", "sendOutcomeDismiss")

        console.log("")
        console.log("nothing is on screen while a send is still waiting: a receipt beside an")
        console.log("unanswered request would be two answers to one question")
        fake.lastSendOutcomeJson = JSON.stringify({ status: "broadcast", hash: probe.txHash })
        fake.pendingRequestId = "snd_later"
        check("a pending send hides the last receipt", view.item.showOutcome, false)
        fake.pendingRequestId = ""
    }

    // ── the three navigation hops ─────────────────────────────────────────────

    function assertNavigationHopsNameCapabilities() {
        console.log("")
        console.log("the three hops that are pure navigation. Each was a sentence telling the")
        console.log("user to go and find an app; each names a capability now, so a second")
        console.log("implementation of any of them would serve this wallet unchanged")

        var before = probe.requests.length
        probe.press("manageAccountsButton")
        check("accounts", probe.lastRequest().intent, "evm.accounts.manage")
        check("...with no payload at all",
              JSON.stringify(probe.lastRequest().params), "{}")
        probe.answer({ ok: true, data: {}, error: "" })

        // The banner only offers the button for a verdict that names something to go and do.
        fake.verifiedProxyJson = JSON.stringify({ ok: true, chainId: 11155111, mode: "required",
                                                  blocking: true, action: "open_verified_proxy",
                                                  message: "the proxy is not running" })
        check("the verified-proxy button appears with the verdict",
              node("openVerifiedProxyButton").visible, true)
        probe.press("openVerifiedProxyButton")
        check("verified routing", probe.lastRequest().intent, "evm.verified_routing.operate")

        console.log("")
        console.log("...and the hint it sits under STAYS. Nothing guarantees a provider, so")
        console.log("those words are the instruction to follow by hand")
        check("the hint is still there", node("verifiedBannerAction").text,
              "Open Verified Proxy and press Start.")
        probe.answer({ ok: false, data: undefined, error: "unavailable" })
        check("...and unavailable says so beneath it", node("intentNote").text,
              "Nothing on this device offers to do that — follow the note above.")

        console.log("")
        console.log("`wait` is the one verdict with nothing to go and do: the proxy is")
        console.log("running and catching up on its own")
        fake.verifiedProxyJson = JSON.stringify({ ok: true, chainId: 11155111, mode: "required",
                                                  blocking: true, action: "wait",
                                                  message: "catching up" })
        check("no button for a verdict that only asks for patience",
              node("openVerifiedProxyButton").visible, false)

        check("both hops asked, and each exactly once", probe.requests.length - before, 2)
    }

    function assertRpcSettingsHop() {
        console.log("")
        console.log("the endpoint hop lives behind Settings, whose own comment used to")
        console.log("explain why the button could not exist")
        var dlg = find(view.item, "settingsDialog")
        if (dlg && dlg.open)
            dlg.open()
        if (!probe.pressInDialog("settingsDialog", "openRpcSettingsButton"))
            return
        check("rpc endpoints", probe.lastRequest().intent, "evm.rpc.configure")
        check("...with no payload", JSON.stringify(probe.lastRequest().params), "{}")
        probe.answer({ ok: true, data: {}, error: "" })
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

            probe.assertTheHandleIsWhatTravels()
            probe.assertSilenceIsTheNormalOutcome()
            probe.assertUnavailableRestoresTheOldInstruction()
            probe.assertEveryOtherCodeNamesItself()
            probe.assertNoHandleAsksNothing()
            probe.assertTheOutcomeExplainsTheTrip()
            probe.assertTheReceiptCanBeReadAndDismissed()
            probe.assertNavigationHopsNameCapabilities()
            probe.assertRpcSettingsHop()

            console.log("")
            console.log(probe.failures ? "RESULT: FAILURES" : "RESULT: ALL PASS")
            Qt.exit(probe.failures ? 1 : 0)
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/EthWalletView.qml")
}
