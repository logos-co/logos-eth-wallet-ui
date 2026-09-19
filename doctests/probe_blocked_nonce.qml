// A nonce that holds up later sends: the banner names it per chain, offers the one-click
// resend only for a transfer this wallet can rebuild, and says how to get past the rest. A
// row another transaction at its nonce has mined reads `replaced`, on the list and on its
// own screen. The published shapes are test_blocked_nonce.cpp's; this runs the bindings.
import QtQuick

Item {
    id: probe
    width: 1100
    height: 900

    property int failures: 0
    readonly property string me: "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"
    readonly property string payee: "0x0ADB6CaA256A5375C638C00e2fF80A9Ac1b2d3A7"
    readonly property string replacedHash: "0x2659000000000000000000000000000000000000000000000000000000000001"
    readonly property string resentHash: "0x2148000000000000000000000000000000000000000000000000000000000002"
    readonly property string stuckHash: "0x6ad1000000000000000000000000000000000000000000000000000000000003"
    readonly property string waitingHash: "0x7c33000000000000000000000000000000000000000000000000000000000004"
    readonly property int t0: 1789669762
    readonly property int t1: 1789824627
    readonly property int t2: 1789824900
    property var resent: []

    function check(label, got, want) {
        var ok = String(got) === String(want)
        if (!ok) probe.failures++
        console.log((ok ? "  PASS  " : "  FAIL  ") + label + "   got=" + got
                    + (ok ? "" : "  want=" + want))
    }
    function find(o, name) {
        if (!o) return null
        if (o.objectName === name) return o
        var kids = o.data !== undefined ? o.data : []
        for (var i = 0; i < kids.length; ++i) {
            var hit = find(kids[i], name)
            if (hit) return hit
        }
        return null
    }
    function inDialog(dialogName, name, key) {
        var d = find(view.item, dialogName)
        var hit = (d && d.contentItem) ? find(d.contentItem, name) : null
        return hit ? hit[key] : "<absent>"
    }
    function prop(name, key) {
        var o = find(view.item, name)
        return o ? o[key] : "<absent>"
    }
    function when(t) { return Qt.formatDateTime(new Date(t * 1000), "MMM d, HH:mm") }

    readonly property string networks: JSON.stringify([
        { chainId: 1, name: "Ethereum", nativeSymbol: "ETH", testnet: false,
          enabled: true, inScope: true, verifiedProxyMode: "off",
          verifiedProxy: { mode: "off", state: "disabled", usable: true } },
        { chainId: 11155111, name: "Sepolia", nativeSymbol: "ETH", testnet: true,
          enabled: true, inScope: true, verifiedProxyMode: "off",
          verifiedProxy: { mode: "off", state: "disabled", usable: true } }
    ])
    function tx(hash, nonce, status, ts, extra) {
        var r = { chainId: 1, hash: hash, nonce: nonce, status: status, timestamp: ts, from: probe.me,
                  to: probe.payee, label: "Send ETH", origin: "eth_wallet_backend", kind: "native",
                  value: "100000000000", valueDisplay: "0.0000001", valueExact: "0.0000001",
                  valueSymbol: "ETH", maxFeePerGas: "338658463", maxPriorityFeePerGas: "0" }
        for (var k in extra) r[k] = extra[k]
        return r
    }
    readonly property string history: JSON.stringify([
        tx(probe.waitingHash, 45, "pending", probe.t2, {}),
        tx(probe.stuckHash, 44, "pending", probe.t1, { stalled: true }),
        tx(probe.resentHash, 40, "confirmed", probe.t1 - 100, { blockNumber: 26011969 }),
        tx(probe.replacedHash, 40, "pending", probe.t0, { stalled: true, replaced: true })
    ])
    readonly property var resendRequest: ({ chainId: 1, from: probe.me, to: probe.payee, amount: "100000000000",
                                           nonce: 44, maxFeePerGas: "372524310", maxPriorityFeePerGas: "37979581" })
    readonly property var resendQuote: ({ ok: true, chainId: 1, to: probe.payee, amount: "100000000000",
                                          amountExact: "0.0000001", amountSymbol: "ETH", token: null, nativeSymbol: "ETH",
                                          nonce: 44, gasLimit: 21000, maxFeePerGas: "372524310",
                                          maxPriorityFeePerGas: "37979581", feeCeilingWeiDisplay: "0.0000078",
                                          maxCostWeiDisplay: "0.0000079", feeSource: "custom",
                                          replaces: { nonce: 44, raised: false,
                                                      pendingMaxFeePerGas: "338658463", pendingMaxPriorityFeePerGas: "0" } })
    readonly property string blocked: JSON.stringify([
        { chainId: 1, nonce: 44, behind: 1, why: "stalled", since: probe.t1, hash: probe.stuckHash,
          label: "Send ETH", origin: "eth_wallet_backend",
          resend: { chainId: 1, from: probe.me, to: probe.payee, amount: "100000000000", nonce: 44 },
          floorMaxFeePerGas: "338658463", floorMaxPriorityFeePerGas: "0" },
        { chainId: 10, nonce: 3, behind: 2, why: "pending", since: probe.t2, hash: "0x1d66",
          label: "Swap", origin: "uniswap_backend" },
        { chainId: 11155111, nonce: 7, behind: 1, why: "stranded", since: probe.t2 }
    ])

    QtObject {
        id: fake
        property string lastError: ""
        property bool scopedDataFresh: true
        property bool dataLoading: false
        property bool balancesLoading: false
        property bool quoteLoading: false
        property bool feeTiersLoading: false
        property string activeNetworkJson: JSON.stringify(JSON.parse(probe.networks)[0])
        property string networksJson: probe.networks
        property string networkScope: "both"
        property string verifiedProxyJson: JSON.stringify({ mode: "off", state: "disabled",
                                                            usable: true, blocking: false })
        property string accountsJson: JSON.stringify([probe.me])
        property string selectedAccount: probe.me
        property string accountLabelsJson: "{}"
        property string accountWalletsJson: "{}"
        property string contactsJson: "[]"
        property string contactsError: ""
        property string balancesJson: "[]"
        property string balancesRoute: ""
        property string tokensJson: "[]"
        property string tokenSort: "alpha"
        property string historyJson: probe.history
        property string blockedChainsJson: "[]"
        property string blockedNoncesJson: probe.blocked
        property bool resendLoading: false
        property string resendReviewJson: ""
        property int dismissed: 0
        property var submitted: []
        function submitSend(r) { fake.submitted = fake.submitted.concat([r]) }
        function dismissResend() { fake.dismissed++; fake.resendReviewJson = "" }
        property bool sweepingReceipts: false
        property string txDetailsJson: ""
        property bool txDetailsLoading: false
        property bool txStatusLoading: false
        property string feeTiersJson: "{}"
        property string quoteJson: "{}"
        property string quoteRequestJson: ""
        property string sendError: ""
        property bool quoteStale: false
        property string pendingRequestId: ""
        property string pendingApprovalHandle: ""
        property string lastSendOutcomeJson: ""
        property string intentSendJson: ""
        property bool intentSendPricing: false
        function refresh() {}
        function chooseTokenSort(order) {}
        function refreshVerifiedProxy() {}
        function fetchTxDetails(h) {}
        function resendBlockedNonce(chainId) { probe.resent = probe.resent.concat([chainId]) }
    }

    property var logos: ({ module: function (name) { return fake },
                           isViewModuleReady: function (name) { return true },
                           request: function (intent, params, cb) {} })

    Loader {
        id: view
        anchors.fill: parent
        onStatusChanged: {
            if (status === Loader.Error) {
                console.log("  FAIL  the view did not load")
                Qt.exit(1)
            }
            if (status === Loader.Ready) settle.start()
        }
    }

    property int phase: 0
    Timer {
        id: settle
        interval: 350
        repeat: true
        onTriggered: {
            probe.phase++
            if (probe.phase === 1) {
                console.log("")
                console.log("the banner names the stuck nonce on each chain")
                check("it is up", prop("blockedNoncesFrame", "visible"), true)
                check("Ethereum: the stalled transfer and what waits behind it", prop("stuckNonce_1", "text"),
                      "Ethereum: nonce 44 (Send ETH, sent " + when(probe.t1) + ") has not confirmed, "
                      + "and 1 later transaction is waiting behind it.")
                check("...offers the one-click resend", prop("resendNonceButton_1", "visible"), true)
                check("...ready to press", prop("resendNonceButton_1", "enabled"), true)
                check("...in those words", prop("resendNonceButton_1", "text"), "Resend with current fees")
                check("...and needs no hint", prop("stuckNonceHint_1", "visible"), false)
                check("another app's call is named", prop("stuckNonce_10", "text"),
                      "Chain 10: nonce 3 (Swap, sent " + when(probe.t2) + ") has not confirmed, "
                      + "and 2 later transactions are waiting behind it.")
                check("...and not resent from here", prop("resendNonceButton_10", "visible"), false)
                check("...the hint says where it can be", prop("stuckNonceHint_10", "text"),
                      "Resend it from uniswap_backend, or send anything at nonce 3 from Send, under Advanced.")
                check("a number never sent is named", prop("stuckNonce_11155111", "text"),
                      "Sepolia (testnet): nonce 7 was reserved but never sent, so 1 later transaction "
                      + "is waiting behind it (since " + when(probe.t2) + ").")
                check("...with nothing to resend", prop("resendNonceButton_11155111", "visible"), false)
                check("...and how to release it", prop("stuckNonceHint_11155111", "text"),
                      "To release them, send anything at nonce 7 from Send, under Advanced.")

                find(view.item, "resendNonceButton_1").clicked()
                check("a press asks for that chain's resend", JSON.stringify(probe.resent), "[1]")
                fake.resendLoading = true
            } else if (probe.phase === 2) {
                console.log("")
                console.log("while one resend runs, or any send waits for approval, no second one")
                check("the button says it is running", prop("resendNonceButton_1", "text"), "Resending…")
                check("...and cannot be pressed", prop("resendNonceButton_1", "enabled"), false)
                fake.resendLoading = false
                fake.pendingRequestId = "snd_1"
            } else if (probe.phase === 3) {
                check("a send waiting for approval disables it too", prop("resendNonceButton_1", "enabled"), false)
                fake.pendingRequestId = ""
                view.item.selectTab(3)
            } else if (probe.phase === 4) {
                console.log("")
                console.log("the row another transaction at its nonce mined reads replaced")
                check("on the list", prop("txStatus_" + probe.replacedHash, "text"), "replaced")
                check("the stalled row still reads unconfirmed", prop("txStatus_" + probe.stuckHash, "text"),
                      "unconfirmed")
                view.item.openTxDetail(probe.replacedHash)
            } else if (probe.phase === 5) {
                check("on its own screen", prop("txDetailStatus", "text"), "replaced")
                check("...which says why", prop("txDetailReplacedNote", "text"),
                      "Another transaction at nonce 40 was mined, so this one never will be. "
                      + "Nothing in it left this account.")
                check("...and not that checking stopped", prop("txDetailStalledNote", "visible"), false)
                view.item.openTxDetail(probe.stuckHash)
            } else if (probe.phase === 6) {
                console.log("")
                console.log("the resend is priced, then reviewed: nothing leaves before Resend")
                fake.resendReviewJson = JSON.stringify({ request: probe.resendRequest, quote: probe.resendQuote })
            } else if (probe.phase === 7) {
                check("the transfer, again", inDialog("resendReviewDialog", "resendReviewAmount", "value"), "0.0000001 ETH")
                check("to the same recipient", inDialog("resendReviewDialog", "resendReviewTo", "value"), "0x0ADB…d3A7")
                check("at the fees it goes out with", inDialog("resendReviewDialog", "resendReviewFee", "value"),
                      "at most 0.0000078 ETH (custom)")
                check("pinned to the stuck nonce", inDialog("resendReviewDialog", "resendReviewNonce", "value"), "44")
                check("...and saying what it replaces", inDialog("resendReviewDialog", "resendReviewReplaces", "text"),
                      "Replaces the transaction still pending at nonce 44.")
                check("the review sent nothing", fake.submitted.length, 0)
                find(find(view.item, "resendReviewDialog").contentItem, "resendReviewConfirm").clicked()
                check("Resend submits the request that was priced", JSON.stringify(fake.submitted),
                      JSON.stringify([JSON.stringify(probe.resendRequest)]))
                find(find(view.item, "resendReviewDialog").contentItem, "resendReviewCancel").clicked()
                check("Back withdraws it", fake.dismissed, 1)
            } else if (probe.phase === 8) {
                check("a stalled row keeps its own note", prop("txDetailStalledNote", "visible"), true)
                check("...and no replaced one", prop("txDetailReplacedNote", "visible"), false)
                fake.historyJson = ""
            } else {
                console.log("")
                console.log("a history nobody has read says nothing about nonces")
                check("the banner goes with it", prop("blockedNoncesFrame", "visible"), false)

                console.log("")
                console.log("RESULT: " + (probe.failures ? probe.failures + " FAILED" : "ALL PASS"))
                Qt.exit(probe.failures ? 1 : 0)
            }
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/EthWalletView.qml")
}
