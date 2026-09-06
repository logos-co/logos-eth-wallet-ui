// The transaction screen, LOADED and DRIVEN, with no app and no backend.
//
// The C++ tables beside this file run every rule that is a pure function. What they cannot
// reach is the other half: whether a BINDING says what the rule decided. `qml_binding` in
// assert_ui.py reads that binding as text, and text cannot tell you that `txDetailMinedRow`
// renders an em-dash for a transaction the fetched detail is not about — only evaluating it can.
//
// So this stands the view up under an offscreen Qt with a fabricated backend, opens two
// transaction screens, and asserts what the rows SAY. Run it with doctests/run_view_probe.sh.
//
// The fabricated replies are the backend's own shapes, copied from its tests: an ERC-20 send
// whose recipient and target differ, with two decoded transfers and a half-failed fetch; and a
// plain pending ether send, which is the case that must stay quiet.
import QtQuick

Item {
    id: probe
    width: 1000
    height: 900

    readonly property string me: "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"
    readonly property string them: "0x0adBc7B2D1A2b7C8E9F0A1b2c3d4e5f60718D3A7"
    readonly property string weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    readonly property string stranger: "0x1234567890123456789012345678901234567890"
    readonly property string ercHash: "0x9a3c000000000000000000000000000000000000000000000000000000000001"
    readonly property string ethHash: "0x7b11000000000000000000000000000000000000000000000000000000000002"
    readonly property string doneHash: "0x5c22000000000000000000000000000000000000000000000000000000000003"
    readonly property string failedHash: "0x3e44000000000000000000000000000000000000000000000000000000000004"
    readonly property string freshHash: "0x2f88000000000000000000000000000000000000000000000000000000000005"
    // A real transfer(address,uint256) to `them` for the same amount: selector plus two
    // 32-byte words, which is the 68 bytes the Data row must count.
    readonly property string ercInput: "0xa9059cbb0000000000000000000000000adbc7b2d1a2b7c8e"
        + "9f0a1b2c3d4e5f60718d3a7000000000000000000000000000000000000000000000000000000e8d4a51000"

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

    // Searched from the CURRENT stack item, never from the root: a popped screen lingers
    // until Qt destroys it, and both transaction screens carry the same objectName.
    function screen() {
        var nav = find(view.item, "nav")
        return nav ? nav.currentItem : null
    }
    function row(name) {
        return find(screen(), name) || ({ value: "<missing>", text: "<missing>",
                                          copyValue: "<missing>", visible: "<missing>",
                                          enabled: "<missing>" })
    }

    property var rows: [{
        hash: probe.ercHash, chainId: 11155111, from: probe.me, to: probe.them,
        value: "1000000000000", kind: "erc20", token: probe.weth, status: "confirmed",
        timestamp: 1756600000, nonce: 26, gasLimit: 51000, gasUsed: "36442",
        gasUsedPercent: 71, effectiveGasPrice: "1500000001",
        effectiveGasPriceDisplay: "1.5", effectiveGasPriceExact: "1.500000001",
        maxPriorityFeePerGas: "1000000000", maxPriorityFeePerGasDisplay: "1",
        gasPriceUnit: "gwei", blockNumber: 25882523,
        feeWei: "54663000036442", feeWeiDisplay: "0.00005",
        feeWeiExact: "0.000054663000036442",
        feeCeilingWei: "102000000000000", feeCeilingWeiDisplay: "0.0001",
        feeCeilingWeiExact: "0.000102",
        valueSymbol: "WETH", valueDecimals: 18,
        valueDisplay: "<0.00001", valueExact: "0.000001",
        nativeSymbol: "ETH", stalled: false, unresolved: false, verificationBlocked: false,
        txTo: probe.weth, interactedWithDiffers: true, interactedWithSymbol: "WETH",
        transfersMore: 3,
        transfers: [
            { contract: probe.weth, from: probe.me, to: probe.them, amount: "1000000000000",
              known: true, mine: true, symbol: "WETH", decimals: 18,
              amountDisplay: "<0.00001", amountExact: "0.000001" },
            { contract: probe.stranger, from: probe.them, to: probe.me, amount: "42000000",
              known: false, mine: false }
        ]
    }, {
        // A plain ether send: recipient and target are the same address, so there is no second
        // fact to show, and nothing has settled, so there is nothing to fetch.
        hash: probe.ethHash, chainId: 11155111, from: probe.me, to: probe.them,
        value: "10000000000000000", kind: "native", status: "pending", timestamp: 1756600500,
        nonce: 27, gasLimit: 21000, maxFeePerGas: "2000000000",
        feeCeilingWei: "42000000000000", feeCeilingWeiDisplay: "0.00004",
        feeCeilingWeiExact: "0.000042",
        gasPriceUnit: "gwei", valueSymbol: "ETH", valueDecimals: 18,
        valueDisplay: "0.01", valueExact: "0.01", nativeSymbol: "ETH",
        stalled: false, unresolved: false, verificationBlocked: false
    }, {
        // A SETTLED ether send. It has a receipt, so it HAS a `txTo` — and that address is the
        // recipient itself. This is the row that proves the second address is gated on the two
        // DIFFERING rather than merely on a receipt having been read.
        hash: probe.doneHash, chainId: 11155111, from: probe.me, to: probe.them,
        value: "10000000000000000", kind: "native", status: "confirmed", timestamp: 1756601000,
        nonce: 28, gasLimit: 21000, gasUsed: "21000", gasUsedPercent: 100,
        effectiveGasPrice: "1000000000", effectiveGasPriceDisplay: "1",
        maxPriorityFeePerGas: "1000000000", maxPriorityFeePerGasDisplay: "1",
        gasPriceUnit: "gwei", blockNumber: 25882600,
        feeWei: "21000000000000", feeWeiDisplay: "0.00002", feeWeiExact: "0.000021",
        feeCeilingWei: "42000000000000", feeCeilingWeiDisplay: "0.00004",
        feeCeilingWeiExact: "0.000042",
        totalWei: "10021000000000000", totalWeiExact: "0.010021",
        valueSymbol: "ETH", valueDecimals: 18, valueDisplay: "0.01", valueExact: "0.01",
        nativeSymbol: "ETH", stalled: false, unresolved: false, verificationBlocked: false,
        txTo: probe.them, interactedWithDiffers: false
    }, {
        // A REVERTED send, carrying the measured fee pair from F-2: two different numbers
        // whose bounded strings are both "<0.00001". The screen exists to compare them.
        hash: probe.failedHash, chainId: 11155111, from: probe.me, to: probe.them,
        value: "10000000000000000", kind: "native", status: "failed", timestamp: 1756601500,
        nonce: 29, gasLimit: 21000, gasUsed: "21000", gasUsedPercent: 100,
        maxFeePerGas: "441114770",
        effectiveGasPrice: "285833650", effectiveGasPriceDisplay: "0.28583",
        effectiveGasPriceExact: "0.28583365",
        maxPriorityFeePerGas: "1000000000", maxPriorityFeePerGasDisplay: "1",
        maxPriorityFeePerGasExact: "1",
        gasPriceUnit: "gwei", blockNumber: 25882700,
        feeWei: "6002506650000", feeWeiDisplay: "<0.00001", feeWeiExact: "0.00000600250665",
        feeCeilingWei: "9263410170000", feeCeilingWeiDisplay: "<0.00001",
        feeCeilingWeiExact: "0.00000926341017",
        valueSymbol: "ETH", valueDecimals: 18, valueDisplay: "0.01", valueExact: "0.01",
        nativeSymbol: "ETH", stalled: false, unresolved: false, verificationBlocked: false,
        txTo: probe.them, interactedWithDiffers: false
    }, {
        // An ERC-20 send whose receipt has NOT landed: no `txTo`, no decoded transfers. The
        // raw card carries the contract and the calldata; the recipient the user typed exists
        // only in this wallet's own record, and would otherwise be nowhere on the screen.
        // A day later than the four above, which is also the list's only day break.
        hash: probe.freshHash, chainId: 11155111, from: probe.me, to: probe.them,
        value: "1000000000000", kind: "erc20", token: probe.weth, status: "pending",
        timestamp: 1756690000, nonce: 30, gasLimit: 51000,
        feeCeilingWei: "102000000000000", feeCeilingWeiDisplay: "0.0001",
        feeCeilingWeiExact: "0.000102",
        gasPriceUnit: "gwei", valueSymbol: "WETH", valueDecimals: 18,
        valueDisplay: "<0.00001", valueExact: "0.000001", nativeSymbol: "ETH",
        stalled: false, unresolved: false, verificationBlocked: false,
        txInput: probe.ercInput
    }]

    // A HALF answer, which is the normal case: the block landed and the transaction leg did
    // not. It names the ERC-20 transaction, and only that one may render it.
    property string detailsJson: JSON.stringify({
        ok: true, hash: probe.ercHash, chainId: 11155111, route: "direct",
        gasPriceUnit: "gwei", block: { number: 25882523, timestamp: 1756600005 },
        transactionError: "the node does not have this transaction"
    })

    property var fake: ({})
    property var logos: ({ module: function (n) { return probe.fake }, isViewModuleReady: function (n) { return true } })

    Component.onCompleted: {
        probe.fake = {
            activeNetworkJson: JSON.stringify({ chainId: 11155111, name: "Sepolia",
                                                nativeSymbol: "ETH", testnet: true }),
            networksJson: "[]", accountsJson: JSON.stringify([probe.me]),
            accountLabelsJson: "{}", feeTiersJson: "{}",
            verifiedProxyJson: JSON.stringify({ ok: true, chainId: 11155111, mode: "off" }),
            scopedDataFresh: true, dataLoading: false, quoteLoading: false,
            balancesJson: JSON.stringify([{ symbol: "ETH", display: "1.5", exact: "1.5" }]),
            balancesRoute: "direct",
            tokensJson: JSON.stringify([{ symbol: "ETH", name: "Ether", decimals: 18,
                                          native: true }]),
            historyJson: JSON.stringify(probe.rows), blockedChainsJson: "[]",
            availableTokensJson: "", availableTokensLoading: false, tokenToggleBusy: false,
            tokenToggleError: "",
            sweepingReceipts: false, quoteJson: "{}", quoteRequestJson: "", quoteStale: false,
            txDetailsJson: probe.detailsJson, txDetailsLoading: false, txStatusLoading: false,
            pendingRequestId: "", lastError: "", sendError: "", selectedAccount: probe.me,
            refreshTxStatus: function (h) {}, fetchTxDetails: function (h) {}
        }
        view.source = Qt.resolvedUrl("../src/qml/EthWalletView.qml")
    }

    function assertErc20Screen() {
        console.log("an ERC-20 send. The top card carries RAW transaction fields only: the")
        console.log("transaction's own `to` is the CONTRACT, and there is no recipient field")
        console.log("on it to show — the recipient is interpretation and lives further down")
        check("no To row: the transaction has no such field",
              row("txDetailToRow").visible, false)
        check("Interacted with names the contract", row("txDetailInteractedRow").value,
              "WETH · 0xC02a…6Cc2")
        check("...and is shown", row("txDetailInteractedRow").visible, true)
        check("...and copies the WHOLE address", row("txDetailInteractedRow").copyValue,
              probe.weth)
        console.log("   the calldata is raw evidence and belongs on that card. This row was")
        console.log("   recorded before it was stored, and the fetch returned no transaction")
        console.log("   leg, so it is UNKNOWN — an em-dash, and no byte count claimed")
        check("the data row is on the card", row("txDetailDataRow").visible, true)
        check("...saying it does not know", row("txDetailDataValue").text, "—")
        check("...with no count it cannot support", row("txDetailDataLabel").text, "Data")
        check("...and nothing to copy", row("txDetailDataCopy").visible, false)

        console.log("the gas figures, all of them free: stored at broadcast and from the receipt")
        check("gas used against the approved limit", row("txDetailGasUsedRow").value,
              "36442 of 51000 (71%)")
        check("gas price in gwei, never in ether", row("txDetailGasPriceRow").value, "1.5 gwei")
        check("the tip, from the row itself", row("txDetailPriorityRow").value, "1 gwei")
        check("the ceiling beside the fee that was PAID", row("txDetailCeilingRow").value,
              "0.0001 ETH")
        check("...and it is shown, because this row settled",
              row("txDetailCeilingRow").visible, true)

        console.log("the Transfer logs, decoded off the receipt: a fact, not a lookup")
        check("the section is shown", row("txDetailTransfersCard").visible, true)
        check("our own transfer sorts first and is in the token's units",
              row("txDetailTransferAmount_0").value, "<0.00001 WETH")
        check("...and its label says it left this account",
              row("txDetailTransferAmount_0").label, "Sent")
        check("...and it copies EVERY digit, not the bounded string",
              row("txDetailTransferAmount_0").copyValue, "0.000001")
        check("a token we do not list shows the RAW integer, labelled",
              row("txDetailTransferAmount_1").value, "42000000 base units")
        check("...and copies that integer, which is already exact",
              row("txDetailTransferAmount_1").copyValue, "42000000")
        check("...with a note naming the contract",
              row("txDetailUnknownToken_1").visible, true)
        check("...and no such note on the one we do know",
              row("txDetailUnknownToken_0").visible, false)
        console.log("   the receipt landed and decoded a transfer, so the recorded-recipient")
        console.log("   card below is GONE — these rows are the only place the recipient is")
        console.log("   still rendered, and every address on this screen is copyable")
        check("the recorded card is not on a settled send",
              row("txDetailRecordedCard").visible, false)
        check("the recipient is a row of its own", row("txDetailTransferTo_0").value,
              "0x0adB…D3A7")
        check("...copyable in full, not a truncated label",
              row("txDetailTransferTo_0Copy").value, probe.them)
        check("...and that button is really on screen, not merely declared",
              row("txDetailTransferTo_0Copy").visible, true)
        check("the sender beside it is copyable too",
              row("txDetailTransferFrom_0Copy").value, probe.me)
        check("...and so are the second transfer's, which is not ours",
              row("txDetailTransferFrom_1Copy").value, probe.them)
        check("...both ends of it", row("txDetailTransferTo_1Copy").value, probe.me)
        check("what the cap dropped is counted", row("txDetailTransfersMore").text,
              "+3 more transfers in this transaction")

        console.log("the fetch: a HALF answer is an answer, and the leg that failed says so")
        check("the mined time landed", row("txDetailMinedRow").value !== "—", true)
        console.log("   F-5: at minute resolution these two rows printed the SAME string, and")
        console.log("   the block time is the only thing this fetch returns for this row")
        check("...and it is not the broadcast string over again",
              row("txDetailMinedRow").value !== row("txDetailBroadcastRow").value, true)
        check("...and it says how long the transaction waited",
              String(row("txDetailMinedRow").value).indexOf("(5s after broadcast)") >= 0, true)
        check("...both rows to the second, so a user can check the difference themselves",
              String(row("txDetailBroadcastRow").value).length, 19)

        console.log("   F-2: a bounded row and an exact copy value, which is the design's own")
        console.log("   rule and was honoured only by the transfer rows")
        check("the gas price row stays bounded", row("txDetailGasPriceRow").value, "1.5 gwei")
        check("...and its copy button carries every digit",
              row("txDetailGasPriceRowCopy").value, "1.500000001")
        check("...and that button is really on screen, not merely declared",
              row("txDetailGasPriceRowCopy").visible, true)
        check("the fee row copies its exact figure too",
              row("txDetailFeeRowCopy").value, "0.000054663000036442")
        check("the ceiling row too", row("txDetailCeilingRowCopy").value, "0.000102")
        check("the failed leg is worded by the backend, beside the rows it is about",
              row("txDetailFetchError").text, "the node does not have this transaction")
        check("...and the button offers the retry", row("txDetailFetchButton").text,
              "Try again")
        check("...and is armed, because something is still missing",
              row("txDetailFetchButton").enabled, true)
    }

    function assertSettledNativeScreen() {
        console.log("")
        console.log("a SETTLED ether send: it has a receipt, so it HAS the transaction's own")
        console.log("`to` — and that address IS the recipient. Still no second row")
        check("no contract row: this transaction called nobody",
              row("txDetailInteractedRow").visible, false)
        check("...and the To row renders the transaction's OWN `to`, which the receipt carried",
              row("txDetailToRow").value, "0x0adB…D3A7")
        check("...and no calldata row either", row("txDetailDataRow").visible, false)
        check("no tokens moved but ether, and we do not say \"none\"",
              row("txDetailTransfersCard").visible, false)
        check("...and nothing is recorded in their place: this is not an erc20 send",
              row("txDetailRecordedCard").visible, false)
        check("the fee that was paid", row("txDetailFeeRow").value, "0.00002 ETH")
        check("...beside the ceiling it was quoted at", row("txDetailCeilingRow").value,
              "0.00004 ETH")
        check("every unit of the limit was burnt", row("txDetailGasUsedRow").value,
              "21000 of 21000 (100%)")
        check("the total, exact, native sends only", row("txDetailTotalRow").visible, true)
    }

    function assertFailedScreen() {
        console.log("")
        console.log("a REVERTED send. The fee left the account and the amount did not, and the")
        console.log("two fee figures are different numbers whose bounded strings are the same")
        check("the status says so", row("txDetailStatus").text, "failed")
        check("...and a note names the number that actually moved",
              row("txDetailFailedNote").visible, true)
        console.log("   F-3: total_wei used to be value + fee REGARDLESS of status, so this")
        console.log("   screen labelled money that never moved \"Total amount\"")
        check("no total on a failure", row("txDetailTotalRow").visible, false)

        console.log("   F-2: both bounded strings are \"<0.00001\", so the ceiling row was a")
        console.log("   verbatim duplicate of the fee row above it — 35% of headroom, invisible")
        check("the fee prints every digit instead", row("txDetailFeeRow").value,
              "0.00000600250665 ETH")
        check("...and the ceiling prints its own", row("txDetailCeilingRow").value,
              "0.00000926341017 ETH")
        check("...so the two rows differ, which is the only reason to show both",
              row("txDetailFeeRow").value !== row("txDetailCeilingRow").value, true)
        check("and each copies its exact figure", row("txDetailFeeRowCopy").value,
              "0.00000600250665")
        check("...the ceiling too", row("txDetailCeilingRowCopy").value, "0.00000926341017")
    }

    function assertNativeScreen() {
        console.log("")
        console.log("a plain ether send: the common case, and it must not get NOISIER")
        check("no second address, because there is no second fact",
              row("txDetailInteractedRow").visible, false)
        check("...and the To row stands in for it, off `to` while `txTo` is unread",
              row("txDetailToRow").value, "0x0adB…D3A7")
        check("no calldata row: there is no calldata", row("txDetailDataRow").visible, false)
        check("no tokens-transferred section", row("txDetailTransfersCard").visible, false)

        console.log("   THE DEFECT THIS SCREEN MUST NOT HAVE: the fetched detail names the")
        console.log("   OTHER transaction, so not one of its figures may appear here")
        check("mined is unknown, not the other transaction's time",
              row("txDetailMinedRow").value, "—")
        check("...and no error from the other transaction's fetch either",
              row("txDetailFetchError").visible, false)

        console.log("   and nothing is claimed about a transaction that has not settled")
        check("gas used is unknown", row("txDetailGasUsedRow").value, "—")
        check("gas price is unknown", row("txDetailGasPriceRow").value, "—")
        check("the tip is unknown", row("txDetailPriorityRow").value, "—")
        check("the ceiling row is hidden: the fee row already IS the ceiling",
              row("txDetailCeilingRow").visible, false)
        check("the fee row says so in words", row("txDetailFeeRow").value,
              "up to 0.00004 ETH")
        check("the fetch is disabled: there is no block to read",
              row("txDetailFetchButton").enabled, false)
        check("...and says why", row("txDetailFetchNote").visible, true)
    }

    // F-6. Enforced in the backend — `receipt::checksummed`, at decode AND at read, so a row
    // already on disk is normalised too. What is checked here is the consequence on screen:
    // one address, one string, however many places it reaches the view from.
    function assertOneCasing() {
        console.log("")
        console.log("F-6: the sender appears twice on the ERC-20 screen — the From row, off a")
        console.log("parsed Address, and the transfer's own From row, off a raw LOG TOPIC.")
        console.log("Those two arrive in different casings and used to be rendered in both")
        var from = String(row("txDetailFromRow").value)
        check("the From row is EIP-55", from, "0x8626…1199")
        check("...and the log-topic row spells the same address the same way",
              row("txDetailTransferFrom_0").value, from)
        check("...and the two copy buttons hand over one string",
              row("txDetailTransferFrom_0Copy").value, row("txDetailFromRowCopy").value)
        console.log("   `txTo` reaches us in the node's own lowercase too, and the card now")
        console.log("   renders it directly rather than the recipient beside it")
        check("the contract row is EIP-55", row("txDetailInteractedRow").value,
              "WETH · 0xC02a…6Cc2")
        check("...and its copy button hands over the whole of it",
              row("txDetailInteractedRowCopy").value, probe.weth)
    }

    function assertFreshErc20Screen() {
        console.log("")
        console.log("an ERC-20 send whose receipt has NOT landed. With \"To\" gone from the raw")
        console.log("card and nothing decoded off a receipt, the address the user typed would")
        console.log("be NOWHERE — so it is recorded below, in the interpreted section, said to")
        console.log("be this wallet's own record rather than anything read off the chain")
        check("no To row", row("txDetailToRow").visible, false)
        // Bare, not "WETH · …": the backend names `txTo` and only `txTo`, so a row standing
        // on `token` has no name to wear and the view does not invent one for it.
        check("the card names the contract, off `token` while `txTo` is unread",
              row("txDetailInteractedRow").value, "0xC02a…6Cc2")
        check("...and copies the whole of it",
              row("txDetailInteractedRowCopy").value, probe.weth)
        check("nothing was decoded", row("txDetailTransfersCard").visible, false)
        check("so the recipient is recorded instead", row("txDetailRecordedCard").visible, true)
        check("...as the address this wallet was asked to pay",
              row("txDetailRecordedToRow").value, "0x0adB…D3A7")
        check("...copyable in full", row("txDetailRecordedToRowCopy").value, probe.them)
        check("...and labelled as our record, not the chain's",
              String(row("txDetailRecordedNote").text).indexOf("receipt has not been read") >= 0,
              true)
        console.log("   the calldata this row DOES carry, wrapped rather than elided, and")
        console.log("   counted: 68 bytes is a selector and two 32-byte words")
        check("the data row is shown", row("txDetailDataRow").visible, true)
        check("...counting the bytes", row("txDetailDataLabel").text, "Data · 68 bytes")
        check("...showing all of them", row("txDetailDataValue").text, probe.ercInput)
        check("...wrapping rather than eliding", row("txDetailDataValue").wrapMode,
              TextEdit.WrapAnywhere)
        check("...and copyable whole", row("txDetailDataCopy").value, probe.ercInput)
    }

    // The Activity list the screens above were opened from. Five rows over two days, so the
    // heading the delegate computes against its neighbour must appear exactly twice.
    function assertActivityHeadings() {
        console.log("")
        console.log("the activity list groups by day, MetaMask-style. The model is a plain JS")
        console.log("array, which ListView's section.property cannot read, so the break is")
        console.log("decided in the delegate against the row above it")
        var list = find(view.item, "historyList")
        check("the list is on screen with every row", list ? list.count : 0, probe.rows.length)
        var shown = [], heights = ({}), hits = ({})
        for (var i = 0; i < probe.rows.length; ++i) {
            var h = probe.rows[i].hash
            var head = find(view.item, "txDay_" + h)
            var r = find(view.item, "txRow_" + h)
            var hit = find(view.item, "txRowHit_" + h)
            if (head && head.visible)
                shown.push(h)
            if (r)
                heights[h] = r.implicitHeight
            if (hit)
                hits[h] = hit.implicitHeight
        }
        check("two days, two headings", shown.length, 2)
        check("...one opening the first day", shown[0], probe.ercHash)
        check("...one opening the second", shown[1], probe.freshHash)
        check("a dated row is never bucketed as unknown",
              find(view.item, "txDay_" + probe.ercHash).text,
              Qt.formatDate(new Date(probe.rows[0].timestamp * 1000), "MMM d, yyyy"))
        console.log("   the heading rides in the row's own container, so the row that carries")
        console.log("   one is TALLER — a heading outside that derivation is an overlap")
        check("the heading row is taller than its identically-shaped neighbour",
              heights[probe.ercHash] > heights[probe.ethHash], true)
        console.log("   ...while the part that HOVERS is the same shape either way. The heading")
        console.log("   used to be anchored INSIDE the delegate, whose hover and press")
        console.log("   background covered it too: pointing at \"Yesterday\" lit up the")
        console.log("   transaction beneath it as one block")
        check("the hoverable row is the same height with a heading above it as without",
              hits[probe.ercHash], hits[probe.ethHash])
        var hit0 = find(view.item, "txRowHit_" + probe.ercHash)
        check("...and the heading is nowhere inside the item that hovers",
              hit0 ? find(hit0, "txDay_" + probe.ercHash) : "<no hoverable row>", null)
        check("...it is a sibling, under the row's own container",
              find(find(view.item, "txRow_" + probe.ercHash),
                   "txDay_" + probe.ercHash) !== null, true)
        console.log("   and it cannot open a transaction either: a Text has no click and no")
        console.log("   hover surface of its own")
        var head0 = find(view.item, "txDay_" + probe.ercHash)
        check("the heading has no click", typeof head0.clicked, "undefined")
        check("...and no hover surface", head0.hoverEnabled, undefined)
        check("and each row carries its own time",
              find(view.item, "txTime_" + probe.ethHash).text,
              Qt.formatDateTime(new Date(probe.rows[1].timestamp * 1000), "HH:mm"))
    }

    // A heading that dated itself off `new Date()` had no binding dependency at all, and the
    // history behind it is published through change-guarded setters — so on an idle wallet it
    // stayed "Today" past local midnight for good. The only way to see that from here is to
    // MOVE the day under a model that does not change, and watch the heading follow.
    function assertHeadingsAge() {
        console.log("")
        console.log("the headings read a ticker on the root, not the wall clock. Nothing below")
        console.log("touches the model: the same five rows are on screen throughout")
        var head = find(view.item, "txDay_" + probe.ercHash)
        var key = Qt.formatDate(new Date(probe.rows[0].timestamp * 1000), "yyyy-MM-dd")
        var dated = Qt.formatDate(new Date(probe.rows[0].timestamp * 1000), "MMM d, yyyy")
        var ticker = find(view.item, "dayKeyTicker")
        check("a timer moves the keys", ticker ? ticker.running && ticker.repeat : false, true)
        check("...no faster than a heading needs", ticker ? ticker.interval : 0, 60000)
        view.item.todayKey = key
        check("the row's own day, held as today, reads Today", head.text, "Today")
        view.item.todayKey = "9999-12-31"
        view.item.yesterdayKey = key
        check("...and one day on, the SAME row reads Yesterday", head.text, "Yesterday")
        view.item.yesterdayKey = "9999-12-30"
        check("...and past that it wears its date again", head.text, dated)
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
            item.openTxDetail(probe.ercHash)
            probe.assertErc20Screen()
            probe.assertOneCasing()
            // openTxDetail pops to the root itself, immediately, before it pushes.
            item.openTxDetail(probe.doneHash)
            probe.assertSettledNativeScreen()
            item.openTxDetail(probe.failedHash)
            probe.assertFailedScreen()
            item.openTxDetail(probe.ethHash)
            probe.assertNativeScreen()
            item.openTxDetail(probe.freshHash)
            probe.assertFreshErc20Screen()
            // The list itself, which needs a layout pass the handler it is asserted from
            // cannot wait for: its delegates do not exist until the view has laid out.
            item.selectTab(1)
            settle.start()
        }
    }

    Timer {
        id: settle
        interval: 400
        onTriggered: {
            probe.assertActivityHeadings()
            probe.assertHeadingsAge()
            console.log("")
            console.log("RESULT: " + (probe.failures ? probe.failures + " FAILED" : "ALL PASS"))
            Qt.exit(probe.failures ? 1 : 0)
        }
    }
}
