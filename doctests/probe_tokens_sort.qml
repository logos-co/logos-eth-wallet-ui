// The Tokens tab's sort control, LOADED and DRIVEN, with no app and no backend.
//
// The order itself is the BACKEND's: get_balances answers a row for every enabled token,
// already sorted by the persisted order, because comparing 18-decimal amounts is exact U256
// work and belongs where a table can run it. What is measured here is the other half — that
// the list on screen FOLLOWS that order, that the menu says which one is in force, and that
// nothing on it promises an order by value. This wallet has no prices and will not fetch any.
//
// The fake backend is a QtObject, not the plain JS object probe_tx_detail.qml hands over: a
// write to a JS object's field notifies nothing, and the second half of this file MOVES the
// published order and watches the screen follow it.
import QtQuick

Item {
    id: probe
    width: 900
    height: 700

    readonly property string me: "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"

    property int failures: 0

    function check(label, got, want) {
        var ok = String(got) === String(want)
        if (!ok)
            probe.failures++
        console.log((ok ? "  PASS  " : "  FAIL  ") + label + "   got=" + got
                    + (ok ? "" : "  want=" + want))
    }

    // Depth-first over `data`, which holds every child including a Control's contentItem.
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

    // A Menu is a Popup, not an Item: its rows are reachable through the menu's own contentModel
    // and nowhere in the item tree `find` walks.
    function sortItem(order) {
        var menu = find(view.item, "tokenSortMenu")
        if (!menu)
            return null
        for (var i = 0; i < menu.count; ++i)
            if (menu.itemAt(i).objectName === "tokenSort_" + order)
                return menu.itemAt(i)
        return null
    }

    readonly property string weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    readonly property string dai: "0x6B175474E89094C44Da98b954EedeAC495271d0F"
    readonly property string usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

    // A row is named for its CONTRACT, case-folded; the native currency for the one key an
    // address cannot spell. Two rows named for a shared symbol would be one row said twice.
    function key(t) { return t.native === true ? "native" : String(t.address).toLowerCase() }

    // The rows as they are LAID OUT, top to bottom — not the model the view was handed.
    function rowOrder() {
        var list = JSON.parse(probe.tokens), rows = []
        for (var i = 0; i < list.length; ++i) {
            var r = find(view.item, "tokenRow_" + probe.key(list[i]))
            if (r)
                rows.push({ sym: list[i].symbol, y: r.y })
        }
        rows.sort(function (a, b) { return a.y - b.y })
        return rows.map(function (o) { return o.sym }).join(",")
    }

    // Four tokens in the order list_tokens answers, native first. USDC is on the list and in
    // NEITHER balances reply: a token the balances do not name keeps its place rather than
    // dropping off a screen that is the only place the user can see it.
    readonly property string tokens: JSON.stringify([
        { symbol: "ETH", name: "Ether", decimals: 18, native: true },
        { symbol: "WETH", name: "Wrapped Ether", decimals: 18, native: false,
          address: probe.weth },
        { symbol: "DAI", name: "Dai Stablecoin", decimals: 18, native: false,
          address: probe.dai },
        { symbol: "USDC", name: "USD Coin", decimals: 6, native: false,
          address: probe.usdc }
    ])
    // The same three balances in the two orders the backend persists. DAI is zero and still
    // has a row: an enabled token is on the list whether or not it holds anything.
    readonly property string alphaFirst: JSON.stringify([
        { symbol: "DAI", address: probe.dai, native: false,
          display: "0", exact: "0", amountExact: "0" },
        { symbol: "ETH", native: true, display: "1.5", exact: "1.5", amountExact: "1.5" },
        { symbol: "WETH", address: probe.weth, native: false,
          display: "2.5", exact: "2.5", amountExact: "2.5" }
    ])
    readonly property string balanceFirst: JSON.stringify([
        { symbol: "WETH", address: probe.weth, native: false,
          display: "2.5", exact: "2.5", amountExact: "2.5" },
        { symbol: "ETH", native: true, display: "1.5", exact: "1.5", amountExact: "1.5" },
        { symbol: "DAI", address: probe.dai, native: false,
          display: "0", exact: "0", amountExact: "0" }
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
        property string accountsJson: JSON.stringify([probe.me])
        property string selectedAccount: probe.me
        property string accountLabelsJson: "{}"
        property string balancesJson: probe.alphaFirst
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
        property string tokenSort: "alpha"
        property var sortCalls: []
        function chooseTokenSort(order) {
            var c = fake.sortCalls
            c.push(order)
            fake.sortCalls = c
        }
    }

    property var logos: ({ module: function (n) { return fake } })

    // Driven through the button a human presses. `visible` on anything inside a CLOSED popup
    // reads false whatever its binding says, so every assertion about a menu row below is made
    // with the menu open — and opening it this way is also what proves the button does.
    function openMenu() {
        find(view.item, "tokenSortButton").clicked()
    }

    function assertMenu() {
        console.log("")
        console.log("the sort button opens a menu of the two orders")
        var menu = find(view.item, "tokenSortMenu")
        check("the button opens it", menu ? menu.visible : false, true)
        check("the menu offers two orders", menu ? menu.count : 0, 2)
        check("...alphabetical", sortItem("alpha").text, "Alphabetically (A-Z)")
        check("...and declining balance", sortItem("balance").text, "Declining balance")
        console.log("   MetaMask calls the second one \"Declining balance ($ high-low)\". There")
        console.log("   are no prices here and there will not be — a price feed is told which")
        console.log("   tokens to quote, which is the holdings — so no label may promise one")
        check("no label orders by money",
              (sortItem("alpha").text + sortItem("balance").text).indexOf("$"), -1)
        check("...and the second says what it DOES order by",
              find(sortItem("balance"), "tokenSortNote_balance").text,
              "By token amount, not by value")
        check("...where the order is chosen, not somewhere else",
              find(sortItem("balance"), "tokenSortNote_balance").visible, true)
        check("...while the first needs no such line",
              find(sortItem("alpha"), "tokenSortNote_alpha").visible, false)
        console.log("   and the order in force is ticked. Drawn by the view, not by the style:")
        console.log("   a `checkable` row TOGGLES on the click, which overwrites the binding")
        console.log("   that reads the persisted order")
        check("the persisted order is ticked",
              find(sortItem("alpha"), "tokenSortTick_alpha").visible, true)
        check("...and the other one is not",
              find(sortItem("balance"), "tokenSortTick_balance").visible, false)
        console.log("   Menu leaves contentWidth at 0 unless it is told, and every row then")
        console.log("   renders at the background's width: measured at 126 for a row wanting")
        console.log("   229, with the tick drawn on top of the line under it")
        var row = sortItem("balance")
        check("the menu is as wide as its widest row", row.width >= row.implicitWidth, true)
        check("...so the tick sits clear of the line it belongs to",
              find(row, "tokenSortTick_balance").x
              >= row.contentItem.x + find(row, "tokenSortNote_balance").width, true)
    }

    function assertAlphaOrder() {
        console.log("the Tokens tab carries a sort control, and the order in force is readable")
        console.log("without opening it")
        check("the strip is on screen", find(view.item, "tokenSortStrip").visible, true)
        check("...naming the order the backend persisted",
              find(view.item, "tokenSortLabel").text, "Alphabetically (A-Z)")
        console.log("   and the list is laid out in the order get_balances published — the")
        console.log("   token list's own order is ETH,WETH,DAI,USDC, and nothing here compares")
        console.log("   an amount")
        check("the rows follow the backend", rowOrder(), "DAI,ETH,WETH,USDC")
        check("...every enabled token has a row, including the zero one",
              find(view.item, "balance_" + probe.dai.toLowerCase()).text, "0")
        check("...and a token the balances do not name keeps its place, at the end",
              find(view.item, "balance_" + probe.usdc.toLowerCase()).text, "—")
    }

    function assertOrderMoved() {
        console.log("")
        console.log("the backend persists the other order and re-sorts what it publishes. The")
        console.log("token list itself did not move: this is the balances' order, followed")
        check("the rows follow it there", rowOrder(), "WETH,ETH,DAI,USDC")
        check("the strip says so", find(view.item, "tokenSortLabel").text, "Declining balance")
        check("...and the tick moved with it",
              find(sortItem("balance"), "tokenSortTick_balance").visible, true)
        check("...off the order that is no longer in force",
              find(sortItem("alpha"), "tokenSortTick_alpha").visible, false)
    }

    function assertAsksBackend() {
        console.log("")
        console.log("choosing an order ASKS: the backend persists it and re-sorts the balances,")
        console.log("and the list follows those. Nothing is sorted here")
        sortItem("alpha").triggered()
        check("the menu asks for the order chosen", JSON.stringify(fake.sortCalls),
              JSON.stringify(["alpha"]))
        sortItem("balance").triggered()
        check("...and asks nothing for the one already in force",
              JSON.stringify(fake.sortCalls), JSON.stringify(["alpha"]))
    }

    function assertUnknownIsNotAnOrder() {
        console.log("")
        console.log("an order this build does not know is shown as no order at all, and an")
        console.log("unread balance set is not an order either — it is the list, unsorted")
        check("the strip falls back rather than naming an order nothing can show",
              find(view.item, "tokenSortLabel").text, "Alphabetically (A-Z)")
        check("...with exactly one row ticked, never two",
              (find(sortItem("alpha"), "tokenSortTick_alpha").visible ? 1 : 0)
              + (find(sortItem("balance"), "tokenSortTick_balance").visible ? 1 : 0), 1)
        check("...and the list keeps the token list's own order",
              rowOrder(), "ETH,WETH,DAI,USDC")
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
            // The delegates do not exist until the view has laid out, which the handler that
            // loaded it cannot wait for.
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
                probe.assertAlphaOrder()
                probe.openMenu()
            } else if (probe.phase === 2) {
                probe.assertMenu()
                fake.tokenSort = "balance"
                fake.balancesJson = probe.balanceFirst
            } else if (probe.phase === 3) {
                probe.assertOrderMoved()
                // Choosing dismisses the menu, as a click on it does.
                probe.assertAsksBackend()
                fake.tokenSort = "by-vibes"
                fake.balancesJson = ""
                probe.openMenu()
            } else {
                probe.assertUnknownIsNotAnOrder()
                console.log("")
                console.log("RESULT: " + (probe.failures ? probe.failures + " FAILED"
                                                         : "ALL PASS"))
                Qt.exit(probe.failures ? 1 : 0)
            }
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/EthWalletView.qml")
}
