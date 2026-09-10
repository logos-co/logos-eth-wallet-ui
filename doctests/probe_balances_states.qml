// The balance cell says READING, then answers — and never both, and never neither.
//
// Three situations rendered the same em-dash: never fetched, fetched and empty, and fetched
// and refused. The user opened a cold wallet and got a red Rust `Debug` blob over a column of
// dashes, with nothing on screen saying a read was even in flight.
//
// The row that matters most here is the fourth: `balancesLoading` false while `dataLoading` is
// still TRUE. That is the real shape of a refused read — the lane is held by the history leg
// that goes out next — and a spinner gated on the lane spins there for up to 20s BESIDE the
// error the balances read already produced. Three of the four candidate designs for this fix
// died on exactly that, so it is asserted rather than reasoned about.
//
// The fake is a QtObject because this probe MOVES the flags, and a write to a plain JS
// object's field notifies nothing.
import QtQuick

Item {
    id: probe
    width: 1200
    height: 1000

    readonly property string me: "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"
    readonly property string weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    readonly property string dai: "0x6B175474E89094C44Da98b954EedeAC495271d0F"
    readonly property string usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

    property int failures: 0
    property real rowYWithNoBanner: -1

    // Where the first balance row sits in the view. The geometry no other assertion here
    // looks at, and the one the layout regression moved.
    function tokenRowY() {
        var r = probe.find(view.item, "tokenRow_native")
        return r ? r.mapToItem(view.item, 0, 0).y : -1
    }

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

    // TOTAL: a missing element must report as absent, not throw. A probe that dies half way
    // prints its header and nothing under it, which reads as a pass to anything scanning.
    function shown(name) {
        var o = probe.find(view.item, name)
        return o ? o.visible : "<absent>"
    }
    function textOf(name) {
        var o = probe.find(view.item, name)
        return o ? String(o.text) : "<absent>"
    }

    readonly property string tokens: JSON.stringify([
        { symbol: "ETH", name: "Ether", decimals: 18, native: true },
        { symbol: "WETH", name: "Wrapped Ether", decimals: 18, native: false,
          address: probe.weth }
    ])
    readonly property string answered: JSON.stringify([
        { symbol: "ETH", native: true, display: "1.5", exact: "1.5", amountExact: "1.5" },
        { symbol: "WETH", address: probe.weth, native: false,
          display: "2.5", exact: "2.5", amountExact: "2.5" }
    ])

    QtObject {
        id: fake

        property string lastError: ""
        property bool scopedDataFresh: true
        property bool dataLoading: true
        property bool balancesLoading: true
        property bool quoteLoading: false
        property string activeNetworkJson: JSON.stringify({ chainId: 11155111, name: "Sepolia",
                                                            nativeSymbol: "ETH", testnet: true })
        property string networksJson: "[]"
        property string verifiedProxyJson: JSON.stringify({ ok: true, chainId: 11155111,
                                                            mode: "off" })
        property string accountsJson: JSON.stringify([probe.me])
        property string selectedAccount: probe.me
        property string accountLabelsJson: "{}"
        property string balancesJson: ""
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

        // The persisted order, and every call the view made to move it.
        property int refreshCalls: 0
        function refresh() { fake.refreshCalls++; fake.lastError = "" }

        property string tokenSort: "alpha"
        property var sortCalls: []
        function chooseTokenSort(order) {
            var c = fake.sortCalls
            c.push(order)
            fake.sortCalls = c
        }
    }

    property var logos: ({ module: function (n) { return fake },
                           isViewModuleReady: function (n) { return true } })

    // Cheap sanity on where the rows sit. It does NOT catch the fillHeight regression that
    // once pushed the balances off the bottom — MEASURED: removing the pin still passes here,
    // because this probe's column has no spare height to hand out the way the real window
    // does. What pins that is the source-shape check in assert_ui.py.
    function assertAnAbsentBannerTakesNoSpace() {
        console.log("")
        console.log("no error, so the banner row occupies no height at all — and the rows")
        console.log("below it are still on screen")
        var row = probe.find(view.item, "errorRow")
        check("the row is there", row !== null, true)
        check("...but not shown", row ? row.visible : "<absent>", false)
        probe.rowYWithNoBanner = probe.tokenRowY()
        check("...so the first token row is on screen",
              probe.rowYWithNoBanner >= 0 && probe.rowYWithNoBanner < probe.height, true)
    }

    function assertAFirstReadSpins() {
        console.log("")
        console.log("the first read is outstanding: nothing is known and something is being")
        console.log("read, which is the one combination that earns a spinner")
        check("the native row spins", probe.shown("balanceSpinner_native"), true)
        check("...and shows no amount instead", probe.shown("balance_native"), false)
        check("the token row spins too",
              probe.shown("balanceSpinner_" + probe.weth.toLowerCase()), true)
        check("no banner while it is merely slow", probe.shown("errorLabel"), false)
        check("...and nothing to retry yet", probe.shown("errorRetryButton"), false)
    }

    function assertAnAnswerReplacesIt() {
        console.log("")
        console.log("the amounts land. The spinner is gone, not merely covered")
        check("the spinner stopped", probe.shown("balanceSpinner_native"), false)
        check("...and the figure is on screen", probe.shown("balance_native"), true)
        check("...reading the amount", probe.textOf("balance_native"), "1.5")
        check("still no banner", probe.shown("errorLabel"), false)
    }

    function assertARefusalIsNotASpinner() {
        console.log("")
        console.log("THE ROW THAT MATTERS. The balances read was refused, so its leg is down —")
        console.log("but the LANE is still up, because the history call goes out next. A")
        console.log("spinner gated on the lane would spin here beside the error, for as long")
        console.log("as the history leg takes")
        check("dataLoading is still up", fake.dataLoading, true)
        check("...and the balances leg is not", fake.balancesLoading, false)
        check("no spinner", probe.shown("balanceSpinner_native"), false)
        check("...the cell falls back to an em-dash", probe.textOf("balance_native"), "—")
        check("the banner says what happened", probe.shown("errorLabel"), true)
        check("...in a sentence, not a Debug render",
              probe.textOf("errorLabel").indexOf("PluginCallFailed"), -1)
        check("...and offers the way out", probe.shown("errorRetryButton"), true)

        console.log("")
        console.log("   and the banner is a BANNER. A Layout nested in a Layout defaults to")
        console.log("   fillHeight true, so this row once claimed every spare pixel and pushed")
        console.log("   the balances off the bottom — while every assertion above still passed.")
        var moved = probe.tokenRowY() - probe.rowYWithNoBanner
        check("the rows moved down by a banner, not by a screenful", moved > 0 && moved < 120,
              true)
        check("...and are still on screen", probe.tokenRowY() < probe.height, true)
    }

    function assertRetryAsksAgain() {
        console.log("")
        console.log("Retry is the only re-read this view has: nothing else here calls refresh,")
        console.log("so without it a failed first read is a dead wallet until the user")
        console.log("navigates away and back")
        var btn = probe.find(view.item, "errorRetryButton")
        if (!btn) {
            probe.failures++
            console.log("  FAIL  errorRetryButton is not in the tree")
            return
        }
        btn.clicked()
        check("it asked the backend", fake.refreshCalls, 1)
        check("...and the banner cleared with it", probe.shown("errorLabel"), false)
        check("...taking the button with it", probe.shown("errorRetryButton"), false)
    }

    function assertARereadKeepsTheOldFigure() {
        console.log("")
        console.log("re-reading over a known balance shows the previous figure, not a spinner:")
        console.log("a column that empties itself on every refresh reads as a lost balance")
        check("the figure stayed", probe.textOf("balance_native"), "1.5")
        check("...with no spinner over it", probe.shown("balanceSpinner_native"), false)
    }

    Loader {
        id: view
        anchors.fill: parent
        onStatusChanged: {
            if (status === Loader.Error) {
                console.log("  FAIL  the view did not load")
                Qt.exit(1)
            }
            if (status === Loader.Ready)
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
                probe.assertAnAbsentBannerTakesNoSpace()
                probe.assertAFirstReadSpins()
                fake.balancesJson = probe.answered
                fake.balancesLoading = false
                fake.dataLoading = false
            } else if (probe.phase === 2) {
                probe.assertAnAnswerReplacesIt()
                // A fresh selection: nothing known, both legs out.
                fake.balancesJson = ""
                fake.dataLoading = true
                fake.balancesLoading = true
            } else if (probe.phase === 3) {
                // The balances leg answers with a refusal; the history leg stays out.
                fake.balancesLoading = false
                fake.lastError = "balances: the Ethereum RPC service did not answer"
            } else if (probe.phase === 4) {
                probe.assertARefusalIsNotASpinner()
                probe.assertRetryAsksAgain()
                fake.balancesJson = probe.answered
                fake.dataLoading = false
                // A re-read over a known figure.
                fake.balancesLoading = true
            } else {
                probe.assertARereadKeepsTheOldFigure()
                console.log("")
                console.log("RESULT: " + (probe.failures ? probe.failures + " FAILED"
                                                         : "ALL PASS"))
                Qt.exit(probe.failures ? 1 : 0)
            }
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/EthWalletView.qml")
}
