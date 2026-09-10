// The Receive screen: what is encoded, and what is drawn.
//
// The QR is encoded in the VIEW, in JavaScript, and drawn as plain Rectangles — the sandbox
// this plugin runs in refuses `data:` URIs and remote URLs, and a Canvas never receives
// paint() inside its QQuickWidget. doctests/qr_table.mjs runs the encoder against the spec;
// what only a loaded view can answer is everything between the encoder and the screen: that
// the page opens, that the matrix reaches the Rectangles, that the geometry lands on whole
// pixels, and that the text underneath is the WHOLE address rather than the elided form the
// header carries.
//
// The last of those is the one a user pays for. A code is unreadable to a human, so the line
// beneath it is the only way to check it against what they were given — and an elided address
// cannot be checked against anything.
import QtQuick

Item {
    id: probe
    width: 900
    height: 700

    readonly property string me: "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"
    readonly property string other: "0x0adBc7B2D1A2b7C8E9F0A1b2c3d4e5f60718D3A7"

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

    property var logos: ({ module: function (n) { return fake }, isViewModuleReady: function (n) { return true } })

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
        property string accountsJson: JSON.stringify([probe.me, probe.other])
        property string selectedAccount: probe.me
        property string accountLabelsJson: "{}"
        property string accountWalletsJson: "{}"
        property string balancesJson: JSON.stringify([{ symbol: "ETH", display: "1.5",
                                                        exact: "1.5", native: true }])
        property string balancesRoute: "direct"
        property string tokensJson: JSON.stringify([{ symbol: "ETH", name: "Ether",
                                                      decimals: 18, native: true }])
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
        property string pendingRequestId: ""
        property string pendingApprovalHandle: ""
        property string lastSendOutcomeJson: ""

        property string contactsJson: "[]"
        property string contactsError: ""

        function saveContact(address, name) {}
        function forgetContact(address) {}
        function quote(r) {}
        function setQuoteAutoRefresh(on) {}
        function submitSend(r) {}
        function cancelSend() {}
        function selectAccount(a) {}
        function chooseTokenSort(o) {}
    }

    // A pushed screen, not a popup: its items really are instantiated, so the code can be
    // measured rather than read off a binding that nothing evaluated.
    function screen() {
        var nav = find(view.item, "nav")
        return nav ? nav.currentItem : null
    }
    function onScreen(name) {
        return find(screen(), name) || ({ text: "<missing>", visible: "<missing>" })
    }

    // ── getting there ────────────────────────────────────────────────────────

    function assertReceiveIsAnActionOnTheAccountInHand() {
        console.log("")
        console.log("Receive sits beside Send, not among Address book / Networks / Tokens:")
        console.log("those three open places you configure something in, and this one does a")
        console.log("thing with the account already selected. So it is armed by that account")
        console.log("and by nothing else")
        var btn = find(view.item, "openReceiveButton")
        check("the button is there", btn !== null, true)
        check("...and armed, an account being selected", btn.enabled, true)

        fake.selectedAccount = ""
        check("no account, nothing to receive to", btn.enabled, false)
        fake.selectedAccount = probe.me
        check("...and armed again once there is one", btn.enabled, true)

        console.log("")
        console.log("and it pushes a screen, which is what makes the code measurable at all —")
        console.log("a popup instantiates no delegates in a harness with no overlay")
        btn.clicked()
        check("the page is open", onScreen("receivePage").visible, true)
        check("...with a way back", onScreen("receiveBack").visible, true)
    }

    // ── what is encoded ──────────────────────────────────────────────────────

    function assertTheBareChecksummedAddressIsWhatIsEncoded() {
        console.log("")
        console.log("what is encoded is the BARE EIP-55 address: not an EIP-681 URI, whose")
        console.log("amount a scanning wallet may ignore while showing none, and never")
        console.log("uppercased, because the mixed case IS the checksum")
        var page = onScreen("receivePage")
        check("the payload is the address itself", page.payload, probe.me)
        check("...with no scheme in front of it", page.payload.indexOf(":") < 0, true)
        check("...and the case it was given", page.payload === probe.me.toUpperCase(), false)

        console.log("")
        console.log("and it follows the selection: a code left over from the previous account")
        console.log("is a code that pays somebody else")
        fake.selectedAccount = probe.other
        check("the payload moved", onScreen("receivePage").payload, probe.other)
        var moved = onScreen("receiveQrBox").qr.bits
        fake.selectedAccount = probe.me
        check("...and the matrix with it", onScreen("receiveQrBox").qr.bits === moved, false)
    }

    // ── what is drawn ────────────────────────────────────────────────────────

    function assertTheMatrixReachesTheRectangles() {
        console.log("")
        console.log("the code is drawn as plain Rectangles, one per RUN of dark modules. What")
        console.log("no source assertion can see is whether the runs are the matrix: a run")
        console.log("list that is empty, or that covers the wrong modules, draws a picture")
        console.log("that is not this address")
        var box = onScreen("receiveQrBox")
        check("the box is visible", box.visible, true)
        check("...over a version-3 matrix", box.qr.size, 29)

        var runs = view.item.qrRuns(box.qr)
        check("there are runs to draw", runs.length > 0, true)

        var dark = 0
        for (var i = 0; i < box.qr.bits.length; ++i)
            if (box.qr.bits.charAt(i) === "1")
                dark++
        var covered = 0, inBounds = true
        for (var j = 0; j < runs.length; ++j) {
            covered += runs[j][2]
            if (runs[j][0] < 0 || runs[j][1] < 0 || runs[j][1] >= box.qr.size
                    || runs[j][0] + runs[j][2] > box.qr.size)
                inBounds = false
        }
        check("the runs cover every dark module and no other", covered, dark)
        check("...and none of them leaves the matrix", inBounds, true)
        // A per-module fallback draws exactly `dark` Rectangles, and the runs collapse
        // every solid row into one.
        check("...in fewer Items than one per dark module", runs.length < dark, true)

        console.log("")
        console.log("a run is [startX, y, length], so a run of length 0 would be an invisible")
        console.log("Rectangle standing in for a dark module that never gets drawn")
        var zero = runs.filter(function (r) { return r[2] < 1 })
        check("no empty runs", zero.length, 0)

        console.log("")
        console.log("and finally the Rectangles THEMSELVES — everything above is arithmetic on")
        console.log("a returned array, which stays true even if the Repeater draws nothing, or")
        console.log("draws the code in the ground colour, or transposes it")
        var drawn = []
        for (var c = 0; c < box.children.length; ++c)
            if (box.children[c].color !== undefined && box.children[c] !== box)
                drawn.push(box.children[c])
        check("one Rectangle per run reached the scene", drawn.length, runs.length)

        var cell = box.cell, quiet = box.quiet
        var placed = 0, dark_drawn = 0
        for (var d = 0; d < drawn.length; ++d) {
            var it = drawn[d]
            for (var r2 = 0; r2 < runs.length; ++r2) {
                if (it.x === (runs[r2][0] + quiet) * cell && it.y === (runs[r2][1] + quiet) * cell
                        && it.width === runs[r2][2] * cell && it.height === cell) { placed++; break }
            }
            if (String(it.color) === "#000000") dark_drawn++
        }
        check("...each at its run's place and size", placed, runs.length)
        check("...and each drawn dark, not in the ground colour", dark_drawn, runs.length)
    }

    function assertTheGeometryLandsOnWholePixels() {
        console.log("")
        console.log("the cell is FLOORED and the box then takes the size that falls out. A")
        console.log("fractional cell leaves hairline seams between the rectangles, and a")
        console.log("scanner reads some of those as module boundaries — so the box is not a")
        console.log("fixed 240 with the modules rounded inside it")
        var box = onScreen("receiveQrBox")
        check("the quiet zone is the spec's four modules", box.quiet, 4)
        check("the cell is a whole number of pixels", box.cell, Math.floor(box.cell))
        check("...and as large as 240 allows", box.cell,
              Math.floor(240 / (box.qr.size + 2 * box.quiet)))
        var modulesWide = box.qr.size + 2 * box.quiet
        check("the box is the modules plus the quiet zone, exactly", box.width,
              box.cell * modulesWide)
        check("...and square", box.height, box.width)
        check("...so it divides into whole cells", box.width % box.cell, 0)
        check("which is NOT a fixed 240", box.width === 240, false)

        console.log("")
        console.log("and the two colours are literals. A palette colour inverts in dark mode,")
        console.log("and an inverted code does not scan")
        check("the ground is white", String(box.color), "#ffffff")
    }

    // ── the line underneath ──────────────────────────────────────────────────

    function assertTheAddressIsWholeAndSeparatelyCopyable() {
        console.log("")
        console.log("the address is printed WHOLE. The header's copy is elided, and an elided")
        console.log("address cannot be checked against the one a user was given — which is the")
        console.log("only check available against a picture nobody can read")
        var line = onScreen("receiveAddress")
        check("the whole address", line.text, probe.me)
        check("...not the elided form", line.text.indexOf("…") < 0, true)
        check("...wrapped rather than clipped", line.wrapMode, TextEdit.WrapAnywhere)

        console.log("")
        console.log("and the copy button carries its OWN name. Two controls under one")
        console.log("objectName is a harness reaching whichever came first, and the header's")
        console.log("button is on screen at the same time as this one")
        var copy = onScreen("receiveAddressCopyButton")
        check("it is there", copy.visible, true)
        check("...offering the whole address, not the elided one", copy.value, probe.me)
        check("...and the header's button is a different object",
              copy === find(view.item, "addressCopyButton"), false)
        check("...which is still on screen while this page is open",
              find(view.item, "addressCopyButton") !== null, true)
    }

    // ── the state with nothing to encode ─────────────────────────────────────

    function assertAnEmptySelectionHidesTheCodeRatherThanThrowing() {
        console.log("")
        console.log("an empty selection reaches this screen — the account list can empty under")
        console.log("it. The encoder is called from a BINDING, so an exception there does not")
        console.log("blank the code, it takes the whole view down with it")
        fake.selectedAccount = ""
        var page = onScreen("receivePage")
        check("the page is still standing", page.visible, true)
        check("...with nothing encoded", page.qr, null)
        check("...so no code is drawn", onScreen("receiveQrBox").visible, false)
        check("...and no empty address line either", onScreen("receiveAddress").visible, false)
        check("...nor a copy button offering an empty string",
              onScreen("receiveAddressCopyButton").visible, false)

        console.log("")
        console.log("and it says so, rather than showing a blank rectangle that reads as a")
        console.log("code which failed to load")
        check("the screen accounts for itself", onScreen("receiveUnavailable").visible, true)

        console.log("")
        console.log("...and comes back when an account does. The page is not rebuilt, so a")
        console.log("code that only ever draws on first open would pass every check above")
        fake.selectedAccount = probe.me
        check("the code is back", onScreen("receiveQrBox").visible, true)
        check("...for the account now selected", onScreen("receivePage").payload, probe.me)
        check("...and the note stood down", onScreen("receiveUnavailable").visible, false)
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

            probe.assertReceiveIsAnActionOnTheAccountInHand()
            probe.assertTheBareChecksummedAddressIsWhatIsEncoded()
            probe.assertTheMatrixReachesTheRectangles()
            probe.assertTheGeometryLandsOnWholePixels()
            probe.assertTheAddressIsWholeAndSeparatelyCopyable()
            probe.assertAnEmptySelectionHidesTheCodeRatherThanThrowing()

            console.log("")
            console.log(probe.failures ? "RESULT: FAILURES" : "RESULT: ALL PASS")
            Qt.exit(probe.failures ? 1 : 0)
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/EthWalletView.qml")
}
