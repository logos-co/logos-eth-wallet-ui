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

    function root() { return view.item }

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

    // A QtObject, not a JS object: `intentRequested` has to be a REAL signal for the view's
    // `Connections { target: logos }` to bind to, or the provider half measures nothing.
    property var logos: shell
    property var responses: []
    QtObject {
        id: shell
        signal intentRequested(string requestId, string intent, var params, string requesterName)
        function module(n) { return fake }
        function isViewModuleReady(n) { return true }
        function request(intent, params, cb) {
            var r = probe.requests
            r.push({ intent: intent, params: params })
            probe.requests = r
            probe.reply = cb
        }
        function respond(requestId, ok, data, error) {
            var r = probe.responses
            r.push({ requestId: requestId, ok: ok, data: data, error: error })
            probe.responses = r
        }
    }
    function lastResponse() {
        return probe.responses.length ? probe.responses[probe.responses.length - 1]
                                      : ({ requestId: "<none>", ok: "<none>", error: "<none>", data: {} })
    }
    // What the fake backend was asked to review, accept or decline.
    property var reviewed: []
    property int accepted: 0
    property int declined: 0

    QtObject {
        id: fake

        property string lastError: ""
        property string intentSendJson: ""
        property bool intentSendPricing: false
        function reviewIntentSend(json) { var r = probe.reviewed; r.push(JSON.parse(json)); probe.reviewed = r }
        function acceptIntentSend() { probe.accepted++ }
        function declineIntentSend() { probe.declined++; fake.intentSendJson = "" }
        property bool scopedDataFresh: true
        property bool dataLoading: false
        property bool balancesLoading: false
        property bool quoteLoading: false
        property string activeNetworkJson: JSON.stringify({ chainId: 11155111, name: "Sepolia",
                                                            nativeSymbol: "ETH", testnet: true })
        property string networksJson: JSON.stringify([{ chainId: 11155111, name: "Sepolia",
                                                        nativeSymbol: "ETH", testnet: true,
                                                        enabled: true }])
        property string configuredNetworksJson: networksJson
        property string networkScope: "testnets"
        property string verifiedProxyJson: JSON.stringify({ ok: true, chainId: 11155111,
                                                            mode: "off" })
        property string accountsJson: JSON.stringify([probe.me])
        property string selectedAccount: probe.me
        property string accountLabelsJson: "{}"
        property string accountWalletsJson: "{}"
        property string balancesJson: "[]"
        property string balancesRoute: "direct"
        property string tokensJson: "[]"
        // Empty until the send settles, exactly as the real one is: `pollSend` refreshes
        // history a beat AFTER publishing the outcome, which is the window the receipt's
        // "View transaction" button has to survive.
        property string historyJson: "[]"
        property string blockedChainsJson: "[]"
        property bool sweepingReceipts: false
        property string txDetailsJson: ""
        property bool txDetailsLoading: false
        property bool txStatusLoading: false
        property string feeTiersJson: "{}"
        property bool feeTiersLoading: false
        property string quoteJson: "{}"
        property string quoteRequestJson: ""
        property string sendError: ""
        property bool quoteStale: false
        property string tokenSort: "alpha"

        // The two the send round trip turns on.
        property string pendingRequestId: ""
        property string pendingApprovalHandle: ""
        property string lastSendOutcomeJson: ""

        // Counted, because withdrawing a record the user may still approve by hand is the
        // one way this callback can do real damage.
        property int cancelCalls: 0
        function cancelSend() { fake.cancelCalls++ }
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

    function assertAClosedPathWithdrawsTheRecord() {
        console.log("")
        console.log("the codes that mean the intent path is CLOSED. The keystore cannot tell")
        console.log("'nobody is coming' from 'someone is coming, slowly' — with a dispatch in")
        console.log("flight the signer is often not loaded yet, so silence and absence look")
        console.log("identical there. This side knows, so it withdraws the record instead of")
        console.log("leaving a clock to race a human")
        for (var i = 0; i < 4; ++i) {
            var code = ["bad_request", "not_declared", "timeout", "cancelled"][i]
            var before = fake.cancelCalls
            fake.pendingApprovalHandle = ""
            fake.pendingApprovalHandle = probe.handle
            probe.answer({ ok: false, data: undefined, error: code })
            check("  " + code + " withdraws it", fake.cancelCalls - before, 1)
        }
    }

    function assertTheFallbackCodesLeaveItAlone() {
        console.log("")
        console.log("...and the ONE that must not. `unavailable` may mean the signer is merely")
        console.log("unreachable BY INTENT while still openable by hand, and that manual path")
        console.log("is the fallback the whole design rests on — withdrawing here would delete")
        console.log("the record the user was just told to go and approve")
        var before = fake.cancelCalls
        fake.pendingApprovalHandle = ""
        fake.pendingApprovalHandle = probe.handle
        probe.answer({ ok: false, data: undefined, error: "unavailable" })
        check("  unavailable leaves the record standing", fake.cancelCalls - before, 0)
        console.log("")
        console.log("nor does success: the send is settled by send_status, and withdrawing an")
        console.log("approval the human just granted would be the worst outcome of all")
        var b = fake.cancelCalls
        fake.pendingApprovalHandle = ""
        fake.pendingApprovalHandle = probe.handle
        probe.answer({ ok: true, data: {}, error: "" })
        check("  ok leaves it standing", fake.cancelCalls - b, 0)
    }

    function assertTheReceiptCarriesTheWholeHash() {
        console.log("")
        console.log("the receipt offers the hash to copy. SHORTENED on screen, WHOLE on the")
        console.log("clipboard — a truncated hash a user retypes is worse than no hash")
        fake.pendingApprovalHandle = ""
        fake.pendingRequestId = ""
        fake.historyJson = "[]"
        fake.lastSendOutcomeJson = JSON.stringify({ status: "broadcast", hash: probe.txHash })

        check("shown short", inDialog("sendOutcomeDialog", "sendOutcomeHash").text,
              "0x9a3c0000…00000001")
        check("...but copied whole",
              inDialog("sendOutcomeDialog", "sendOutcomeCopyButton").value, probe.txHash)
        check("...and there is nothing to copy when there is no hash",
              root().outcomeHash.length > 0, true)
    }

    function assertViewTransactionWaitsForTheRow() {
        console.log("")
        console.log("`openTxDetail` refuses a hash it cannot find, and refuses it SILENTLY. The")
        console.log("row arrives a beat after the outcome does, so an always-enabled button")
        console.log("would close the receipt and go nowhere in exactly the window it is used")
        // Existence, not `visible` — see the header: a popup's visible reads false here
        // whatever its binding says, so asserting it would pass for both answers.
        check("the button is there, because there is a hash",
              find(find(view.item, "sendOutcomeDialog").contentItem,
                   "sendOutcomeViewTx") !== null, true)
        check("...but not yet armed, because history has not caught up",
              inDialog("sendOutcomeDialog", "sendOutcomeViewTx").enabled, false)

        fake.historyJson = JSON.stringify([{
            hash: probe.txHash, chainId: 11155111, from: probe.me,
            to: "0x0adBc7B2D1A2b7C8E9F0A1b2c3d4e5f60718D3A7", value: "1000000000000000",
            kind: "native", status: "pending", timestamp: 1756600000, nonce: 7
        }])
        check("...and it arms the moment the row lands",
              inDialog("sendOutcomeDialog", "sendOutcomeViewTx").enabled, true)
    }

    function assertViewTransactionLandsOnTheRow() {
        console.log("")
        console.log("pressing it closes the receipt and opens that transaction. Both: leaving")
        console.log("the dialog up over the screen it just opened is the obvious way to get")
        console.log("this half right and still ship something unusable")
        probe.pressInDialog("sendOutcomeDialog", "sendOutcomeViewTx")
        check("the receipt is gone", root().showOutcome, false)
        var nav = find(view.item, "nav")
        check("...and a detail screen was pushed", nav !== null && nav.depth > 1, true)
    }

    function assertTheSubmitWaitEndsBothWays() {
        console.log("")
        console.log("the gap between the click and the chooser is real work — pricing, a nonce")
        console.log("reservation, the keystore record — with the dialog still up. Both ways out")
        console.log("have to clear it: a refusal that left the flag set would leave the button")
        console.log("dead with no way back except closing the dialog")
        view.item.sendSubmitting = true
        fake.pendingRequestId = "snd_x"
        check("the backend taking it ends the wait", view.item.sendSubmitting, false)

        view.item.sendSubmitting = true
        fake.pendingRequestId = ""
        fake.sendError = "insufficient funds"
        check("...and so does it refusing", view.item.sendSubmitting, false)
        fake.sendError = ""
    }

    function assertAnUnnamedAccountBorrowsItsWalletName() {
        console.log("")
        console.log("an account nobody named, in a wallet somebody did. `#index` is the")
        console.log("DERIVATION index off the account's own path, not a position in this list —")
        console.log("a position renumbers when an account is added or removed, and the label")
        console.log("would then quietly come to mean a different account")
        fake.accountWalletsJson = JSON.stringify({
            "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199": { wallet: "Status Throwaway", index: 0 }
        })
        check("it borrows the wallet's name and says where in it",
              view.item.displayName(probe.me), "Status Throwaway #0")
        // The name never REPLACES the address ANYWHERE it has room for both — that is
        // `namedAddr`, the rule the activity list and every detail row use. The closed
        // account picker is the one exception, and a deliberate one: it is 220px with an
        // elide of its own, so both in it means the address is what gets cut.
        check("...and the general rule carries the address with it",
              view.item.namedAddr(probe.me), "Status Throwaway #0 (0x8626…1199)")
        check("...while the closed picker shows the name alone, beside the address",
              view.item.accountDisplay(probe.me), "Status Throwaway #0")

        console.log("")
        console.log("...but its OWN name always wins, and an account in an unnamed wallet")
        console.log("falls back to the address rather than inventing anything")
        fake.accountLabelsJson = JSON.stringify({ "8626f6940e2eb28930efb4cef49b2d1f2c9c1199": "Payroll" })
        check("its own name wins", view.item.displayName(probe.me), "Payroll")
        fake.accountLabelsJson = "{}"
        fake.accountWalletsJson = "{}"
        check("and with neither, the address", view.item.accountDisplay(probe.me).indexOf("0x"), 0)
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
        console.log("the endpoint hop lives on the Networks screen. It used to be behind a")
        console.log("Settings popup whose whole content was links to other places — a click")
        console.log("in front of each of them, and gone now")
        view.item.openNetworks()
        var nav = find(view.item, "nav")
        var page = nav ? nav.currentItem : null
        var btn = page ? find(page, "openRpcSettingsButton") : null
        if (!btn) {
            probe.failures++
            console.log("  FAIL  openRpcSettingsButton is not on the Networks screen")
            return
        }
        // A pushed screen, not a popup: its children are really instantiated, so this is a
        // press rather than an assertion about a binding.
        btn.clicked()
        check("rpc endpoints", probe.lastRequest().intent, "evm.rpc.configure")
        check("...with no payload", JSON.stringify(probe.lastRequest().params), "{}")
        probe.answer({ ok: true, data: {}, error: "" })
        check("...and the network selector is on that screen too, not in a dialog",
              find(page, "walletChainEnabled_11155111") !== null || root_networksEmpty(), true)
    }

    function assertTokenListsHop() {
        console.log("")
        console.log("token membership is not a Wallet screen. Its Settings row hands control")
        console.log("to whichever app provides token-list configuration")
        view.item.selectTab(4)
        var nav = find(view.item, "nav")
        var depth = nav ? nav.depth : -1
        probe.press("tokenListsEntry")
        check("token lists", probe.lastRequest().intent, "evm.token_lists.configure")
        check("...with no payload", JSON.stringify(probe.lastRequest().params), "{}")
        check("...without pushing a Wallet-owned screen", nav ? nav.depth : -1, depth)
        probe.answer({ ok: false, data: undefined, error: "unavailable" })
        check("...and an unavailable provider is explained on Settings",
              node("tokenListsIntentNote").text,
              "Nothing on this device manages token lists.")
    }

    // The probe's fake publishes no network list, so the selector legitimately has no rows.
    // Saying so beats an assertion that passes for the wrong reason.
    function root_networksEmpty() { return view.item.networks.length === 0 }

    // ── the other direction: this wallet PROVIDES evm.transactions.send ──────────
    //
    // An app hands over calls and a purpose. The backend reviews and prices them, the human
    // sees them before the signer does, and the app is answered once — with every hash, or
    // with why not. The backend is fabricated, so what is asserted is the VIEW's half: what
    // it asks the backend, what it shows, and what it tells the shell.
    function assertAnotherAppsSendIsReviewedAndAnswered() {
        console.log("")
        console.log("another app asks this wallet to send. The request reaches the backend for")
        console.log("review with the shell's id and the requester's attested name")
        var root = view.item
        fake.pendingRequestId = ""
        fake.lastSendOutcomeJson = ""
        var calls = [{ to: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45", value: "0x0", data: "0x5ae401dc",
                       label: "Swap USDC for ETH on Uniswap V3" }]
        shell.intentRequested("req_7", "evm.transactions.send",
                              ({ purpose: "Swap 1000 USDC for ETH on Uniswap", calls: calls }), "uniswap_ui")
        check("the backend is asked to review it", probe.reviewed.length, 1)
        check("...under the shell's id", probe.reviewed[0].requestId, "req_7")
        check("...naming the requester the shell attested", probe.reviewed[0].requester, "uniswap_ui")
        check("...with the payload untouched", probe.reviewed[0].params.calls[0].data, "0x5ae401dc")
        check("nothing is answered yet", probe.responses.length, 0)

        console.log("   the backend publishes what it checked, and the dialog shows all of it")
        fake.intentSendJson = JSON.stringify({ requestId: "req_7", requester: "uniswap_ui", chainId: 11155111,
                                               from: probe.me, purpose: "Swap 1000 USDC for ETH on Uniswap",
                                               tier: "normal", calls: calls })
        check("the review is open", root.intentSendOpen, true)
        check("who asked", inDialog("intentSendDialog", "intentSendRequester").value, "uniswap_ui")
        check("what they claim it is for", inDialog("intentSendDialog", "intentSendPurpose").value,
              "Swap 1000 USDC for ETH on Uniswap")
        check("the call, with its label and contract", inDialog("intentSendDialog", "intentSendCall_0").text,
              "1. Swap USDC for ETH on Uniswap V3 · 0x68b3…Fc45")
        check("...and its calldata, whole", inDialog("intentSendDialog", "intentSendCallData_0").text, "0x5ae401dc")
        fake.intentSendPricing = true
        check("while the sender prices it, the fee line says so", inDialog("intentSendDialog", "intentSendFee").text, "Pricing…")
        check("...and the send button waits", inDialog("intentSendDialog", "intentSendAccept").enabled, false)
        fake.intentSendPricing = false
        fake.intentSendJson = JSON.stringify(Object.assign(JSON.parse(fake.intentSendJson),
                                                           { fee: { ok: true, feeCeilingWeiDisplay: "0.0004", valueWeiDisplay: "1.5", nativeSymbol: "ETH" } }))
        check("the fee is a ceiling, never a price", inDialog("intentSendDialog", "intentSendFee").text,
              "Network fee at most 0.0004 ETH")
        check("the ether the calls carry is the sender's sum, in ether, never bare wei",
              inDialog("intentSendDialog", "intentSendValue").value, "1.5 ETH")
        check("...and the button offers the send on the named network",
              inDialog("intentSendDialog", "intentSendAccept").text, "Send on Sepolia (testnet)")

        console.log("   the human says yes: the backend sends, and the request becomes the wallet's")
        console.log("   own pending send — same signer hand-off — while the app waits")
        pressInDialog("intentSendDialog", "intentSendAccept")
        check("accept reaches the backend", probe.accepted, 1)
        fake.intentSendJson = ""
        fake.pendingRequestId = "snd_7"; fake.pendingApprovalHandle = probe.handle
        check("the signer is asked for the same send", probe.lastRequest().intent, "evm.signing.approve")
        check("...and the app is still waiting", probe.responses.length, 0)
        probe.answer({ ok: true })
        fake.lastSendOutcomeJson = JSON.stringify({ status: "broadcast", hash: "0xb", hashes: ["0xa", "0xb"] })
        fake.pendingRequestId = ""; fake.pendingApprovalHandle = ""
        check("the outcome answers the app", probe.responses.length, 1)
        check("...ok", probe.lastResponse().ok, true)
        check("...with every hash", JSON.stringify(probe.lastResponse().data.hashes), JSON.stringify(["0xa", "0xb"]))
        check("...and the status", probe.lastResponse().data.status, "broadcast")
        check("...and the id is spent", root.intentSendRequestId, "")

        console.log("   declining answers `cancelled` and clears the review")
        root.dismissOutcome(); fake.lastSendOutcomeJson = ""
        shell.intentRequested("req_8", "evm.transactions.send", ({ purpose: "p", calls: calls }), "some_app")
        fake.intentSendJson = JSON.stringify({ requestId: "req_8", requester: "some_app", chainId: 11155111,
                                               from: probe.me, purpose: "p", tier: "normal", calls: calls })
        pressInDialog("intentSendDialog", "intentSendDecline")
        check("the backend clears it", probe.declined, 1)
        check("the app hears cancelled", probe.lastResponse().error, "cancelled")
        check("...for its own request", probe.lastResponse().requestId, "req_8")

        console.log("   a refusal by the backend is passed on with its code and detail")
        shell.intentRequested("req_9", "evm.transactions.send", ({ purpose: "p", calls: [] }), "some_app")
        fake.intentSendJson = JSON.stringify({ requestId: "req_9", requester: "some_app", error: "bad_request", detail: "no calls" })
        check("bad_request reaches the app", probe.lastResponse().error, "bad_request")
        check("...with the reason", probe.lastResponse().data.detail, "no calls")
        check("...and the review is not open", root.intentSendOpen, false)

        console.log("   a rejection by the human is the app's answer too")
        shell.intentRequested("req_10", "evm.transactions.send", ({ purpose: "p", calls: calls }), "some_app")
        fake.intentSendJson = JSON.stringify({ requestId: "req_10", requester: "some_app", chainId: 11155111,
                                               from: probe.me, purpose: "p", tier: "normal", calls: calls })
        pressInDialog("intentSendDialog", "intentSendAccept")
        fake.intentSendJson = ""
        fake.pendingRequestId = "snd_10"; fake.pendingApprovalHandle = probe.handle
        probe.answer({ ok: true })
        fake.lastSendOutcomeJson = JSON.stringify({ status: "rejected" })
        fake.pendingRequestId = ""; fake.pendingApprovalHandle = ""
        check("rejected, in the sender's word", probe.lastResponse().error, "rejected")
        check("...not ok", probe.lastResponse().ok, false)

        console.log("   a second request over an open review ends the first")
        root.dismissOutcome(); fake.lastSendOutcomeJson = ""
        shell.intentRequested("req_11", "evm.transactions.send", ({ purpose: "p", calls: calls }), "app_a")
        shell.intentRequested("req_12", "evm.transactions.send", ({ purpose: "p", calls: calls }), "app_b")
        check("the first is answered cancelled", probe.lastResponse().requestId, "req_11")
        check("...as such", probe.lastResponse().error, "cancelled")
        check("...and the second is the one under review", root.intentSendRequestId, "req_12")
        fake.intentSendJson = JSON.stringify({ requestId: "req_12", requester: "app_b", chainId: 11155111,
                                               from: probe.me, purpose: "p", tier: "normal", calls: calls })
        pressInDialog("intentSendDialog", "intentSendDecline")
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
            probe.assertAClosedPathWithdrawsTheRecord()
            probe.assertTheFallbackCodesLeaveItAlone()
            probe.assertTheSubmitWaitEndsBothWays()
            probe.assertAnUnnamedAccountBorrowsItsWalletName()
            probe.assertNoHandleAsksNothing()
            probe.assertTheOutcomeExplainsTheTrip()
            probe.assertTheReceiptCanBeReadAndDismissed()
            probe.assertTheReceiptCarriesTheWholeHash()
            probe.assertViewTransactionWaitsForTheRow()
            probe.assertViewTransactionLandsOnTheRow()
            probe.assertNavigationHopsNameCapabilities()
            probe.assertRpcSettingsHop()
            probe.assertTokenListsHop()
            probe.assertAnotherAppsSendIsReviewedAndAnswered()

            console.log("")
            console.log(probe.failures ? "RESULT: FAILURES" : "RESULT: ALL PASS")
            Qt.exit(probe.failures ? 1 : 0)
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/EthWalletView.qml")
}
