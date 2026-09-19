// Send, reviewed. The Send page's fee figures are the kit's rows, its Send opens a review that
// names what the signer will be asked, and only the review's Confirm submits the form. The
// Advanced fields send both fee fields or neither.
import QtQuick

Item {
    id: probe
    width: 1000
    height: 900

    readonly property string me: "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"
    readonly property string friend: "0x1234567890123456789012345678901234567890"
    property int failures: 0
    property var submitted: []

    function check(label, got, want) {
        var ok = String(got) === String(want)
        if (!ok) probe.failures++
        console.log((ok ? "  PASS  " : "  FAIL  ") + label + "   got=" + got + (ok ? "" : "  want=" + want))
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
    function inSend(name) {
        var hit = find(find(view.item, "sendPage"), name)
        return hit || ({ text: "<missing>", value: "<missing>", enabled: "<missing>" })
    }
    function inDialog(dialogName, name) {
        var d = find(view.item, dialogName)
        var hit = (d && d.contentItem) ? find(d.contentItem, name) : null
        return hit || ({ text: "<missing>", value: "<missing>", enabled: "<missing>" })
    }
    function form() { return find(view.item, "sendForm") }

    // prepare_send's reply for 0.25 ETH to `friend`, as the wallet backend relays it.
    readonly property var quote: ({ ok: true, chainId: 11155111, from: probe.me, to: probe.friend,
        amount: "250000000000000000", amountExact: "0.25", amountSymbol: "ETH", token: null,
        nativeSymbol: "ETH", nonce: 42, gasLimit: 21000, maxFeePerGas: "3171648910",
        maxPriorityFeePerGas: "169400000", feeCeilingWeiDisplay: "0.00006", maxCostWeiDisplay: "0.25006",
        feeSource: "feeHistory", replaces: null, route: "direct", feeRoute: "unknown" })

    QtObject {
        id: fake
        property string lastError: ""
        property bool scopedDataFresh: true
        property bool dataLoading: false
        property bool quoteLoading: false
        property string activeNetworkJson: JSON.stringify({ chainId: 11155111, name: "Sepolia",
                                                            nativeSymbol: "ETH", testnet: true })
        property string networksJson: JSON.stringify([{ chainId: 11155111, name: "Sepolia", nativeSymbol: "ETH",
                                                        testnet: true, enabled: true, inScope: true }])
        property string verifiedProxyJson: JSON.stringify({ ok: true, chainId: 11155111, mode: "off" })
        property string accountsJson: JSON.stringify([probe.me])
        property string selectedAccount: probe.me
        property string accountLabelsJson: "{}"
        property string accountWalletsJson: "{}"
        property string balancesJson: JSON.stringify([{ symbol: "ETH", display: "1.5", exact: "1.5", native: true }])
        property string balancesRoute: "direct"
        property string tokensJson: JSON.stringify([{ symbol: "ETH", name: "Ether", decimals: 18, native: true }])
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
        property string pendingRequestId: ""
        property string pendingApprovalHandle: ""
        property string lastSendOutcomeJson: ""
        property string contactsJson: "[]"
        property string contactsError: ""
        property bool balancesLoading: false
        property bool feeTiersLoading: false
        property string networkScope: "testnets"
        property string intentSendJson: ""
        property bool intentSendPricing: false
        property string blockedNoncesJson: "[]"
        property bool resendLoading: false
        property string resendReviewJson: ""
        function quote(r) {}
        function setQuoteAutoRefresh(on) {}
        function submitSend(r) { probe.submitted = probe.submitted.concat([r]) }
        function cancelSend() {}
        function selectAccount(a) {}
        function chooseTokenSort(o) {}
    }
    property var logos: ({ module: function (n) { return fake }, isViewModuleReady: function (n) { return true },
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
        interval: 300
        repeat: true
        onTriggered: {
            probe.phase++
            if (probe.phase === 1) {
                view.item.selectTab(1)
                inSend("toField").text = probe.friend
                inSend("amountField").text = "0.25"
            } else if (probe.phase === 2) {
                // The quote priced exactly the request the form describes.
                fake.quoteRequestJson = form().formRequest
                fake.quoteJson = JSON.stringify(probe.quote)
            } else if (probe.phase === 3) {
                console.log("")
                console.log("the Send page's figures are the kit's rows")
                check("the ceiling, named as one", inSend("feeRow").value, "at most 0.00006 ETH (Market)")
                check("the gas limit", inSend("gasLimitRow").value, "21000")
                check("the max fee, in gwei", inSend("maxFeeRow").value, "3.17164891 gwei")
                check("the nonce", inSend("nonceRow").value, "42")
                check("where they came from", inSend("feeSourceLabel").text, "Fee basis: feeHistory")
                check("Send is armed by them", inSend("sendSubmitButton").enabled, true)

                console.log("")
                console.log("Send opens the review, which says what the signer will be asked")
                inSend("sendSubmitButton").clicked()
                check("Send submits nothing by itself", probe.submitted.length, 0)
                check("what leaves", inDialog("sendReviewDialog", "sendReviewAmount").value, "0.25 ETH")
                check("to whom", inDialog("sendReviewDialog", "sendReviewTo").value, "0x1234…7890")
                check("on which network", inDialog("sendReviewDialog", "sendReviewNetwork").value, "Sepolia (testnet)")
                check("the most it can cost, fee included", inDialog("sendReviewDialog", "sendReviewTotal").value,
                      "at most 0.25006 ETH")
                check("the fee ceiling", inDialog("sendReviewDialog", "sendReviewFee").value, "at most 0.00006 ETH (Market)")
                check("the nonce", inDialog("sendReviewDialog", "sendReviewNonce").value, "42")
                check("the one transaction", inDialog("sendReviewDialog", "sendReviewCall_0").text,
                      "1. Send ETH · 0x1234…7890 · carries ether")
                inDialog("sendReviewDialog", "sendReviewConfirm").clicked()
                check("Confirm submits the form on screen, once", JSON.stringify(probe.submitted),
                      JSON.stringify([form().formRequest]))
                fake.sendError = "insufficient funds for gas * price + value"
            } else if (probe.phase === 4) {
                check("a refusal stays in the review, beside its reason", inDialog("sendReviewDialog", "sendReviewError").text,
                      "insufficient funds for gas * price + value")
                check("...and Confirm comes back for another try", inDialog("sendReviewDialog", "sendReviewConfirm").enabled, true)

                console.log("")
                console.log("a lone priority fee goes out with the max fee the quote suggested")
                inSend("advancedToggle").checked = true
                inSend("maxPriorityFeeField").text = "0"
                inSend("nonceField").text = "40"
            } else {
                var r = JSON.parse(form().formRequest)
                check("the tip as typed", r.maxPriorityFeePerGas, "0")
                check("the max fee held from the quote on screen when it was typed", r.maxFeePerGas, "3171648910")
                check("the nonce, a number", r.nonce, 40)
                check("no gas limit the user did not set", r.gasLimit, undefined)

                console.log("")
                console.log("RESULT: " + (probe.failures ? probe.failures + " FAILED" : "ALL PASS"))
                Qt.exit(probe.failures ? 1 : 0)
            }
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/EthWalletView.qml")
}
