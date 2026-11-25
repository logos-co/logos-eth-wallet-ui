// One backend error, one place. sendError and contactsError each stay set until the next
// success, so a review or the add-address sheet shows the refusal its own call answered with, in
// words, and the Send tab's line and the address book's line show only what the page did: never
// behind the dialog, never again after it closes, never stale in the next one opened.
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
        property bool contactsLocked: false
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
        // Answers as the backend does: true once saved, false with contactsError set.
        property string refuseWith: ""
        function saveContact(address, name) { fake.contactsError = fake.refuseWith; return fake.refuseWith.length === 0 }
        property string forgetRefusal: ""
        function forgetContact(address) { fake.contactsError = fake.forgetRefusal }
        function cancelSend() {}
        function selectAccount(a) {}
        function chooseTokenSort(o) {}
    }
    // `lose` makes the next call fail as a lost QtRO call would: the error callback, not the answer.
    property bool lose: false
    property var logos: ({ module: function (n) { return fake }, isViewModuleReady: function (n) { return true },
                           request: function (intent, params, cb) {},
                           watch: function (reply, done, err) {
                               if (probe.lose) { probe.lose = false; if (err) err("call failed"); return }
                               if (done) done(reply)
                           } })
    function dialog(name) { return find(view.item, name) }
    function inBook(name) {
        var hit = find(find(view.item, "addressBookTab"), name)
        return hit || ({ text: "<missing>", visible: "<missing>" })
    }

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

    // A popup opens only once the window is up, and lays out over the next frames: one step a tick.
    property int phase: 0
    Timer {
        id: settle
        interval: 300
        repeat: true
        onTriggered: {
            probe.phase++
            var review = probe.dialog("sendReviewDialog")
            var add = probe.dialog("bookAddDialog")
            if (probe.phase === 1) {
                view.item.selectTab(1)
                inSend("toField").text = probe.friend
                inSend("amountField").text = "0.25"
            } else if (probe.phase === 2) {
                fake.quoteRequestJson = form().formRequest
                fake.quoteJson = JSON.stringify(probe.quote)
            } else if (probe.phase === 3) {
                inSend("sendSubmitButton").clicked()
            } else if (probe.phase === 4) {
                console.log("")
                console.log("a refused Confirm is said in its review, in words, and nowhere else")
                check("the review is up", review.visible, true)
                check("it opens with no error", inDialog("sendReviewDialog", "sendReviewError").visible, false)
                inDialog("sendReviewDialog", "sendReviewConfirm").clicked()
                fake.sendError = "InsufficientFunds: insufficient funds for gas * price + value"
                check("refused: the reason in the review, without its code", inDialog("sendReviewDialog", "sendReviewError").text,
                      "insufficient funds for gas * price + value")
                check("...and not on the Send tab behind it", inSend("sendErrorLabel").visible, false)
                check("...and Confirm comes back for another try", inDialog("sendReviewDialog", "sendReviewConfirm").enabled, true)
                review.close()
            } else if (probe.phase === 5) {
                check("closed: the review is down", review.visible, false)
                check("...and the Send tab does not show it after", inSend("sendErrorLabel").visible, false)
                check("...nor does the closed review keep it", inDialog("sendReviewDialog", "sendReviewError").text, "")
                inSend("sendSubmitButton").clicked()
            } else if (probe.phase === 6) {
                check("reopened: the review starts clean", inDialog("sendReviewDialog", "sendReviewError").visible, false)
                review.close()
            } else if (probe.phase === 7) {
                console.log("")
                console.log("a refusal of the form itself is the Send tab's own, and shows there")
                fake.sendError = ""
                fake.sendError = "maxPriorityFeePerGas cannot exceed maxFeePerGas"
                check("on the Send tab, as worded", inSend("sendErrorLabel").text, "maxPriorityFeePerGas cannot exceed maxFeePerGas")
                check("...and visible", inSend("sendErrorLabel").visible, true)
                fake.sendError = ""
                check("a success clears it", inSend("sendErrorLabel").visible, false)

                console.log("")
                console.log("the add-address sheet opens clean, keeps its own refusal, and the book's line does not repeat it")
                view.item.selectTab(4)
                fake.contactsError = "Invalid: '0xold' is not an Ethereum address"
                add.open()
            } else if (probe.phase === 8) {
                check("the sheet is up", add.visible, true)
                check("an earlier refusal is not shown in it", inDialog("bookAddDialog", "bookAddError").visible, false)
                check("...nor on the book behind it", inBook("bookError").visible, false)
                inDialog("bookAddDialog", "bookNewName").text = "Rorschach"
                check("a name with no address: Add says why it is off", inDialog("bookAddDialog", "bookAddHint").visible, true)
                check("...and is off", inDialog("bookAddDialog", "bookAddSave").enabled, false)
                inDialog("bookAddDialog", "bookNewAddress").text = "0xnope"
                check("an address: the hint goes", inDialog("bookAddDialog", "bookAddHint").visible, false)
                fake.refuseWith = "Invalid: '0xnope' is not an Ethereum address"
                inDialog("bookAddDialog", "bookAddSave").clicked()
                check("refused: said in the sheet, without its code", inDialog("bookAddDialog", "bookAddError").text,
                      "'0xnope' is not an Ethereum address")
                check("...not on the book behind it", inBook("bookError").visible, false)
                add.close()
            } else if (probe.phase === 9) {
                check("Cancel: not on the book after", inBook("bookError").visible, false)
                add.open()
            } else if (probe.phase === 10) {
                check("reopened: the sheet starts clean", inDialog("bookAddDialog", "bookAddError").visible, false)
                inDialog("bookAddDialog", "bookNewAddress").text = probe.friend
                probe.lose = true
                inDialog("bookAddDialog", "bookAddSave").clicked()
                check("a call lost on the way: the sheet is free", add.awaiting, false)
                check("...and says so", inDialog("bookAddDialog", "bookAddError").text, "The wallet did not answer. Try again.")
                add.close()
            } else if (probe.phase === 11) {
                console.log("")
                console.log("a refused forget is the book's own, and shows on its line")
                fake.refuseWith = ""
                fake.contactsError = ""
                fake.forgetRefusal = "Locked: the address book is locked"
                fake.contactsJson = JSON.stringify([{ address: probe.friend, name: "Rorschach" }])
            } else {
                inBook("bookForget_0").clicked()
                check("on the book, in words", inBook("bookError").text, "the address book is locked")
                check("...and visible", inBook("bookError").visible, true)
                settle.stop()
                console.log("")
                console.log("RESULT: " + (probe.failures ? probe.failures + " FAILED" : "ALL PASS"))
                Qt.exit(probe.failures ? 1 : 0)
            }
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/EthWalletView.qml")
}
