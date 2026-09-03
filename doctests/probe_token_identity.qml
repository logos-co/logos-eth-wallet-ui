// TWO CONTRACTS THAT CALL THEMSELVES THE SAME THING, on screen at once.
//
// A token is its (chain, contract). The shipped token list carries five (chainId, symbol)
// pairs answered by two different contracts, and on chain 1 "LIT" is BOTH Litentry
// 0xb59490aB…9723 and Lighter 0x232CE3bd…4Ee2, both at 18 decimals. Holding both is ordinary,
// and both addresses below are the real ones.
//
// Keyed by symbol, the wallet answered the FIRST row wearing it: one token's row showed the
// other's balance, a 1000-unit holding rendered as nothing, the second contract's detail
// screen was unreachable, the two rows shared an objectName, and the picker put a bare symbol
// on the wire — which is how the wrong asset gets spent. Every check below is paired with a
// control that would still pass if the symbol were the key, or that shows the two answers
// really are different.
//
// The fake backend is a QtObject: a write to a plain JS object's field notifies nothing.
import QtQuick

Item {
    id: probe
    width: 900
    height: 700

    readonly property string me: "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"
    readonly property int chain: 1

    readonly property string litentry: "0xb59490aB09A0f526Cc7305822aC65f2Ab12f9723"
    readonly property string lighter: "0x232CE3bd40fCd6f80f3d55A522d03f25Df784Ee2"
    readonly property string usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

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

    // The view's own identity rule, restated here so a probe that agreed with a bug in it
    // would not agree with itself.
    function key(addr) { return addr === "" ? "native" : String(addr).toLowerCase() }

    function txt(name) { var o = find(view.item, name); return o ? String(o.text) : "<missing>" }
    function vis(name) { var o = find(view.item, name); return o ? o.visible : "<missing>" }

    // The rows as they are LAID OUT, top to bottom, named by contract.
    function rowOrder() {
        var addrs = ["", probe.litentry, probe.lighter, probe.usdc]
        var names = ["ETH", "LIT/Litentry", "LIT/Lighter", "USDC"], rows = []
        for (var i = 0; i < addrs.length; ++i) {
            var r = find(view.item, "tokenRow_" + probe.key(addrs[i]))
            if (r)
                rows.push({ name: names[i], y: r.y })
        }
        rows.sort(function (a, b) { return a.y - b.y })
        return rows.map(function (o) { return o.name }).join(",")
    }

    // list_tokens' order: native first, then the offered contracts.
    readonly property string tokens: JSON.stringify([
        { symbol: "ETH", name: "Ether", decimals: 18, native: true, builtin: true },
        { symbol: "LIT", name: "Litentry", decimals: 18, native: false,
          address: probe.litentry },
        { symbol: "LIT", name: "Lighter", decimals: 18, native: false,
          address: probe.lighter },
        { symbol: "USDC", name: "USD Coin", decimals: 6, native: false, address: probe.usdc }
    ])

    // get_balances' order, which the Tokens tab renders. The two LITs are NOT adjacent in it:
    // collapsed onto one symbol key they take one position between them, the comparator
    // answers 0 for the pair, and Qt's unstable sort then reshuffles the whole list.
    readonly property string balances: JSON.stringify([
        { symbol: "LIT", address: probe.litentry, native: false,
          display: "1000", exact: "1000", amountExact: "1000" },
        { symbol: "ETH", native: true, display: "1.5", exact: "1.5", amountExact: "1.5" },
        { symbol: "LIT", address: probe.lighter, native: false,
          display: "0", exact: "0", amountExact: "0" },
        { symbol: "USDC", address: probe.usdc, native: false,
          display: "12", exact: "12", amountExact: "12" }
    ])

    // What get_balances answers once Lighter is turned off: no row for it AT ALL. Its figure
    // on the Manage screen has to come from that absence, not from its namesake's row.
    readonly property string balancesLighterOff: JSON.stringify([
        { symbol: "LIT", address: probe.litentry, native: false,
          display: "1000", exact: "1000", amountExact: "1000" },
        { symbol: "ETH", native: true, display: "1.5", exact: "1.5", amountExact: "1.5" },
        { symbol: "USDC", address: probe.usdc, native: false,
          display: "12", exact: "12", amountExact: "12" }
    ])

    // The catalogue behind Manage tokens: the same pair, one of them turned OFF. A disabled
    // token is in no balances reply at all, so its figure is an em-dash — never the holding
    // of whichever enabled contract happens to wear the same symbol.
    readonly property string available: JSON.stringify({
        ok: true, chainId: probe.chain, tokenSort: "alpha", total: 3, shown: 3, listed: 400,
        tokens: [
            { symbol: "ETH", name: "Ether", decimals: 18,
              native: true, enabled: true, builtin: true, source: "native" },
            { symbol: "LIT", name: "Litentry", decimals: 18, address: probe.litentry,
              native: false, enabled: true, builtin: false, source: "embedded" },
            { symbol: "LIT", name: "Lighter", decimals: 18, address: probe.lighter,
              native: false, enabled: false, builtin: false, source: "embedded" }
        ]
    })

    QtObject {
        id: fake

        property string lastError: ""
        property bool scopedDataFresh: true
        property bool dataLoading: false
        property bool quoteLoading: false
        property string activeNetworkJson: JSON.stringify({ chainId: probe.chain,
                                                            name: "Ethereum",
                                                            nativeSymbol: "ETH", testnet: false })
        property string networksJson: "[]"
        property string verifiedProxyJson: JSON.stringify({ ok: true, chainId: probe.chain,
                                                            mode: "off" })
        property string accountsJson: JSON.stringify([probe.me])
        property string selectedAccount: probe.me
        property string accountLabelsJson: "{}"
        property string balancesJson: probe.balances
        property string balancesRoute: "direct"
        property string tokensJson: probe.tokens
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
        property string pendingRequestId: ""
        property string tokenSort: "alpha"

        function chooseTokenSort(order) {}
        function quote(requestJson) {}
        function setQuoteAutoRefresh(on) {}
        function searchTokens(query) { fake.availableTokensJson = probe.available }
        function setTokenEnabled(address, on) {}
    }

    property var logos: ({ module: function (n) { return fake } })

    // ── the list ──────────────────────────────────────────────────────────────────
    function assertTwoRows() {
        console.log("two contracts on chain 1 both call themselves LIT. They are two tokens,")
        console.log("and the screen has to be able to say so")
        var a = find(view.item, "tokenRow_" + probe.key(probe.litentry))
        var b = find(view.item, "tokenRow_" + probe.key(probe.lighter))
        check("the first contract has a row", a !== null, true)
        check("...and the second has its own", b !== null, true)
        check("...which is a DIFFERENT row, not the same one found twice",
              a !== null && b !== null && a !== b, true)
        console.log("   an objectName the two shared named whichever rendered last, so a")
        console.log("   harness could not assert on either of them")
        check("...at its own place on screen", a !== null && b !== null && a.y !== b.y, true)
    }

    function assertOwnBalance() {
        console.log("")
        console.log("and each row carries its OWN holding. Matched on the symbol, both rows")
        console.log("answered the FIRST balance wearing it: a real 1000-unit holding rendered")
        console.log("as 0 on the row that owns it, and 1000 on the row that does not")
        check("the contract holding 1000 says 1000",
              txt("balance_" + probe.key(probe.litentry)), "1000")
        check("...and the one holding nothing says 0",
              txt("balance_" + probe.key(probe.lighter)), "0")
        console.log("   control: those are two different answers, so this is not one figure")
        console.log("   read twice — and neither row is showing the other's")
        check("the two rows disagree",
              txt("balance_" + probe.key(probe.litentry))
              !== txt("balance_" + probe.key(probe.lighter)), true)
        console.log("   control: a token the balances DO name is still found — keying on the")
        console.log("   contract did not simply stop matching")
        check("an unambiguous token keeps its balance",
              txt("balance_" + probe.key(probe.usdc)), "12")
        check("...the native currency too", txt("balance_native"), "1.5")
        check("...including the headline figure, which is the native row and no other",
              txt("primaryBalance"), "1.5 ETH")
    }

    function assertTellableApart() {
        console.log("")
        console.log("a human has to be able to tell them apart too: the name, and enough of the")
        console.log("contract to distinguish it")
        check("the first is named", txt("tokenName_" + probe.key(probe.litentry)), "Litentry")
        check("...the second differently", txt("tokenName_" + probe.key(probe.lighter)),
              "Lighter")
        check("the first carries its contract",
              txt("tokenContract_" + probe.key(probe.litentry)), "0xb594…9723")
        check("...and the second its own",
              txt("tokenContract_" + probe.key(probe.lighter)), "0x232C…4Ee2")
        check("...on screen, not merely set",
              vis("tokenContract_" + probe.key(probe.litentry)), true)
        console.log("   control: a symbol only one contract wears needs no such line — the")
        console.log("   address appears where it settles a question, not on every row")
        check("an unambiguous row carries no contract",
              txt("tokenContract_" + probe.key(probe.usdc)), "")
        check("...and does not show one", vis("tokenContract_" + probe.key(probe.usdc)), false)
    }

    function assertOrderSurvives() {
        console.log("")
        console.log("the list is the BACKEND's order. Two rows sharing a position is a")
        console.log("comparator that answers 0 for the pair, and Qt's sort is unstable — the")
        console.log("whole published order was lost, not just the pair's")
        check("the rows follow get_balances exactly", rowOrder(),
              "LIT/Litentry,ETH,LIT/Lighter,USDC")
    }

    // ── the detail screen ─────────────────────────────────────────────────────────
    function assertDetail(addr, name, exact, contract) {
        check("the screen opened", find(view.item, "tokenDetailPage") !== null, true)
        check("...for " + name, txt("tokenDetailName"), name)
        check("...showing that contract's balance", txt("tokenDetailBalance"), exact + " LIT")
        var row = find(view.item, "tokenContractRow")
        check("...and naming the contract it is about", row ? String(row.copyValue) : "", addr)
        check("...shortened on screen", row ? String(row.value) : "", contract)
    }

    // ── the send picker ───────────────────────────────────────────────────────────
    function dialog() { return find(view.item, "sendDialog") }
    function form() { var d = dialog(); return d ? d.contentItem : null }
    function picker() { return find(form(), "sendTokenPicker") }

    // What a human does: the row is chosen, and THEN the signal fires — which is the order the
    // handler is written against.
    function pick(i) {
        var p = picker()
        p.currentIndex = i
        p.activated(i)
    }

    function assertSendNamesTheContract() {
        console.log("")
        console.log("the picker decides which asset LEAVES the account. A bare symbol on the")
        console.log("wire is a symbol the backend cannot resolve to one contract — it refuses")
        console.log("an ambiguous one now, so the address is what makes either send possible")
        var p = picker()
        check("the picker offers both", p ? p.count : 0, 4)
        console.log("   and it says which is which, by name and contract — this control is the")
        console.log("   last place the wrong asset can still be chosen")
        check("...naming the first", String(p.model[1]).indexOf("Litentry 0xb594…9723") >= 0,
              true)
        check("...and the second", String(p.model[2]).indexOf("Lighter 0x232C…4Ee2") >= 0, true)
        console.log("   control: an unambiguous row is left alone — no name, no contract")
        check("USDC's line is the symbol and the balance", String(p.model[3]), "USDC — 12")

        pick(2)
        var req = JSON.parse(form().request())
        check("choosing the second LIT puts its CONTRACT on the wire", req.tokenAddress,
              probe.lighter)
        check("...and still names the symbol, which the backend takes as a label", req.token,
              "LIT")
        console.log("   control: the other LIT is a different request, not the same one twice")
        pick(1)
        var other = JSON.parse(form().request())
        check("the first LIT names the OTHER contract", other.tokenAddress, probe.litentry)
        check("...while the symbol alone cannot tell them apart",
              other.token === req.token, true)
        console.log("   control: the native currency has no contract to name")
        pick(0)
        check("a native send carries no address",
              JSON.parse(form().request()).tokenAddress === undefined, true)
    }

    // The dialog's own items. A closed Popup's contentItem is not in the Item tree `find`
    // walks from the view, so the send column is searched from the form itself.
    function ftxt(name) { var o = find(form(), name); return o ? String(o.text) : "<missing>" }
    function fvis(name) { var o = find(form(), name); return o ? o.visible : "<missing>" }

    // prepare_send's reply for the token the picker chose, priced against `addr`.
    function priceFor(addr) {
        fake.quoteJson = JSON.stringify({ ok: true, gasLimit: "60000", maxFeePerGas: "1",
                                          nonce: 3, token: "LIT", tokenAddress: addr,
                                          nativeSymbol: "ETH" })
        fake.quoteRequestJson = form().request()
    }

    function assertQuotePricedContract() {
        console.log("")
        console.log("the Send screen is the last thing between a symbol and a signature, so the")
        console.log("figures say which CONTRACT they priced — prepare_send's own answer, not a")
        console.log("restatement of what the form asked")
        check("the priced contract is named", ftxt("quoteTokenNote"),
              "Priced for Lighter 0x232C…4Ee2")
        check("...on screen", fvis("quoteTokenNote"), true)
        console.log("   and if the backend resolved a contract the picker did not choose, that")
        console.log("   is a send about to move the wrong asset and it says so")
        fake.quoteJson = JSON.stringify({ ok: true, gasLimit: "60000", maxFeePerGas: "1",
                                          nonce: 3, token: "LIT",
                                          tokenAddress: probe.litentry, nativeSymbol: "ETH" })
        check("a mismatch is stated, not swallowed", ftxt("quoteTokenNote"),
              "These figures priced a DIFFERENT contract: Litentry 0xb594…9723")
        console.log("   control: a symbol only one contract wears needs no such line — and the")
        console.log("   line is absent, not merely empty")
        pick(3)
        priceFor(probe.usdc)
        check("an unambiguous send says nothing extra", fvis("quoteTokenNote"), false)
        console.log("   control: and a reply that named no contract at all is not a mismatch")
        pick(0)
        fake.quoteJson = JSON.stringify({ ok: true, gasLimit: "21000", maxFeePerGas: "1",
                                          nonce: 3, nativeSymbol: "ETH" })
        fake.quoteRequestJson = form().request()
        check("a native send says nothing either", fvis("quoteTokenNote"), false)
    }

    // ── Manage tokens ─────────────────────────────────────────────────────────────
    function assertDisabledRowShowsNothing() {
        console.log("")
        console.log("and in Manage tokens, where a row that is OFF sits beside an enabled one")
        console.log("wearing its symbol. A disabled token is in no balances reply at all")
        check("the enabled contract shows its holding",
              txt("manageTokenBalance_" + probe.key(probe.litentry)), "1000 LIT")
        check("...while the one that is OFF advertises nothing",
              txt("manageTokenBalance_" + probe.key(probe.lighter)), "— LIT")
        console.log("   control: the two rows are told apart here too")
        check("the disabled row names its contract",
              txt("manageTokenContract_" + probe.key(probe.lighter)), "0x232C…4Ee2")
        check("...and the enabled one names its own",
              txt("manageTokenContract_" + probe.key(probe.litentry)), "0xb594…9723")
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
            settle.start()
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
                probe.assertTwoRows()
                probe.assertOwnBalance()
                probe.assertTellableApart()
                probe.assertOrderSurvives()
                probe.assertSendNamesTheContract()
                probe.dialog().open()
            } else if (probe.phase === 2) {
                probe.pick(2)
                probe.priceFor(probe.lighter)
                probe.assertQuotePricedContract()
                probe.dialog().close()
                view.item.openTokenDetail(probe.key(probe.lighter))
            } else if (probe.phase === 3) {
                console.log("")
                console.log("the second contract's own screen, which by symbol was unreachable:")
                console.log("the lookup answered the first row wearing LIT, every time")
                probe.assertDetail(probe.lighter, "Lighter", "0", "0x232C…4Ee2")
                view.item.openTokenDetail(probe.key(probe.litentry))
            } else if (probe.phase === 4) {
                console.log("")
                console.log("   control: the other key opens the OTHER screen")
                probe.assertDetail(probe.litentry, "Litentry", "1000", "0xb594…9723")
                fake.balancesJson = probe.balancesLighterOff
                view.item.openManageTokens()
            } else {
                probe.assertDisabledRowShowsNothing()
                console.log("")
                console.log("RESULT: " + (probe.failures ? probe.failures + " FAILED"
                                                         : "ALL PASS"))
                Qt.exit(probe.failures ? 1 : 0)
            }
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/EthWalletView.qml")
}
