// The Manage tokens screen, LOADED and DRIVEN, with no app and no backend.
//
// What it measures is the screen working: the catalogue the backend answered is on screen as
// rows, a row that cannot be turned off does not offer to be, a press ASKS the backend rather
// than moving the row itself, and the query goes out as a call rather than filtering a list
// pulled into the view — the embedded Uniswap list is thousands of rows.
//
// The fake backend is a QtObject, not a plain JS object: a write to a JS object's field
// notifies nothing, and this file MOVES the published catalogue and watches the screen follow.
import QtQuick

Item {
    id: probe
    width: 900
    height: 700

    readonly property string me: "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"
    readonly property int chain: 11155111

    readonly property string weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    readonly property string dai: "0x6B175474E89094C44Da98b954EedeAC495271d0F"
    readonly property string usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

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

    // The view keys every row on its CONTRACT, case-folded, and the native row on the one key
    // an address cannot spell. A row named for its symbol was a row two contracts shared.
    function key(k) { return k === "ETH" ? "native" : String(k).toLowerCase() }

    function toggleFor(k) { return find(view.item, "manageTokenToggle_" + probe.key(k)) }

    // The rows as they are LAID OUT, top to bottom — not the model the view was handed.
    function rowOrder() {
        var keys = ["ETH", probe.weth, probe.dai, probe.usdc], rows = []
        for (var i = 0; i < keys.length; ++i) {
            var r = find(view.item, "manageTokenRow_" + probe.key(keys[i]))
            if (r)
                rows.push({ key: keys[i], y: r.y })
        }
        rows.sort(function (a, b) { return a.y - b.y })
        return rows.map(function (o) { return o.key }).join(",")
    }

    // What a press does to a real switch: the click moves `checked` and THEN the signal fires,
    // which is the order the handler is written against — it reads what the press meant.
    function press(sw) {
        sw.toggle()
        sw.toggled()
    }

    // The catalogue the backend offers on this chain. Native first, then enabled, then the
    // rest — the order is the backend's and the screen renders it as given. USDC is offered
    // and OFF, which is the only row a press may move.
    function catalogue(chainId) {
        return JSON.stringify({
            ok: true, chainId: chainId, tokenSort: "alpha", total: 4, shown: 4, listed: 40,
            tokens: [
                { symbol: "ETH", name: "Ether", decimals: 18,
                  native: true, enabled: true, builtin: true, source: "native" },
                { symbol: "WETH", name: "Wrapped Ether", decimals: 18, address: probe.weth,
                  native: false, enabled: true, builtin: true, source: "allowlist" },
                { symbol: "DAI", name: "Dai Stablecoin", decimals: 18, address: probe.dai,
                  native: false, enabled: true, builtin: false, source: "enabled" },
                { symbol: "USDC", name: "USD Coin", decimals: 6, address: probe.usdc,
                  native: false, enabled: false, builtin: false, source: "embedded" }
            ]
        })
    }

    // Same four rows, with the three counts moved. `total` above `shown` is the CUT: the query
    // matched more than came back, which the screen may not swallow.
    function cutCatalogue(total, shown) {
        var c = JSON.parse(probe.catalogue(probe.chain))
        c.total = total
        c.shown = shown
        return JSON.stringify(c)
    }

    // The ordinary sepolia answer: `listed: 0`, NO listError. A real, complete reply — the
    // bundled list is a mainnet snapshot — so only the built-in rows are offered.
    function emptyChainCatalogue() {
        var c = JSON.parse(probe.catalogue(probe.chain))
        c.listed = 0
        c.total = 1
        c.shown = 1
        c.tokens = [c.tokens[0]]
        return JSON.stringify(c)
    }

    // The list itself could not be read. A DIFFERENT answer from the one above, and the only
    // one that is a failure.
    function failedCatalogue(rows) {
        var c = JSON.parse(probe.catalogue(probe.chain))
        c.listed = 0
        c.listError = "token_list: connection refused"
        c.tokens = rows ? [c.tokens[0]] : []
        c.total = rows ? 1 : 0
        c.shown = c.total
        return JSON.stringify(c)
    }

    // A query that matched nothing on a chain whose list is perfectly readable.
    function noMatchCatalogue() {
        var c = JSON.parse(probe.catalogue(probe.chain))
        c.total = 0
        c.shown = 0
        c.tokens = []
        return JSON.stringify(c)
    }

    property int searchesBefore: 0
    function searchCount() { return fake.searchCalls.length }
    function searchesSince() { return fake.searchCalls.length - probe.searchesBefore }
    function lastSearch() {
        return fake.searchCalls.length ? fake.searchCalls[fake.searchCalls.length - 1]
                                       : "<none>"
    }

    function txt(name) { var o = find(view.item, name); return o ? String(o.text) : "<missing>" }
    function vis(name) { var o = find(view.item, name); return o ? o.visible : "<missing>" }

    QtObject {
        id: fake

        property string lastError: ""
        property bool scopedDataFresh: true
        property bool dataLoading: false
        property bool quoteLoading: false
        property string activeNetworkJson: JSON.stringify({ chainId: probe.chain,
                                                            name: "Sepolia",
                                                            nativeSymbol: "ETH", testnet: true })
        property string networksJson: "[]"
        property string verifiedProxyJson: JSON.stringify({ ok: true, chainId: probe.chain,
                                                            mode: "off" })
        property string accountsJson: JSON.stringify([probe.me])
        property string selectedAccount: probe.me
        property string accountLabelsJson: "{}"
        // DAI is enabled and holds nothing: a row, showing zero. USDC is off, so get_balances
        // never named it and its figure is an em-dash — not a zero nobody read.
        property string balancesJson: JSON.stringify([
            { symbol: "ETH", native: true, display: "1.5", exact: "1.5", amountExact: "1.5" },
            { symbol: "WETH", address: probe.weth, native: false,
              display: "2.5", exact: "2.5", amountExact: "2.5" },
            { symbol: "DAI", address: probe.dai, native: false,
              display: "0", exact: "0", amountExact: "0" }
        ])
        property string balancesRoute: "direct"
        property string tokensJson: "[]"
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

        property string availableTokensJson: ""
        property bool availableTokensLoading: false
        property bool tokenToggleBusy: false
        property string tokenToggleError: ""

        // Every call the screen made, in order.
        property var searchCalls: []
        property var toggleCalls: []

        // Off while the phases above drive the catalogue by hand. Once on, a search is
        // ANSWERED — late, as the real one is — so the screen recovering from a chain change
        // is the view's own doing and not the probe publishing on its behalf.
        property bool answering: false

        function chooseTokenSort(order) {}
        function searchTokens(query) {
            var c = fake.searchCalls
            c.push(query)
            fake.searchCalls = c
            if (fake.answering)
                answer.restart()
        }
        function setTokenEnabled(address, on) {
            var c = fake.toggleCalls
            c.push(address + "=" + on)
            fake.toggleCalls = c
        }
    }

    property var logos: ({ module: function (n) { return fake }, isViewModuleReady: function (n) { return true } })

    function assertScreen() {
        console.log("Manage tokens is a SCREEN pushed from the Settings tab — under the tab")
        console.log("strip, with its own title and its own way back")
        check("the screen is on the stack", find(view.item, "manageTokensPage") !== null, true)
        check("...under MetaMask's own title", find(view.item, "manageTokensTitle").text,
              "Manage tokens")
        check("...with a back arrow", find(view.item, "manageTokensBackButton") !== null, true)

        console.log("")
        console.log("and opening it READ the catalogue. The Settings row is the only route a")
        console.log("user has; a route that pushes the screen without asking leaves the em-dash")
        console.log("below standing for ever, because nothing else ever asks")
        check("opening the screen read the offered set", probe.searchCount() >= 1, true)
        check("...the WHOLE of it, not a query", probe.lastSearch(), "")
        console.log("   and pushing one does not build the other two")
        check("the address book is not standing", find(view.item, "addressBookPage"), null)
        check("...nor the networks screen", find(view.item, "networksPage"), null)
        check("...and the field asks for what MetaMask asks for",
              find(view.item, "tokenSearchField").placeholderText,
              "Enter token name or address")
        console.log("   a token is enabled PER NETWORK, so the screen names the one it is")
        console.log("   asking about")
        check("the network is on screen", find(view.item, "manageTokensNetwork").text,
              "Sepolia (testnet)")
        console.log("   opening it reads the whole offered set: the empty query. The catalogue")
        console.log("   is searched by the BACKEND — the embedded list is thousands of rows")
        check("opening asks the backend for the offered set",
              JSON.stringify(fake.searchCalls), JSON.stringify([""]))
    }

    function assertRows() {
        console.log("")
        console.log("every offered token is a row, in the order the backend answered — native")
        console.log("first, then enabled, then the rest. Nothing here re-sorts it")
        check("the rows follow the backend", rowOrder(),
              ["ETH", probe.weth, probe.dai, probe.usdc].join(","))
        check("...each named", find(view.item, "manageTokenName_" + probe.key(probe.usdc)).text, "USD Coin")
        console.log("   and each carries its balance, which only an ENABLED token has: a token")
        console.log("   that is off was never in get_balances, so it is an em-dash rather than")
        console.log("   a zero nobody read")
        check("an enabled token shows its balance",
              find(view.item, "manageTokenBalance_" + probe.key(probe.weth)).text, "2.5 WETH")
        check("...zero included", find(view.item, "manageTokenBalance_" + probe.key(probe.dai)).text,
              "0 DAI")
        check("...while one that is off shows no figure at all",
              find(view.item, "manageTokenBalance_" + probe.key(probe.usdc)).text, "— USDC")
    }

    function assertLocked() {
        console.log("")
        console.log("a builtin cannot be turned off, and the native token is not a token_list")
        console.log("entry at all — neither row offers a switch that would do anything")
        check("the native row's switch is disabled", toggleFor("ETH").enabled, false)
        check("...and so is a builtin's", toggleFor(probe.weth).enabled, false)
        check("...while an ordinary token's is live", toggleFor(probe.dai).enabled, true)
        console.log("   each showing the backend's answer for that token, not a default")
        check("an enabled token reads on", toggleFor(probe.dai).checked, true)
        check("...and one that is off reads off", toggleFor(probe.usdc).checked, false)
    }

    function assertPressAsks() {
        console.log("")
        console.log("a press ASKS. set_token_enabled emits no event, so the screen cannot move")
        console.log("the row itself and then find out it was refused")
        press(toggleFor(probe.usdc))
        check("the press asks the backend, for that contract and that direction",
              JSON.stringify(fake.toggleCalls), JSON.stringify([probe.usdc + "=true"]))
        console.log("   ...and the row goes back to what the BACKEND says while it answers: the")
        console.log("   click writes `checked` directly, overwriting the binding under it")
        check("the row still shows the backend's answer", toggleFor(probe.usdc).checked, false)
    }

    function assertBackendMoved() {
        console.log("")
        console.log("the backend answers, the re-read lands, and the row follows it")
        check("the row is on", toggleFor(probe.usdc).checked, true)
        check("...and its balance arrived with it",
              find(view.item, "manageTokenBalance_" + probe.key(probe.usdc)).text, "12 USDC")
    }

    // ── provenance ────────────────────────────────────────────────────────────────
    function assertProvenance() {
        console.log("")
        console.log("each row says WHERE its contract address came from. A symbol is not")
        console.log("evidence — anyone may deploy a contract answering \"USDC\" — and enabling a")
        console.log("row is telling this wallet which contract that symbol means")
        check("the network coin says so", txt("manageTokenSource_native"), "Network coin")
        console.log("   `builtin` outranks `source`: a token compiled into this build is offered")
        console.log("   on every chain that has it, whichever public list also names it")
        check("a builtin is named as one, not by the list that also carries it",
              txt("manageTokenSource_" + probe.key(probe.weth)), "Built in")
        check("...one turned on here says that", txt("manageTokenSource_" + probe.key(probe.dai)),
              "Turned on here")
        console.log("   and the bundled snapshot is named as what it is: a public directory,")
        console.log("   not a table this wallet verified")
        check("a row offered by the bundled list says which list",
              txt("manageTokenSource_" + probe.key(probe.usdc)), "Uniswap list")
        check("...in the colour that marks it as not ours",
              String(find(view.item, "manageTokenSource_" + probe.key(probe.usdc)).color)
              !== String(find(view.item, "manageTokenSource_" + probe.key(probe.weth)).color), true)
        console.log("   never the word \"verified\": this view spends that on eth_rpc's")
        console.log("   proof-backed reads, and a token's provenance proves nothing about a balance")
        check("no row's provenance claims verification",
              [probe.weth, probe.dai, probe.usdc, "ETH"]
                  .filter(function (k) { return txt("manageTokenSource_" + probe.key(k))
                                                .toLowerCase().indexOf("verif") >= 0 }), [])
        check("and the screen says once why any of this is a question",
              vis("manageTokensProvenanceNote"), true)
    }

    // ── the cut ───────────────────────────────────────────────────────────────────
    function assertCut() {
        console.log("")
        console.log("`total` is what the query matched, `shown` is what came back. When they")
        console.log("differ the list in front of the user is a SLICE, and saying nothing is the")
        console.log("one thing this screen may not do")
        check("the cut is named, both figures", txt("manageTokensCountNote"),
              "Showing 50 of 318 matches — keep typing to narrow.")
        check("...and it is on screen", vis("manageTokensCountNote"), true)
        check("...while nothing calls a readable list broken",
              vis("manageTokensListNote"), false)
        check("...nor calls this chain empty", vis("manageTokensNoCatalogue"), false)
    }

    function assertNoCut() {
        console.log("")
        console.log("and it is silent when everything that matched came back")
        check("no cut, no line", vis("manageTokensCountNote"), false)
    }

    // ── the three empty states ────────────────────────────────────────────────────
    function assertEmptyChain() {
        console.log("")
        console.log("`listed: 0` with NO listError is the ordinary sepolia answer: a real,")
        console.log("complete reply. The bundled list is a snapshot of a mainnet directory, so")
        console.log("this chain offers only what is built in — and that is not a failure")
        check("the chain's empty list is explained", vis("manageTokensNoCatalogue"), true)
        check("...naming the cause rather than blaming the network",
              txt("manageTokensNoCatalogue").indexOf("mainnet") >= 0, true)
        check("...and nothing on screen calls it an error",
              vis("manageTokensListNote"), false)
        check("...the built-in row is still offered", rowOrder(), "ETH")
    }

    function assertListError() {
        console.log("")
        console.log("a listError is the OTHER answer, and the only one that is a failure. It")
        console.log("must not read like the empty chain above, which had the same `listed: 0`")
        check("the failure is stated", vis("manageTokensListNote"), true)
        check("...in the backend's own words", txt("manageTokensListNote"),
              "The token list could not be read: token_list: connection refused. "
              + "Only tokens already known to this wallet are listed.")
        check("...and NOT as the mainnet-snapshot explanation, which is a different answer",
              vis("manageTokensNoCatalogue"), false)
        check("...in the error colour, not the caption colour",
              String(find(view.item, "manageTokensListNote").color)
              === String(find(view.item, "manageTokensToggleError").color), true)
    }

    function assertListErrorWithNothingLeft() {
        console.log("")
        console.log("...and when it also left no rows, the centre says which of the three this")
        console.log("is: not \"nothing offered\", not \"nothing matched\"")
        check("the centre names the failure", txt("manageTokensEmpty"),
              "The token list could not be read")
        check("...with the reason still beside it", vis("manageTokensListNote"), true)
    }

    function assertNoMatch() {
        console.log("")
        console.log("a query that matched nothing on a chain whose list read fine is the third")
        console.log("answer, and says so about the QUERY")
        check("the centre is about the search", txt("manageTokensEmpty"),
              "No token matches that name or address")
        check("...not about the list being unreadable", vis("manageTokensListNote"), false)
        check("...nor about the chain having none", vis("manageTokensNoCatalogue"), false)
    }

    // ── in flight, and slow ───────────────────────────────────────────────────────
    function assertSearching() {
        console.log("")
        console.log("a call is running with rows already on screen. Those rows answer the")
        console.log("PREVIOUS query, which is worth saying rather than leaving them to look")
        console.log("like the answer to what is in the field now")
        check("the screen says a call is running", vis("manageTokensBusyNote"), true)
        check("...and what the rows under it are", txt("manageTokensBusyNote"),
              "Searching… the rows below still answer the previous query.")
        check("...with the header spinner up", vis("manageTokensSpinner"), true)
    }

    function assertSlow() {
        console.log("")
        console.log("and a search still running well past a keystroke is not a stuck screen —")
        console.log("the bundled list is large, and a spinner alone does not say so")
        check("the wait is explained rather than left to the spinner",
              txt("manageTokensBusyNote"),
              "Still searching the token list — it is large, and this can take a moment.")
    }

    function assertQuiet() {
        console.log("")
        console.log("...and both go when the call lands")
        check("no busy line", vis("manageTokensBusyNote"), false)
        check("no spinner", vis("manageTokensSpinner"), false)
    }

    // ── a refused write ───────────────────────────────────────────────────────────
    function assertRefusal() {
        console.log("")
        console.log("set_token_enabled REFUSES to disable a builtin, answers no event, and")
        console.log("changes no listing. The switch springs back to what the backend still")
        console.log("says, so the refusal is the only account of why it moved")
        check("the refusal is on the screen that asked for it",
              vis("manageTokensToggleError"), true)
        check("...in the backend's own words", txt("manageTokensToggleError"),
              "token: a built-in token cannot be disabled")
        check("...and the row is unmoved, as the backend still has it",
              toggleFor(probe.weth).checked, true)
    }

    function assertRefusalCleared() {
        console.log("   a new query is a new question, and the refusal belonged to the last one")
        check("the refusal is gone", vis("manageTokensToggleError"), false)
    }

    function assertOtherChainIsNotAnAnswer() {
        console.log("")
        console.log("a catalogue read under another network is not this network's answer,")
        console.log("whatever it holds: a token is enabled per chain")
        check("no row survives it", rowOrder(), "")
        check("...and the screen says it does not know rather than showing an empty catalogue",
              find(view.item, "manageTokensUnknown").visible, true)
        check("...which is not the same line as an empty one",
              find(view.item, "manageTokensEmpty").visible, false)
    }

    // ── the network moving under an open screen ───────────────────────────────────
    function assertQueryWentOut() {
        console.log("")
        console.log("what is typed goes out as a call, and the view remembers WHICH query the")
        console.log("rows in front of the user answer")
        check("the typed query was searched for", lastSearch(), "lit")
        check("...and the view holds it", view.item.tokenQuery, "lit")
    }

    function assertChainChangeReSearches() {
        console.log("")
        console.log("the chain can move without this screen doing anything — the backend adopts")
        console.log("the network it is really on. A token is offered PER CHAIN, so every row is")
        console.log("withheld the moment it does, and NOTHING else re-searches: the screen used")
        console.log("to sit on the em-dash forever, recovering only if the user typed")
        check("the rows are withheld, as they must be", rowOrder(), "")
        check("...and the screen is asked again, exactly once", searchesSince(), 1)
        check("...for the SAME query, not reset to the whole offered set", lastSearch(), "lit")
        check("...naming the network it is now asking about",
              find(view.item, "manageTokensNetwork").text, "Ethereum")
        check("...while it waits, saying it does not know",
              find(view.item, "manageTokensUnknown").visible, true)
    }

    function assertRowsReturn() {
        console.log("   ...and the answer to THAT call is what ends it. Without the call none")
        console.log("   ever comes: the em-dash below was permanent, and typing was the only")
        console.log("   way back")
        check("the rows are back", rowOrder(),
              ["ETH", probe.weth, probe.dai, probe.usdc].join(","))
        check("...with nothing still saying it does not know",
              find(view.item, "manageTokensUnknown").visible, false)
    }

    function assertClosedScreenIsNotSearched() {
        console.log("")
        console.log("...and a chain change with the screen CLOSED spends no call: re-opening it")
        console.log("reads the whole offered set anyway, and a wallet is at its busiest exactly")
        console.log("when the chain first arrives")
        // Proved closed before the negative is asserted: "no call went out" is true of a
        // screen that never opened, so without this the control passes on its own.
        //
        // The STACK's depth, not the item's absence: a pop runs a 400ms transition and this
        // probe ticks at 300ms, so the item is still in the scene for a moment after the screen
        // has been left. Depth moves on the pop itself.
        check("the screen really closed", find(view.item, "nav").depth, 1)
        check("no call went out", searchesSince(), 0)
    }

    // The reply, later than the assertion that follows the call. It answers for whatever
    // chain is active when it lands, which is what list_available_tokens does.
    Timer {
        id: answer
        interval: 400
        onTriggered: fake.availableTokensJson =
            probe.catalogue(JSON.parse(fake.activeNetworkJson).chainId)
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
            fake.availableTokensJson = probe.catalogue(probe.chain)
            // The route a USER has: the Settings tab, then the row. Driving openManageTokens()
            // instead once hid a route that pushed the screen and never read it.
            item.selectTab(4)
            find(view.item, "tokensEntry").clicked()
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
                probe.assertScreen()
                probe.assertRows()
                probe.assertProvenance()
                probe.assertLocked()
                probe.assertNoCut()
                probe.assertPressAsks()
                // What the backend's own re-read looks like when it lands.
                var t = JSON.parse(probe.catalogue(probe.chain))
                t.tokens[3].enabled = true
                fake.availableTokensJson = JSON.stringify(t)
                var b = JSON.parse(fake.balancesJson)
                b.push({ symbol: "USDC", address: probe.usdc, native: false,
                         display: "12", exact: "12", amountExact: "12" })
                fake.balancesJson = JSON.stringify(b)
            } else if (probe.phase === 2) {
                probe.assertBackendMoved()
                // A refused write. It answers nothing else: no event, no changed listing.
                fake.tokenToggleError = "token: a built-in token cannot be disabled"
            } else if (probe.phase === 3) {
                probe.assertRefusal()
                fake.tokenToggleError = ""
            } else if (probe.phase === 4) {
                probe.assertRefusalCleared()
                fake.availableTokensJson = probe.cutCatalogue(318, 50)
            } else if (probe.phase === 5) {
                probe.assertCut()
                fake.availableTokensJson = probe.emptyChainCatalogue()
            } else if (probe.phase === 6) {
                probe.assertEmptyChain()
                fake.availableTokensJson = probe.failedCatalogue(true)
            } else if (probe.phase === 7) {
                probe.assertListError()
                fake.availableTokensJson = probe.failedCatalogue(false)
            } else if (probe.phase === 8) {
                probe.assertListErrorWithNothingLeft()
                find(view.item, "tokenSearchField").text = "zzzz"
                fake.availableTokensJson = probe.noMatchCatalogue()
            } else if (probe.phase === 9) {
                probe.assertNoMatch()
                find(view.item, "tokenSearchField").text = ""
                fake.availableTokensJson = probe.catalogue(probe.chain)
                fake.availableTokensLoading = true
            } else if (probe.phase === 10) {
                probe.assertSearching()
                // The real wait is four seconds, which a probe cannot sit through. Shorten it
                // and re-enter the state, which is what restarts the timer.
                find(view.item, "manageTokensSlowTimer").interval = 60
                fake.availableTokensLoading = false
                fake.availableTokensLoading = true
            } else if (probe.phase === 11) {
                probe.assertSlow()
                fake.availableTokensLoading = false
            } else if (probe.phase === 12) {
                probe.assertQuiet()
                fake.availableTokensJson = probe.catalogue(1)
            } else if (probe.phase === 13) {
                probe.assertOtherChainIsNotAnAnswer()
                // Back to this chain's own answer, then a query worth keeping. The field goes
                // out through the real 250ms debounce, which this interval outlasts.
                fake.availableTokensJson = probe.catalogue(probe.chain)
                find(view.item, "tokenSearchField").text = "lit"
            } else if (probe.phase === 14) {
                probe.assertQueryWentOut()
                // The chain moves under the open screen. Not a click: the backend adopts the
                // network it is really on, and this view is told by the published scope.
                probe.searchesBefore = probe.searchCount()
                // From here the fake ANSWERS, so what comes back is a reply to a call the
                // view made rather than a listing this probe published for it.
                fake.answering = true
                fake.activeNetworkJson = JSON.stringify({ chainId: 1, name: "Ethereum",
                                                          nativeSymbol: "ETH", testnet: false })
            } else if (probe.phase === 15) {
                probe.assertChainChangeReSearches()
            } else if (probe.phase === 16) {
                probe.assertRowsReturn()
                // Leaving it is popping the SCREEN again, the way a token detail is left.
                view.item.back()
            } else {
                probe.searchesBefore = probe.searchCount()
                fake.activeNetworkJson = JSON.stringify({ chainId: probe.chain,
                                                          name: "Sepolia",
                                                          nativeSymbol: "ETH", testnet: true })
                probe.assertClosedScreenIsNotSearched()
                console.log("")
                console.log("RESULT: " + (probe.failures ? probe.failures + " FAILED"
                                                         : "ALL PASS"))
                Qt.exit(probe.failures ? 1 : 0)
            }
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/EthWalletView.qml")
}
