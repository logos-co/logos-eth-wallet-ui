import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Icons
import Logos.Theme
import "kit" as Kit
import "qrcodegen.js" as QrGen

// The Ethereum wallet.
//
// Information design follows MetaMask: one question per screen, everything else behind a
// disclosure. Five sections, no action button above the tab strip, and both the portfolio
// scope and Send's selected network stay explicit — a user must never be able to mistake
// which chains they are reading or which chain they are spending on.
//
// This view holds no secret. It requests signatures and reads which accounts exist; the vault
// password is taken only by evm_signer_ui, and seed phrases only ever reach evm_keystore_ui.
//
// Rendering rule: every item showing a string this view did not author sets
// `textFormat: Text.PlainText`. LogosText is a bare Text with no textFormat, i.e. Qt's AutoText
// HTML autodetection — an account label or an error message containing markup would otherwise
// render as markup. LogosSelectableText already defaults to PlainText.
Item {
    id: root
    // Addressable by the headless harness, which drives tabs through selectTab() below —
    // qt-mcp cannot click a LogosTabButton, and StackLayout exposes no invokable setter.
    objectName: "ethWalletRoot"
    anchors.fill: parent

    // Paint the surface. Without this the QQuickWidget's white clear colour shows through and
    // LogosText's default (light) colour renders white-on-white.
    Rectangle { anchors.fill: parent; color: Theme.palette.background }

    readonly property var backend: logos.module("eth_wallet_ui")

    // Must be a writable property fed by the signal, NOT a binding: a binding containing a
    // function call evaluates once at creation, before ui-host has finished handing over, and
    // then latches false forever.
    property bool ready: false

    // What the last copy button put on the clipboard. `recentlyCopied` self-clears after
    // 1.5s and never names the value, so a test cannot assert on it without racing.
    property string lastCopiedValue: ""

    // Seeded as well as fed. The signal is the only thing that MOVES `ready`, but a view
    // built after ui-host handed over never sees one — and with no seed it latches false for
    // the life of the tab: every control disabled, every list empty, nothing to retry.
    // `isViewModuleReady` is a function call, so it cannot be a binding; SignerView carries
    // the same two lines for the same reason.
    Component.onCompleted: root.ready = root.backend !== null
                                        && logos.isViewModuleReady("eth_wallet_ui")

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "eth_wallet_ui") root.ready = isReady && root.backend !== null
        }
    }

    // The Send dialog closes on the backend having a REQUEST ID, never on the click: a submit
    // the backend refused must stay on screen with its reason, which is the whole point of
    // moving the error inside the modal. At root scope because a Connections declared inside a
    // Popup that also sets contentItem is reparented into that contentItem.
    // What came back from asking another app to do something, when it is worth saying.
    // Empty is the normal state: a request that reached a provider hands the user over to
    // it, so this screen is not the one they are reading.
    // True from the click until the backend has either taken the send or refused it. The
    // gap is real work — pricing, a nonce reservation and the keystore's approval record —
    // and it happens with the dialog still up and nothing moving, so a user cannot tell a
    // slow send from a click that missed. Cleared by both outcomes below.
    property bool sendSubmitting: false

    property string approvalNote: ""
    property string intentNote: ""

    // ── another app's transactions: this wallet PROVIDES evm.transactions.send ──
    //
    // The shell's id for the request being serviced, held here because the view is the one
    // that answers the shell: the backend reviews, prices and sends, and publishes what it
    // decided in `intentSendJson`; every answer to the requester goes through answerIntent.
    // Empty when nothing is being serviced.
    property string intentSendRequestId: ""
    readonly property var intentSend: root.ready ? j(backend.intentSendJson, "{}") : ({})
    readonly property bool intentSendOpen: root.ready && backend.intentSendJson !== ""
                                           && root.intentSend.error === undefined
    readonly property bool intentSendPricing: root.ready && backend.intentSendPricing

    function answerIntent(ok, data, error) {
        var id = root.intentSendRequestId
        if (id === "") return
        root.intentSendRequestId = ""
        logos.respond(id, ok, data, error)
    }

    Connections {
        target: logos
        function onIntentRequested(requestId, intent, params, requesterName) {
            if (intent !== "evm.transactions.send") return
            // One review at a time. A request arriving over another ends the first: its
            // requester is told, and the human is shown the newest ask rather than a stack.
            if (root.intentSendRequestId !== "") root.answerIntent(false, ({}), "cancelled")
            root.intentSendRequestId = requestId
            root.backend.reviewIntentSend(JSON.stringify({ requestId: requestId,
                                                           requester: requesterName,
                                                           params: params }))
        }
    }
    // The outcome the user has already seen. Reset whenever a new send clears the backend's,
    // so two identical outcomes in a row still each get a receipt.
    property string dismissedOutcome: ""

    readonly property var sendOutcome: root.ready ? j(backend.lastSendOutcomeJson, "{}") : ({})
    // The whole hash, never the shortened one: it is what goes on the clipboard and what
    // addresses the detail screen.
    readonly property string outcomeHash: root.sendOutcome.hash !== undefined
                                          ? String(root.sendOutcome.hash) : ""

    function dismissOutcome() { root.dismissedOutcome = root.backend.lastSendOutcomeJson }
    readonly property bool showOutcome: root.ready && !root.sendPending
        && backend.lastSendOutcomeJson !== ""
        && backend.lastSendOutcomeJson !== root.dismissedOutcome

    // Ask whoever provides a capability to take over. Used for the three hops that are pure
    // navigation: the provider declares them `handoff`, so the user stays there and this
    // callback only ever runs to report that nobody went.
    function askFor(intent, whenUnavailable) {
        root.intentNote = ""
        logos.request(intent, ({}), function (res) {
            if (res.ok || res.error === "cancelled") return
            root.intentNote = res.error === "unavailable"
                ? whenUnavailable
                : "That request did not go through (" + res.error + ")."
        })
    }

    // Point a signer at the send now waiting on a human.
    //
    // The result is ADVISORY. `send_status` is what settles a send, and it has to be: the
    // shell reports `timeout` after ten minutes while the keystore record is still alive and
    // still approvable, the user can approve from the Signer app by hand with no intent in
    // flight at all, and a host with no intent router answers `unavailable` locally. So this
    // callback never moves the send — it only explains a trip that did not happen.
    // Codes that mean the intent path is CLOSED and no human is looking at the record. The
    // keystore cannot tell "nobody is coming" from "someone is coming, slowly" — with a
    // dispatch in flight the signer is often not even loaded yet, so early silence and
    // absence look identical from there. This side knows, because the dispatch completed.
    // Cancelling here is what lets the keystore's own timer be garbage collection for a dead
    // requester rather than a clock racing a human.
    //
    // `cancelled` is NOT, because it is not final. The Signer answers it for Back, for a newer
    // request taking its screen and for Reject: the first two leave the record approvable, and
    // a rejection reaches `send_status` in its own word. The shell's dismissed chooser says the
    // same word, so that send waits until it expires or is cancelled here.
    //
    // `unavailable` is NOT, and must not be. It may mean the signer is merely unreachable BY
    // INTENT while still openable by hand, and that manual path is the fallback this whole
    // design rests on — withdrawing there would delete the record the user was just told to
    // go and approve.
    function intentPathIsClosed(error) {
        return error === "bad_request" || error === "not_declared" || error === "timeout"
    }

    function askToApprove() {
        var handle = root.ready ? root.backend.pendingApprovalHandle : ""
        if (handle === "") return
        root.approvalNote = ""
        logos.request("evm.signing.approve", ({ handle: handle }), function (res) {
            // An answer about a send that is no longer the pending one moves nothing.
            if (!root.ready || root.backend.pendingApprovalHandle !== handle) return
            // `cancelled` is not a fault to report back at them, nor the end of the send.
            if (res.ok || res.error === "cancelled") return
            root.approvalNote = res.error === "unavailable"
                ? "Approve this transaction in the Signer app to send it."
                : "Could not reach a signer (" + res.error + ")."
            // Withdraw the approval rather than leaving it to expire. The send is settled by
            // `send_status` either way — this only decides whether the record dies now or
            // sits until the keystore collects it.
            if (root.intentPathIsClosed(res.error))
                root.backend.cancelSend()
        })
    }

    Connections {
        target: root.ready ? root.backend : null
        // Either outcome ends the wait: the backend took it (a request id appears) or
        // refused it (an error does). Both have to clear, or a refusal leaves the button
        // dead with nothing on the section to revive it. Only the first navigates, which
        // is what lets a refusal be asserted as "still on Send".
        function onPendingRequestIdChanged() {
            if (root.sendPending) {
                root.sendSubmitting = false
                sendReview.close()
                // The transaction exists now, so leave the form for where it shows up.
                // Tab first, then clear: an emptied form re-priced while still on screen
                // is a quote for a send nobody is making. A resend leaves the form alone.
                root.selectTab(3)
                if (!root.resendSubmitted) sendPage.clearForm()
                root.resendSubmitted = false
            } else if (root.intentSendRequestId !== "" && root.backend.lastSendOutcomeJson !== ""
                       && !root.intentSendOpen) {
                // The outcome is published a beat BEFORE the id clears; whichever lands
                // second is the one that answers, and this is that one.
                root.answerIntentFromOutcome()
            }
        }
        function onSendErrorChanged() {
            if (root.backend.sendError.length > 0) {
                root.sendSubmitting = false
                root.resendSubmitted = false
            }
        }

        // The handle arrives with the request id, and asking is the whole point of having it.
        function onPendingApprovalHandleChanged() {
            if (root.backend.pendingApprovalHandle !== "") root.askToApprove()
        }

        // Cleared at the start of every send, which is also when a receipt already read
        // stops counting as read.
        function onLastSendOutcomeJsonChanged() {
            if (root.backend.lastSendOutcomeJson === "") root.dismissedOutcome = ""
            // The send another app asked for has settled: it is answered with every hash,
            // or with the sender's word for why not. Only once the pending id has cleared —
            // the outcome is published a beat before it, and both must agree.
            if (root.backend.lastSendOutcomeJson !== "" && root.intentSendRequestId !== ""
                    && !root.sendPending && !root.intentSendOpen)
                root.answerIntentFromOutcome()
        }
        // A request the backend refused is answered with its code and the reason, and the
        // record is cleared; a request it accepted stays on screen until the human decides.
        function onIntentSendJsonChanged() {
            // Parsed HERE, off the property itself: a handler on the change signal can run
            // before the `intentSend` binding has been refreshed, and would then read the
            // record it replaced.
            var r = root.j(root.backend.intentSendJson, "{}")
            if (r.error === undefined || root.intentSendRequestId === "") return
            if (r.requestId !== undefined && r.requestId !== root.intentSendRequestId) return
            root.answerIntent(false, ({ detail: r.detail || "" }), String(r.error))
            root.backend.declineIntentSend()
        }
    }

    // The outcome record is the wallet's own; `answerFromOutcome` in the C++ half is the rule
    // this mirrors, kept in step by the table that runs it.
    function answerIntentFromOutcome() {
        var o = root.j(root.backend.lastSendOutcomeJson, "{}")
        if (o.status === undefined) return
        var data = ({ status: o.status })
        if (o.hash !== undefined) data.hash = o.hash
        if (o.hashes !== undefined) data.hashes = o.hashes
        if (o.reason !== undefined) data.reason = o.reason
        root.answerIntent(o.status === "broadcast", data, o.status === "broadcast" ? "" : String(o.status))
    }

    // The picker follows the backend's selection, including the re-select loadAccounts makes
    // when an account leaves the keystore. At root scope for the same reason as above.
    onSelectedChanged: if (accountPicker) accountPicker.syncIndex()

    function j(text, fallback) {
        try { return JSON.parse(text && text.length ? text : fallback) }
        catch (e) { return JSON.parse(fallback) }
    }

    readonly property var net: ready ? j(backend.activeNetworkJson, "{}") : ({})
    readonly property var networks: ready ? j(backend.networksJson, "[]") : []
    readonly property string networkScope: ready ? backend.networkScope : "mainnets"
    // `networks` is already the device-wide in-scope set. Wallet renders that answer and
    // delegates every edit to Ethereum RPC; it never reconstructs the registry's selector.
    readonly property var mainnetChains: networks.filter(function (n) { return n.testnet !== true })
    readonly property var testnetChains: networks.filter(function (n) { return n.testnet === true })
    readonly property var accounts: ready ? j(backend.accountsJson, "[]") : []
    // { "<lowercase hex, no 0x>": "<name>" }, relayed from the keystore.
    readonly property var accountLabels: ready ? j(backend.accountLabelsJson, "{}") : ({})
    readonly property var accountWallets: ready ? j(backend.accountWalletsJson, "{}") : ({})
    readonly property var fees: ready ? j(backend.feeTiersJson, "{}") : ({})
    readonly property bool feeTiersLoading: ready && backend.feeTiersLoading
    // Same rule as the balances: unknown AND being read spins, unknown and idle does not.
    readonly property bool feesPending: feeTiersLoading && root.fees.source === undefined

    // eth_rpc's verdict for the UI-local selected chain, relayed by the backend. Per-chain
    // portfolio failures remain attached to their own balance rows.
    readonly property var vp: ready ? j(backend.verifiedProxyJson, "{}") : ({})
    // Verification is on unless a verdict we could read says "off".
    readonly property bool verificationOn: ready && vp.mode !== undefined && vp.mode !== "off"

    // ── scoped values: the ONLY place a scoped backend property is read ───────────
    // A figure means something only against the account and network it was read under, so
    // every one below is gated on the backend saying it still does. Empty is UNKNOWN
    // throughout — an em-dash or a spinner, never a zero and never "none".
    readonly property bool scoped: ready && backend.scopedDataFresh
    readonly property bool dataLoading: ready && backend.dataLoading
    readonly property bool balancesLoading: ready && backend.balancesLoading

    // Neutral copies of five design-system icons. LogosIconButton colorizes its source, and
    // colorization preserves luminance — so an SVG that ships #5C5C5C or #969696 stays dark
    // whatever `iconColor` asks for, and reads as a disabled control. copy, check, close and
    // grid already ship white; these five did not. Local rather than fixed upstream because
    // those files are shared with Basecamp and the package manager, where the darker weight
    // is what ships today. Delete these the day the design system normalises them.
    readonly property url iconArrowLeft: Qt.resolvedUrl("assets/arrow-left.svg")

    // `flat` hides the background entirely, so a flat icon button has NO hover feedback at
    // all unless its tint reacts — and a control that never changes under the cursor reads as
    // decoration. The design system's own LogosCopyButton is the only one that does this, and
    // it looked like the odd one out in a row of three; it is the one that was right.
    component HoverIcon: LogosIconButton {
        flat: true
        iconColor: isActive ? Theme.palette.text : Theme.palette.textTertiary
    }

    // One destination on the Settings tab. Wallet-owned screens push locally; capabilities
    // owned by another app hand off through the shell. The use site decides which.
    component SettingsEntry: LogosItemDelegate {
        id: entry
        property url chevron

        Layout.fillWidth: true
        implicitHeight: 44
        font.pixelSize: Theme.typography.panelTitleText
        font.weight: Theme.typography.weightMedium

        // Anchored inside the delegate rather than replacing its contentItem, which would drop
        // the background and hover surface it draws. Pointing the way it takes you.
        LogosIcon {
            objectName: entry.objectName + "Chevron"
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
                rightMargin: Theme.spacing.medium
            }
            width: 16
            height: 16
            source: entry.chevron
            rotation: -90
        }
    }
    readonly property url iconList: Qt.resolvedUrl("assets/list.svg")
    readonly property url iconRefresh: Qt.resolvedUrl("assets/refresh.svg")
    readonly property url iconTrash: Qt.resolvedUrl("assets/trash.svg")
    readonly property url iconTriangleDown: Qt.resolvedUrl("assets/triangle-down.svg")

    readonly property bool quoteLoading: ready && backend.quoteLoading

    readonly property bool balancesKnown: scoped && backend.balancesJson.length > 0
    // Unknown AND being read is a spinner; unknown and not being read is an em-dash. The rep
    // states that rule; the Tokens tab was the one screen that did not honour it. Gated on the
    // balances leg, not the lane: the lane stays up through the history call that follows.
    readonly property bool balancesPending: !balancesKnown && balancesLoading
    readonly property var balances: balancesKnown ? j(backend.balancesJson, "[]") : []
    readonly property var balanceFailures: balances.filter(function (row) { return row.blocked === true })
    // eth_rpc's label for the read behind the balances on screen — the ONLY thing here that
    // can be proof-backed. Withdrawn with them: a claim cannot outlive the figure it is about.
    readonly property string balancesRoute: balancesKnown ? backend.balancesRoute : ""

    readonly property bool historyKnown: scoped && backend.historyJson.length > 0
    readonly property var history: historyKnown ? j(backend.historyJson, "[]") : []
    // Chains whose blocking proxy froze pending rows — including chains not shown here. Read
    // by the same call as the history, so it is unknown exactly when the history is.
    readonly property var blockedChains: historyKnown ? j(backend.blockedChainsJson, "[]") : []
    // Per chain, the nonce holding up later sends. From the same read as the history.
    readonly property var blockedNonces: historyKnown ? j(backend.blockedNoncesJson, "[]") : []
    readonly property bool resendLoading: ready && backend.resendLoading === true
    // A priced resend awaiting review: { request, quote }, withdrawn with the account.
    readonly property var resendReview: scoped ? j(backend.resendReviewJson, "{}") : ({})
    property bool resendSubmitted: false

    // A priced transfer as the review shows it: what leaves, to whom, and the one call.
    function transferRows(q, prefix, network) {
        var isNative = q.token === null || q.token === undefined
        var rows = [
            { name: prefix + "Amount", label: "You send", value: (q.amountExact || "—") + " " + (q.amountSymbol || "") },
            { name: prefix + "To", label: "To", value: root.namedAddr(q.to || "") },
            { name: prefix + "Network", label: "Network", value: network }
        ]
        if (isNative && q.maxCostWeiDisplay !== undefined)
            rows.push({ name: prefix + "Total", label: "Total",
                        value: "at most " + q.maxCostWeiDisplay + " " + (q.nativeSymbol || root.nativeSymbol) })
        return rows
    }
    function transferCalls(q) {
        if (q.to === undefined) return []
        var isNative = q.token === null || q.token === undefined
        return [isNative ? { label: "Send " + (q.amountSymbol || ""), to: q.to, value: q.amount }
                       : { label: "Transfer " + (q.amountSymbol || ""), to: q.tokenAddress, value: "0" }]
    }
    readonly property bool sweeping: historyKnown && backend.sweepingReceipts
    // Extra detail for ONE transaction, read on demand. Scoped like every other figure, and it
    // names the transaction it is about — the screen renders it for that hash alone.
    readonly property var txDetails: scoped ? j(backend.txDetailsJson, "{}") : ({})
    readonly property bool txDetailsLoading: ready && backend.txDetailsLoading
    // A receipt re-read is running. Its call is asynchronous, so the button that started it
    // has to say so — the synchronous version froze the window for up to twenty seconds.
    readonly property bool txStatusLoading: ready && backend.txStatusLoading

    // Chain-scoped: withdrawn on a network change, and re-read in the same turn.
    readonly property bool tokensKnown: ready && backend.tokensJson.length > 0
    readonly property var tokens: tokensKnown ? j(backend.tokensJson, "[]") : []
    readonly property var chainTokens: tokens.filter(function (token) {
        return token.chainId === undefined || token.chainId === root.chainId
    })

    // The persisted token order, from the published scope. Normalised to the closed set the
    // menu offers: an order this build does not know is shown as no order at all — a menu
    // with nothing marked and a strip naming an order the user cannot see.
    readonly property string tokenSort: {
        var v = ready ? backend.tokenSort : ""
        return v === "balance" ? "balance" : "alpha"
    }

    // The Tokens tab renders the BACKEND's order. get_balances answers a row for every enabled
    // token, already sorted by the persisted order, so this maps the token list onto the
    // positions it published rather than comparing amounts here: an 18-decimal comparison is
    // exact U256 work and belongs where it is testable. Positions, never amounts. A token the
    // balances do not name keeps its place, at the end — dropping it would hide a holding.
    readonly property var orderedTokens: {
        if (!balancesKnown) return tokens
        var pos = ({}), i
        for (i = 0; i < balances.length; ++i)
            pos[tokenKey(balances[i])] = i
        // Decorated with its own index, so the comparator is TOTAL. Keyed by symbol this map
        // was last-write-wins: two contracts sharing one collapsed to a single position, the
        // comparator answered 0 for the pair, and Qt's unstable sort then reshuffled the whole
        // list the backend had already ordered.
        var out = []
        for (i = 0; i < tokens.length; ++i) {
            var p = pos[tokenKey(tokens[i])]
            out.push({ t: tokens[i], p: p === undefined ? balances.length : p, i: i })
        }
        out.sort(function (a, b) { return a.p !== b.p ? a.p - b.p : a.i - b.i })
        return out.map(function (o) { return o.t })
    }

    // Send's UI-local chain cursor. The composer owns no active chain; 0 means no configured
    // in-scope chain can be selected.
    readonly property int chainId: net.chainId !== undefined ? net.chainId : 0

    // Account × chain × token × request. The backend withdraws it when any of them moves.
    readonly property var quote: scoped ? j(backend.quoteJson, "{}") : ({})
    // The request those figures priced. The Send screen renders them only while it still
    // equals the request the form describes — see sendForm.q.
    readonly property string quoteRequest: scoped ? backend.quoteRequestJson : ""
    // The last automatic re-price failed. Shown beside the figures it is about, never alone.
    readonly property bool quoteStale: scoped && backend.quoteStale

    readonly property string netName: net.name !== undefined ? net.name : ""
    // A network we could not read is not a network: nothing may be labelled with its name,
    // and the chip may not wear the colour that means "not a testnet".
    readonly property bool netKnown: netName.length > 0
    readonly property string nativeSymbol: net.nativeSymbol !== undefined ? net.nativeSymbol : ""
    // The chain's own currency as an identity. It has no contract, so it is matched by the one
    // key an address cannot spell rather than by whatever symbol the network calls it.
    readonly property var nativeToken: ({ native: true })
    function networkById(id) {
        for (var i = 0; i < networks.length; ++i)
            if (networks[i].chainId === id) return networks[i]
        return ({ chainId: id })
    }
    function networkIndex(id) {
        for (var i = 0; i < networks.length; ++i)
            if (networks[i].chainId === id) return i
        return -1
    }
    function networkNameFor(id) {
        var n = networkById(id)
        if (n.name === undefined || String(n.name).length === 0) return "Chain " + id
        return n.name + (n.testnet === true ? " (testnet)" : "")
    }
    // How cursor-scoped screens name their selected network.
    function networkLabel() { return netKnown ? netName + (isTestnet ? " (testnet)" : "") : "—" }
    readonly property bool isTestnet: net.testnet === true
    readonly property bool sendPending: ready && backend.pendingRequestId.length > 0

    readonly property string selected: ready ? backend.selectedAccount : ""
    // Destinations offered in the Send picker. You cannot mean to pick the account you are
    // sending from out of a list of recipients; typing it is still allowed, and warned about.
    readonly property var contacts: ready ? j(backend.contactsJson, "[]") : []

    function contactName(a) {
        for (var i = 0; i < contacts.length; ++i)
            if (sameHex(contacts[i].address, a)) return contacts[i].name || ""
        return ""
    }
    function isContact(a) {
        for (var i = 0; i < contacts.length; ++i)
            if (sameHex(contacts[i].address, a)) return true
        return false
    }

    // Who this account has actually paid, newest first and each address once. Read off the
    // history it already has rather than stored: a second list of recipients would be a copy
    // free to disagree with the transactions it was derived from.
    //
    // `to` is the RECIPIENT for both kinds, which is the field wanted here. It is not the
    // transaction's own `to`: for an ERC-20 send that is the token contract, and offering a
    // contract back as somewhere to send to is how a user burns funds into one. `rawTo` is
    // the function for that, and it is deliberately not the one used here.
    readonly property var recentRecipients: {
        var seen = ({}), out = []
        for (var i = 0; i < history.length; ++i) {
            var a = history[i].to || ""
            if (!a || !a.length) continue
            var k = a.toLowerCase()
            if (seen[k]) continue
            seen[k] = true
            out.push(a)
        }
        return out
    }

    readonly property var otherAccounts: accounts.filter(function (a) {
        return typeof a === "string" && a.length > 0 && !root.sameHex(a, root.selected)
    })

    // ── navigation ────────────────────────────────────────────────────────────────
    // Detail screens push onto `nav`. The harness cannot click a delegate, so each screen
    // opens through a plain function that a human click calls too.
    function selectTab(i) {
        if (nav.depth > 1) nav.popToIndex(0, StackView.Immediate)
        tabs.currentIndex = i
        pages.currentIndex = i
    }
    // The token must be chosen BEFORE the section becomes visible: entering runs
    // tokenPicker.syncIndex(), which reads it back off sendPage. Reversed, the picker resyncs
    // to whatever was there and the caller's choice is dropped silently.
    function openSend(t) {
        if (t && t.chainId !== undefined) root.backend.selectChain(t.chainId)
        sendPage.selectToken(t)
        root.selectTab(1)
    }
    // Keyed, never named: two contracts on one chain may both answer "LIT", and the by-symbol
    // form of this could only ever reach the first of them.
    function openTokenDetail(key) {
        if (tokenByKey(key) === null) return
        if (nav.depth > 1) nav.popToIndex(0, StackView.Immediate)
        nav.pushItem(tokenDetailComponent, { key: key })
    }
    function openTxDetail(hash) {
        if (txByHash(hash) === null) return
        if (nav.depth > 1) nav.popToIndex(0, StackView.Immediate)
        nav.pushItem(txDetailComponent, { hash: hash })
    }
    // Wallet-owned settings screens are sections of one tab. Kept as named functions: they
    // are what the probes and the harness call, and one place to change if the tab moves.
    // They are PUSHED, like a token or a transaction. selectTab first:
    // it pops any screen already up and puts the strip on Settings, so the tab the user is
    // left looking at is the one the pushed screen belongs to.
    function openNetworks() { root.selectTab(4); nav.pushItem(networksComponent) }

    function openAddressBook() { root.selectTab(4); nav.pushItem(addressBookComponent) }

    // A name for the tab index, so the probe and any later caller do not carry the number.
    function openReceive() { root.selectTab(2) }

    function back() { if (nav.depth > 1) nav.popCurrentItem() }

    // The closed set of actions the verdict may carry. Text only, no button: a sandboxed view
    // has no cross-plugin navigation, so a button to Verified Proxy would be dead.
    function actionHint(a) {
        if (a === "wait") return "Waiting for the verified proxy to catch up."
        if (a === "install_or_load") return "Install and start the Verified Proxy module, then reopen this wallet."
        if (a === "open_verified_proxy") return "Open Verified Proxy and press Start."
        if (a === "restart_or_reload") return "Open Verified Proxy, press Stop then Start. If that does not help, reload the app."
        return ""
    }

    // Per-chain, and only on the Networks screen: an aggregate badge cannot honestly say
    // "verified" when one chain is proof-backed and another is not. The setting and its
    // current readiness remain distinct so "on" never silently means "proved".
    function verificationText(n) {
        var mode = n && n.verifiedProxyMode !== undefined ? n.verifiedProxyMode : "unknown"
        var verdict = n && n.verifiedProxy !== undefined ? n.verifiedProxy : ({})
        if (mode === "off") return "Verification off"
        if (mode !== "required") return "Verification unknown"
        if (verdict.usable === true) return "Verification on · ready"
        if (verdict.state === "syncing") return "Verification on · syncing"
        return "Verification on · unavailable"
    }
    function verificationColor(n) {
        var mode = n && n.verifiedProxyMode !== undefined ? n.verifiedProxyMode : "unknown"
        var verdict = n && n.verifiedProxy !== undefined ? n.verifiedProxy : ({})
        if (mode === "off") return Theme.palette.textSecondary
        if (mode !== "required" || verdict.state === "syncing") return Theme.palette.warning
        return verdict.usable === true ? Theme.palette.success : Theme.palette.error
    }

    // What one of eth_rpc's route labels actually promises. `verified` is the only one that
    // means proved; an absent label promises nothing at all.
    function routeNote(r) {
        if (r === "verified") return "proof-backed."
        if (r === "proxied") return "forwarded to the proxy's own provider on trust, not proved."
        if (r === "direct") return "read straight from the endpoint, not proved."
        return "not labelled by eth_rpc, so not proved."
    }

    // One line per chain whose blocking proxy froze rows during the last sweep. `network`
    // and `message` are the backend's own words; the count decides the verb.
    // One stuck nonce, in words: what holds it, since when, and what waits behind it.
    function stuckNonceLine(b) {
        var at = root.networkNameFor(b.chainId) + ": nonce " + b.nonce
        var when = b.since > 0 ? Qt.formatDateTime(new Date(b.since * 1000), "MMM d, HH:mm") : ""
        var waiting = b.behind === 1 ? "1 later transaction is" : b.behind + " later transactions are"
        if (b.why === "stranded")
            return at + " was reserved but never sent, so " + waiting + " waiting behind it (since "
                 + when + ")."
        var what = at + " (" + (b.label || "a transaction") + ", sent " + when + ")"
             + (b.why === "unresolved" ? " never reported whether it went out" : " has not confirmed")
        return what + (b.behind > 0 ? ", and " + waiting + " waiting behind it." : ".")
    }
    function stuckNonceHint(b) {
        if (b.resend !== undefined) return ""
        var via = "send anything at nonce " + b.nonce + " from Send, under Advanced"
        if (b.why === "stranded") return "To release them, " + via + "."
        return (b.origin && b.origin !== "eth_wallet_backend" ? "Resend it from " + b.origin + ", or " : "To replace it, ")
             + via + "."
    }

    function blockedLine(b) {
        var n = b.count === 1 ? "1 transaction" : b.count + " transactions"
        var hint = root.actionHint(b.action)
        return n + " on " + b.network + " cannot be checked. " + (b.message || "")
             + (hint.length ? " " + hint : "")
    }

    // Bundled assets only. The sandbox denies every remote URL, so a token list's logoURI is
    // never fetched; anything without one falls back to the initial below.
    //
    // Takes the TOKEN: a bundled mark handed out by symbol lends this build's authority to
    // whoever deployed the next contract calling itself WETH.
    function localLogo(t) {
        if (!t || (t.native !== true && t.builtin !== true)) return ""
        if (t.symbol === "ETH") return "assets/eth.png"
        if (t.symbol === "WETH") return "assets/weth.png"
        return ""
    }

    // Case-folded equality for an address, a hash or a contract. An absent value on EITHER side
    // matches NOTHING: `(a || "") === (b || "")` answers TRUE about two absent values.
    function sameHex(a, b) {
        return typeof a === "string" && a.length > 0 && typeof b === "string" && b.length > 0
               && a.toLowerCase() === b.toLowerCase()
    }

    function shortAddr(a) {
        if (!a || a.length < 12) return a || ""
        return a.substring(0, 6) + "…" + a.substring(a.length - 4)
    }

    // The QR is encoded HERE, in JavaScript, and drawn as plain Rectangles. The sandbox this
    // view runs in refuses `data:` URIs and remote URLs, and a Canvas never receives paint()
    // inside the plugin's QQuickWidget — all three were measured. A sibling .js import is
    // admitted, so the encoder is one.
    function qrModules(text) {
        try {
            return text && text.length > 0 ? QrGen.modules(text) : null
        } catch (e) {
            return null
        }
    }

    // One Item per RUN of dark modules rather than per module: a solid row of the finder
    // pattern is then one Rectangle rather than seven.
    function qrRuns(qr) {
        var runs = []
        if (!qr) return runs
        for (var y = 0; y < qr.size; y++) {
            var x = 0
            while (x < qr.size) {
                if (qr.bits.charAt(y * qr.size + x) !== "1") { x++; continue }
                var start = x
                while (x < qr.size && qr.bits.charAt(y * qr.size + x) === "1") x++
                runs.push([start, y, x - start])
            }
        }
        return runs
    }

    // A hash is 66 characters, so it gets a wider window than an address: two transactions
    // from the same sweep are otherwise indistinguishable on screen.
    function shortHash(h) {
        if (!h || h.length < 24) return h || ""
        return h.substring(0, 10) + "…" + h.substring(h.length - 8)
    }

    // Display only, and a LOOKUP rather than a calculation: there is exactly one money
    // formatter and it is in the backend, where the arithmetic is exact 256-bit integer work.
    // An amount the backend could not scale emits no display key at all, which is an em-dash —
    // "we could not read it" is not "you have none".
    // Takes the TOKEN, not its symbol. get_balances names the contract on every row, and
    // matching on the symbol handed one contract's balance to another wearing the same one —
    // rendering a real holding as an em-dash on the row that actually owns it.
    function balanceField(t, field) {
        var k = tokenKey(t)
        if (k.length === 0) return "—"
        for (var i = 0; i < balances.length; ++i)
            if (tokenKey(balances[i]) === k)
                return balances[i][field] !== undefined ? balances[i][field] : "—"
        return "—"
    }
    // Bounded: "0" only for an exactly zero balance, "<0.00001" for real dust.
    function balanceDisplay(t) { return balanceField(t, "display") }
    // Every digit. The detail screens use this, so 1 wei is readable somewhere.
    function balanceExact(t) { return balanceField(t, "exact") }

    // A failed chain is carried as one explicit row beside the successful balance rows. Map
    // it onto every token on that chain: an em-dash means unknown, while this symbol means a
    // known read failure and its tooltip preserves the provider's explanation.
    function balanceFailureFor(t) {
        if (!t || t.chainId === undefined) return null
        for (var i = 0; i < balanceFailures.length; ++i)
            if (balanceFailures[i].chainId === t.chainId) return balanceFailures[i]
        return null
    }
    function balanceFailureDescription(t) {
        var failure = balanceFailureFor(t)
        if (failure === null) return ""
        var name = failure.network || networkNameFor(failure.chainId)
        return name + " balances unavailable: " + (failure.error || "The balance read failed.")
    }

    // The picker's row for an address. Case-folded: the keystore returns EIP-55 checksummed
    // hex and a caller may hand back any casing of the same account.
    function accountIndex(a) {
        for (var i = 0; i < accounts.length; ++i)
            if (sameHex(accounts[i], a)) return i
        return -1
    }

    // The offered token with this identity. There is deliberately no by-symbol form: a symbol
    // may name two of them, and every caller here has a whole row or a key to hand.
    function tokenByKey(key) {
        if (!key || key.length === 0) return null
        for (var i = 0; i < tokens.length; ++i)
            if (tokenKey(tokens[i]) === key) return tokens[i]
        return null
    }

    // One name per order, said the same way in the menu and on the strip above the list.
    // MetaMask calls the second one "Declining balance ($ high-low)"; this wallet has no
    // prices and will not fetch any — asking a price server which tokens to quote hands it
    // the user's holdings — so nothing here may be worded as an order by value.
    function tokenSortLabel(order) {
        return order === "balance" ? "Declining balance" : "Alphabetically (A-Z)"
    }

    // Asking is all this does: the backend persists the order and re-sorts the balances it
    // publishes, and the list follows those.
    function setTokenSort(order) {
        if (ready && order !== root.tokenSort) root.backend.chooseTokenSort(order)
    }

    // WHAT IDENTIFIES A TOKEN — here, and everywhere else in this view.
    //
    // A token is its (chain, contract), never its symbol: the shipped list carries five
    // (chain, symbol) pairs answered by two different contracts, and on chain 1 "LIT" is both
    // Litentry and Lighter at 18 decimals. Holding both is ordinary. Case-folded, because the
    // balances, the catalogue and the token list need not spell one address the same way. The
    // native currency has no contract, so it takes the one key an address cannot spell.
    function tokenKey(t) {
        if (!t) return ""
        var chain = t.chainId !== undefined ? String(t.chainId) + ":" : ""
        if (t.native === true) return chain + "native"
        if (typeof t.address === "string" && t.address.length > 0) return chain + t.address.toLowerCase()
        return t.symbol ? chain + "sym:" + t.symbol : ""
    }

    // Symbols more than one row in `list` answers to.
    function dupSymbols(list) {
        var seen = ({}), dup = ({})
        for (var i = 0; i < list.length; ++i) {
            var sym = String(list[i].symbol)
            if (seen[sym] === true) dup[sym] = true
            seen[sym] = true
        }
        return dup
    }
    readonly property var tokenDupSymbols: dupSymbols(tokens)

    // The contract, put on a row only where the symbol beside it is worn by another row on the
    // same screen. Keying by address stops the WALLET confusing the two; this is what stops
    // the reader doing it, and it is the address itself — "LIT (2)" names neither of them.
    function disambiguator(t, dup) {
        return t && dup[String(t.symbol)] === true ? shortAddr(t.address) : ""
    }

    // The Send picker's line. The control that decides which asset leaves the account is the
    // one place a bare symbol is least affordable.
    function tokenPickerLabel(t) {
        var line = t.symbol + " — " + balanceDisplay(t)
        var d = disambiguator(t, tokenDupSymbols)
        return d.length ? line + "  ·  " + (t.name || "") + " " + d : line
    }

    // WHERE A ROW'S CONTRACT ADDRESS CAME FROM, said on the row itself.
    //
    // Enabling a token is telling this wallet which contract to call for a symbol, and the
    // symbol proves nothing — anyone may deploy a contract that answers "USDC". Most rows here
    // come from a bundled SNAPSHOT of Uniswap's public list, which is a directory rather than
    // anything this wallet verified, and the screen may not present that as the same standing
    // as a token compiled into the build. `builtin` outranks `source`: a built-in is offered
    // on every chain that has it and cannot be turned off, whichever list also names it.
    function tokenSource(t) {
        if (!t) return "unknown"
        if (t.native === true) return "native"
        if (t.builtin === true) return "builtin"
        var s = typeof t.source === "string" ? t.source : ""
        return ["allowlist", "custom", "downloaded", "embedded", "enabled"].indexOf(s) >= 0
             ? s : "unknown"
    }
    // Never the word "verified": this view already spends that word on eth_rpc's proof-backed
    // reads, and a token's provenance is not a proof about a balance.
    function tokenSourceLabel(s) {
        if (s === "native") return "Network coin"
        if (s === "builtin") return "Built in"
        if (s === "allowlist") return "Wallet list"
        if (s === "custom") return "Added here"
        if (s === "downloaded") return "Fetched list"
        if (s === "embedded") return "Uniswap list"
        if (s === "enabled") return "Turned on here"
        return "Unknown source"
    }
    // A directory this wallet did not vouch for gets the warning colour. Not an alarm — the
    // row is perfectly usable — but it is the difference the user is being asked to weigh.
    function tokenSourceColor(s) {
        if (s === "native" || s === "builtin" || s === "allowlist")
            return Theme.palette.textSecondary
        if (s === "unknown") return Theme.palette.error
        return Theme.palette.warning
    }

    function txByHash(h) {
        for (var i = 0; i < history.length; ++i)
            if (sameHex(history[i].hash, h)) return history[i]
        return null
    }

    // The keystore keys labels by lowercase hex with no 0x prefix (vault_name), while
    // list_accounts returns EIP-55 checksummed addresses. They never match textually.
    function accountLabel(a) {
        if (!a) return ""
        var k = a.replace(/^0x/, "").toLowerCase()
        for (var key in accountLabels) if (sameHex(key, k)) return accountLabels[key]
        return ""
    }

    // The name when there is one, the short address otherwise. Never an invented "Account 2":
    // a positional name RENUMBERS when an account is added or removed, which in an account
    // picker means the label silently comes to mean a different account.
    function accountWallet(a) {
        if (!a) return null
        for (var key in accountWallets) if (sameHex(key, a)) return accountWallets[key]
        return null
    }

    // Every name this wallet knows for an address, in the order they answer for it: the
    // account's own, then the WALLET it was derived under, then the address book. Empty when
    // it knows none.
    //
    // `#index` is the DERIVATION index, off the account's own path, and it is stable for the
    // life of the account. A position in a list would not be: it renumbers when an account is
    // added or removed, so the label would silently come to mean a different account — which
    // is the whole reason nothing here invents "Account 2".
    function displayName(a) {
        var n = accountLabel(a)
        if (n.length) return n
        var w = accountWallet(a)
        if (w && w.wallet)
            return w.index !== undefined ? w.wallet + " #" + w.index : w.wallet
        return contactName(a)
    }

    // ONE rule for showing an address anywhere in this wallet, and the name never REPLACES
    // the address. A name is this wallet's own word for who that is and cannot be checked
    // against what was signed; the address is what the name existed to save the user reading.
    // So both, whenever a name is known at all: "Treasury (0x7099…79C8)".
    function namedAddr(a) {
        var n = displayName(a)
        return n.length ? n + " (" + shortAddr(a) + ")" : shortAddr(a)
    }

    // What a CLOSED picker shows: the name, or the short address when there is none. Not
    // both — the selected account's address is displayed beside the control, and a 220px box
    // holding a name and an address elides, taking the address with it. The open list shows
    // both, on two lines, which is what `AccountPicker` below is for.
    function accountDisplay(a) {
        var n = displayName(a)
        return n.length ? n : shortAddr(a)
    }

    // Both are still `pending` on disk. Blocked means the chain was never asked at all —
    // the proxy on the row's OWN network is refusing; stalled means we gave up asking.
    function statusText(rec) {
        if (rec.replaced === true) return "replaced"
        if (rec.verificationBlocked === true) return "not checked"
        return rec.stalled === true ? "unconfirmed" : (rec.status || "")
    }
    function statusColor(rec) {
        if (rec.replaced === true) return Theme.palette.textSecondary
        return rec.status === "confirmed" ? Theme.palette.success
             : rec.status === "failed" ? Theme.palette.error
                                       : Theme.palette.warning
    }

    // A row recorded before the backend stored token decimals has an unknowable amount and
    // carries no display key at all, so it renders as an em-dash rather than a guess.
    function txAmount(rec) {
        if (rec.valueDisplay === undefined) return "—"
        return "-" + rec.valueDisplay + " " + (rec.valueSymbol || "")
    }
    // Every digit, for the transaction screen.
    function txAmountExact(rec) {
        if (rec.valueExact === undefined) return "—"
        return "-" + rec.valueExact + " " + (rec.valueSymbol || "")
    }
    // Ask #9: the row's own title carries what left the account. Bounded, because eighteen
    // decimal places would blow the row; the screen beneath it shows every digit.
    //
    // A CALL is another app's transaction from this account — a swap, an approval — recorded
    // by the same sender this wallet uses. Its title is the label that app gave it, verbatim,
    // and the ether it carried only when it carried any: "Sent 0 ETH" would describe a swap
    // as a transfer of nothing.
    function txTitle(rec) {
        if (rec.kind === "call") {
            var title = rec.label && rec.label.length ? rec.label : "Contract call"
            if (rec.valueDisplay !== undefined && rec.valueDisplay !== "0")
                title += " · " + rec.valueDisplay + " " + (rec.valueSymbol || "")
            return title
        }
        if (rec.valueDisplay !== undefined)
            return "Sent " + rec.valueDisplay + " " + (rec.valueSymbol || "")
        return rec.valueSymbol ? "Sent " + rec.valueSymbol : "Sent"
    }

    // Who asked the sender for a call row, as the runtime attested it. Empty for this
    // wallet's own rows: naming ourselves on every transfer would be noise, and the wallet
    // is the one origin the user did not have to be told.
    function txOrigin(rec) {
        if (rec.kind !== "call") return ""
        return rec.origin && rec.origin.length ? "via " + rec.origin : "via another app"
    }

    // Every digit of a figure, for a copy button. Absent leaves the button off: copying an
    // em-dash is worse than having nothing to copy.
    function exactOf(v) { return v !== undefined ? String(v) : "" }

    // The paid fee once a receipt lands; until then the ceiling the user was quoted. Priced in
    // the ROW's own native symbol: a row on another chain is not denominated in this one's.
    // `exact` prints every digit — see feesCollide, where the bounded strings say nothing.
    function txFee(rec, exact) {
        var sym = rec.nativeSymbol !== undefined ? rec.nativeSymbol : ""
        if (rec.feeWeiDisplay !== undefined)
            return (exact && rec.feeWeiExact !== undefined ? rec.feeWeiExact
                                                           : rec.feeWeiDisplay) + " " + sym
        if (rec.feeCeilingWeiDisplay !== undefined) return "up to " + rec.feeCeilingWeiDisplay + " " + sym
        return "—"
    }

    // What the send was quoted at, beside what it paid. Same `exact` rule as txFee.
    function txCeiling(rec, exact) {
        if (rec.feeCeilingWeiDisplay === undefined) return "—"
        var sym = rec.nativeSymbol !== undefined ? rec.nativeSymbol : ""
        return (exact && rec.feeCeilingWeiExact !== undefined ? rec.feeCeilingWeiExact
                                                              : rec.feeCeilingWeiDisplay) + " " + sym
    }

    // Broadcast time, not block time: a receipt carries neither a timestamp nor anything that
    // implies one, so the label says which of the two this is. To the SECOND, because the row
    // below it is only ever a few seconds later and the two must be comparable.
    // One `rec.timestamp` guard, shared with txDay, txTime and txMined below.
    function txWhen(rec) {
        if (rec.timestamp === undefined || rec.timestamp <= 0) return "—"
        return Qt.formatDateTime(new Date(rec.timestamp * 1000), "yyyy-MM-dd HH:mm:ss")
    }

    // The day an activity row belongs to, as a key comparable against the row above it. Empty
    // for a row carrying no broadcast time: that row gets its own bucket rather than silently
    // joining the previous one's day.
    function txDay(rec) {
        if (!rec || rec.timestamp === undefined || rec.timestamp <= 0) return ""
        return Qt.formatDate(new Date(rec.timestamp * 1000), "yyyy-MM-dd")
    }

    // Today's key, and the one before it. `setDate` walks LOCAL midnights, so the day before
    // is the day before on a 23- or 25-hour DST day too — a 24-hour subtraction is not.
    function dayKey(offset) {
        var d = new Date()
        if (offset) d.setDate(d.getDate() + offset)
        return Qt.formatDate(d, "yyyy-MM-dd")
    }

    // The wall clock is not a binding dependency, and an idle wallet republishes no history —
    // so a heading reading `new Date()` itself keeps saying "Today" long past local midnight.
    // These are the dependency it reads instead, and the ticker below is what moves them.
    property string todayKey: dayKey(0)
    property string yesterdayKey: dayKey(-1)

    Timer {
        objectName: "dayKeyTicker"
        interval: 60000
        running: true
        repeat: true
        onTriggered: { root.todayKey = root.dayKey(0); root.yesterdayKey = root.dayKey(-1) }
    }

    // The heading that day wears. Relative for the two days a user thinks of by name, the date
    // itself otherwise. Formatted off the record, never off the key: `new Date("2026-08-31")`
    // parses as UTC midnight and renders as the day BEFORE west of Greenwich.
    function txDayHeading(rec) {
        var key = txDay(rec)
        if (!key.length) return "Date unknown"
        if (key === root.todayKey) return "Today"
        if (key === root.yesterdayKey) return "Yesterday"
        return Qt.formatDate(new Date(rec.timestamp * 1000), "MMM d, yyyy")
    }

    // Time of day for an activity row. The heading above it already carries the date, and an
    // undated row prints nothing rather than an epoch-zero midnight.
    function txTime(rec) {
        if (rec.timestamp === undefined || rec.timestamp <= 0) return ""
        return Qt.formatDateTime(new Date(rec.timestamp * 1000), "HH:mm")
    }

    // Whole seconds between broadcast and block, which is what the fetch actually buys. Integer
    // subtraction of two epoch seconds — no scaling, and nothing here is an amount.
    function minedAfter(d) {
        if (d < 60) return d + "s after broadcast"
        var m = Math.floor(d / 60)
        return m + "m " + (d - m * 60) + "s after broadcast"
    }

    // When the block was mined. It reaches us only with the block header the fetch button
    // reads, so until then it is an em-dash — never the broadcast time wearing the other label.
    // The wait is spelled out beside it: at minute resolution the two rows printed one string.
    function txMined(det, rec) {
        if (!det.block || det.block.timestamp === undefined) return "—"
        var t = det.block.timestamp
        var s = Qt.formatDateTime(new Date(t * 1000), "yyyy-MM-dd HH:mm:ss")
        if (rec.timestamp === undefined || rec.timestamp <= 0 || t < rec.timestamp) return s
        return s + " (" + root.minedAfter(t - rec.timestamp) + ")"
    }

    // The transaction's OWN `to` — the recipient for a native send, the token contract for an
    // erc20 one. `token` IS that contract for an erc20 row this wallet wrote, so it stands in
    // for a row recorded before `txTo` was.
    function rawTo(rec) {
        if (rec.txTo !== undefined) return rec.txTo
        return (rec.kind === "erc20" ? rec.token : rec.to) || ""
    }

    // How the raw card names that address: a contract wears the token's symbol where the table
    // knows it, a recipient its account name where the keystore does.
    function rawToDisplay(rec) {
        var a = rawTo(rec)
        if (!a.length) return "—"
        if (rec.kind !== "native" && rec.interactedWithSymbol !== undefined)
            return rec.interactedWithSymbol + " · " + shortAddr(a)
        return namedAddr(a)
    }

    // Gas burnt against the limit that was approved. Both sides are stored, so this needs no
    // fetch, and the percentage is the BACKEND's — arithmetic here is arithmetic on a double.
    // A limit recovered by the fetch prints without one rather than having one derived.
    function txGasUsed(rec, det) {
        if (rec.gasUsed === undefined) return "—"
        var limit = rec.gasLimit !== undefined ? rec.gasLimit
                  : (det.transaction && det.transaction.gasLimit !== undefined
                     ? det.transaction.gasLimit : undefined)
        if (limit === undefined) return String(rec.gasUsed)
        var pct = rec.gasUsedPercent !== undefined ? " (" + rec.gasUsedPercent + "%)" : ""
        return rec.gasUsed + " of " + limit + pct
    }

    // A per-gas price, exactly as the backend rendered and denominated it. Those come in gwei:
    // in ether every gas price there has ever been is under the resolution the bounded
    // rendering keeps, and would show as the dust marker for every transaction on the screen.
    function perGas(display, unit) {
        return display === undefined ? "—" : display + " " + (unit !== undefined ? unit : "")
    }

    // One decoded Transfer, in the token's own units where the table holds it. A token it does
    // not hold has UNKNOWN decimals, so the backend sends no rendered amount and this shows the
    // raw on-chain integer, labelled as one. Nothing here is ever scaled by an assumed 18.
    function transferAmount(t) {
        if (t.amountDisplay !== undefined) return t.amountDisplay + " " + (t.symbol || "")
        return t.amount + " base units"
    }

    // ── shared pieces ─────────────────────────────────────────────────────────────
    // Inline components cannot see the ids of the file that declares them, so anything they
    // need arrives as a property and anything they report leaves as a signal.

    component RowDivider: Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.palette.borderTertiaryMuted
    }

    component TokenGlyph: Item {
        id: glyph
        property string symbol: ""
        property url logoSource: ""
        implicitWidth: 32
        implicitHeight: 32

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            visible: logo.status !== Image.Ready
            color: Theme.colors.getColor(Theme.palette.primary, 0.18)
            LogosText {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: (glyph.symbol || "?").substring(0, 1)
                color: Theme.palette.primary
                font.weight: Theme.typography.weightMedium
            }
        }
        Image {
            id: logo
            anchors.fill: parent
            source: glyph.logoSource
            sourceSize: Qt.size(64, 64)
            visible: status === Image.Ready
        }
    }

    // Label left, value right. A non-empty copyValue swaps the value for a selectable one
    // with a copy button; the display string is pre-shortened because LogosSelectableText is
    // a TextEdit and clips rather than elides.
    // A label, the name this wallet knows, and the address IN FULL underneath. Two lines,
    // because one line holding both is a line something elides — and the name is ours to
    // shorten while the address is not: 0xa1E2…247E already dropped 30 characters, and a
    // container that trims it again leaves a string that identifies nothing.
    //
    // So the name elides and the address WRAPS. Used where there is room for the whole thing:
    // a transaction's detail and the address book. A picker shows the short form instead, on
    // its own line, where nothing further can cut it.
    component NamedAddressRow: ColumnLayout {
        id: nrow
        property string label: ""
        property string address: ""
        signal copied(string value)

        Layout.fillWidth: true
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.medium
            LogosText {
                text: nrow.label
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                Layout.preferredWidth: 132
            }
            LogosText {
                objectName: nrow.objectName.length > 0 ? nrow.objectName + "Name" : ""
                Layout.fillWidth: true
                visible: text.length > 0
                textFormat: Text.PlainText
                text: root.displayName(nrow.address)
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            Item { Layout.preferredWidth: 132 }
            LogosSelectableText {
                objectName: nrow.objectName.length > 0 ? nrow.objectName + "Address" : ""
                Layout.fillWidth: true
                text: nrow.address
                color: Theme.palette.textSecondary
                font.family: Theme.typography.mono
                font.pixelSize: Theme.typography.secondaryText
                // Wrapped, never elided. A detail screen has the room, and half an address is
                // worse than an address on two lines.
                wrapMode: Text.WrapAnywhere
                horizontalAlignment: Text.AlignRight
            }
            LogosCopyButton {
                // Named like the two buttons beside it in the address book row, which had one
                // each while this had none — the only unlabelled control in the group.
                ToolTip.text: "Copy"
                ToolTip.visible: hovered
                ToolTip.delay: 400
                objectName: nrow.objectName.length > 0 ? nrow.objectName + "Copy" : ""
                value: nrow.address
                onCopied: function (v) { nrow.copied(v) }
            }
        }
    }

    // An account picker whose ROWS carry both halves without either cutting the other.
    //
    // A LogosComboBox row is one elided line, so "Name (0xa1E2…247E)" in it loses the
    // address — already shortened from 42 characters to 11, and then trimmed again into
    // something that identifies nothing. Two lines fixes that rather than choosing between
    // them: the name may elide, because it is this wallet's own word and a user can widen the
    // window; the short address may not, because there is nothing left to take.
    //
    // The model is ADDRESSES, not display strings. Names are resolved per row, so a rename
    // lands without rebuilding the model — and the closed control asks the same resolver.
    component AccountPicker: LogosComboBox {
        id: picker
        property var addresses: []
        readonly property string currentAddress:
            currentIndex >= 0 && currentIndex < addresses.length ? addresses[currentIndex] : ""

        model: addresses
        displayText: root.accountDisplay(picker.currentAddress)

        // Overriding `delegate` replaces LogosComboBox's OWN, and with it the highlight and
        // the pointer cursor that made a row look clickable. Both are restored here rather
        // than left to the style: an ItemDelegate's default background is transparent, so
        // without this the list is inert-looking text that happens to respond.
        delegate: ItemDelegate {
            id: accountItem
            width: picker.popupListView ? picker.popupListView.width : picker.width
            objectName: "accountRow_" + index
            highlighted: picker.highlightedIndex === index
            background: Rectangle {
                color: accountItem.highlighted ? Theme.palette.surface : "transparent"
            }
            HoverHandler {
                cursorShape: accountItem.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
            contentItem: ColumnLayout {
                spacing: 0
                LogosText {
                    Layout.fillWidth: true
                    objectName: "accountRowName_" + index
                    visible: text.length > 0
                    textFormat: Text.PlainText
                    text: root.displayName(modelData)
                    elide: Text.ElideRight
                }
                LogosText {
                    Layout.fillWidth: true
                    objectName: "accountRowAddress_" + index
                    textFormat: Text.PlainText
                    text: root.shortAddr(modelData)
                    color: Theme.palette.textSecondary
                    font.family: Theme.typography.mono
                    font.pixelSize: Theme.typography.secondaryText
                    // Never elided. It is already the mid-ellided form; a second cut leaves a
                    // prefix that matches thousands of addresses.
                    elide: Text.ElideNone
                }
            }
        }
    }

    // A pick-one row for the recipient lists. Same two-line shape as the account picker's,
    // and for the same reason — one line carrying a name and an address is a line that
    // elides the address. The name may go; the short address may not.
    component PickableAddress: ItemDelegate {
        id: pick
        property string address: ""
        property string rowName: ""

        // `hovered`, not `highlighted`: these live in a plain ListView, so nothing else is
        // driving a highlighted index. Same reason as the account rows — an ItemDelegate
        // draws no background of its own and would otherwise look inert.
        background: Rectangle {
            color: pick.hovered ? Theme.palette.surface : "transparent"
        }
        HoverHandler {
            cursorShape: pick.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        contentItem: ColumnLayout {
            spacing: 0
            LogosText {
                Layout.fillWidth: true
                objectName: pick.objectName.length > 0 ? pick.objectName + "Name" : ""
                visible: text.length > 0
                textFormat: Text.PlainText
                text: pick.rowName.length > 0 ? pick.rowName : root.displayName(pick.address)
                elide: Text.ElideRight
            }
            LogosText {
                Layout.fillWidth: true
                objectName: pick.objectName.length > 0 ? pick.objectName + "Address" : ""
                textFormat: Text.PlainText
                text: root.shortAddr(pick.address)
                color: Theme.palette.textSecondary
                font.family: Theme.typography.mono
                font.pixelSize: Theme.typography.secondaryText
                elide: Text.ElideNone
            }
        }
    }

    component DetailRow: RowLayout {
        id: row
        property string label: ""
        property string value: ""
        property string copyValue: ""
        property bool mono: false
        signal copied(string value)
        function copy() { copyButton.copy() }

        Layout.fillWidth: true
        spacing: Theme.spacing.medium

        LogosText {
            text: row.label
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
            Layout.preferredWidth: 132
        }
        Item { Layout.fillWidth: true }

        LogosText {
            visible: row.copyValue.length === 0
            textFormat: Text.PlainText
            text: row.value
            font.family: row.mono ? Theme.typography.mono : Theme.typography.publicSans
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
        RowLayout {
            visible: row.copyValue.length > 0
            spacing: Theme.spacing.small
            LogosSelectableText {
                text: row.value
                font.family: row.mono ? Theme.typography.mono : Theme.typography.publicSans
            }
            LogosCopyButton {
                // Named like the two buttons beside it in the address book row, which had one
                // each while this had none — the only unlabelled control in the group.
                ToolTip.text: "Copy"
                ToolTip.visible: hovered
                ToolTip.delay: 400
                id: copyButton
                // Named after its row, so a probe can assert the copy branch is really on
                // screen rather than merely declared.
                objectName: row.objectName.length > 0 ? row.objectName + "Copy" : ""
                value: row.copyValue
                onCopied: function (v) { row.copied(v) }
            }
        }
    }

    // One activity row, shared by the Activity tab and a token's own activity list.
    //
    // The day heading is a SIBLING of the interactive row, never a child of it. Anchored
    // inside the delegate it sat under the delegate's own hover and press background, so
    // pointing at "Yesterday" lit the transaction beneath it up as one block.
    Component {
        id: txRowDelegate

        Column {
            id: txRow
            objectName: "txRow_" + modelData.hash
            width: ListView.view ? ListView.view.width : 0
            // A Column drops an invisible child AND the spacing that would follow it, so the
            // height covers a heading exactly when one is shown.
            spacing: Theme.spacing.small
            // The row above this one. Both models are plain JS arrays, which ListView's
            // section.property cannot read, so the day break is decided here instead.
            readonly property var prevRec: index > 0 && ListView.view
                                           ? ListView.view.model[index - 1] : null
            // Comparing against the neighbour is only enough because the backend sorts rows
            // newest-first (history.rs). Index 0 always opens a day, including an undated one.
            readonly property bool startsDay: index === 0
                                              || root.txDay(modelData) !== root.txDay(prevRec)

            LogosText {
                id: dayHeading
                objectName: "txDay_" + modelData.hash
                visible: txRow.startsDay
                width: txRow.width
                // Inset to the same column as the row below, which LogosItemDelegate pads.
                leftPadding: Theme.spacing.medium
                rightPadding: Theme.spacing.medium
                topPadding: Theme.spacing.small
                textFormat: Text.PlainText
                text: root.txDayHeading(modelData)
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }

            // The interactive row: the click, the hover, the press and the divider are all
            // its own, and it covers nothing but the transaction.
            LogosItemDelegate {
                id: txHit
                objectName: "txRowHit_" + modelData.hash
                width: txRow.width
                topPadding: Theme.spacing.small
                bottomPadding: Theme.spacing.small
                // Derived, not fixed: these rows wrap and are variable-height.
                implicitHeight: rowBody.implicitHeight + topPadding + bottomPadding
                onClicked: root.openTxDetail(modelData.hash)

                contentItem: ColumnLayout {
                    id: rowBody
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        LogosText {
                            objectName: "txTitle_" + modelData.hash
                            textFormat: Text.PlainText
                            text: root.txTitle(modelData)
                        }
                        Item { Layout.fillWidth: true }
                        LogosBadge {
                            objectName: "txChain_" + modelData.hash
                            text: root.networkNameFor(modelData.chainId)
                            color: root.networkById(modelData.chainId).testnet === true
                                   ? Theme.palette.accentOrange : Theme.palette.textSecondary
                        }
                        // The badge the receipt sweep moves from pending to confirmed.
                        LogosBadge {
                            objectName: "txStatus_" + modelData.hash
                            text: root.statusText(modelData)
                            color: root.statusColor(modelData)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.tiny
                        // Plain text, not selectable: a TextEdit here would swallow the click
                        // that opens the transaction.
                        LogosText {
                            objectName: "txTime_" + modelData.hash
                            visible: text.length > 0
                            Layout.rightMargin: Theme.spacing.tiny
                            textFormat: Text.PlainText
                            color: Theme.palette.textSecondary
                            text: root.txTime(modelData)
                        }
                        // Another app's call names who asked, where a transfer names whom
                        // it paid: the contract it called is on the screen beneath.
                        LogosText {
                            objectName: "txOrigin_" + modelData.hash
                            visible: modelData.kind === "call"
                            textFormat: Text.PlainText
                            color: Theme.palette.textSecondary
                            text: root.txOrigin(modelData)
                        }
                        LogosText {
                            visible: modelData.kind !== "call"
                            textFormat: Text.PlainText
                            color: Theme.palette.textSecondary
                            text: "To: " + root.namedAddr(modelData.to)
                        }
                        LogosCopyButton {
                            // Named like the two buttons beside it in the address book row, which had one
                            // each while this had none — the only unlabelled control in the group.
                            visible: modelData.kind !== "call"
                            ToolTip.text: "Copy"
                            ToolTip.visible: hovered
                            ToolTip.delay: 400
                            objectName: "txToCopy_" + modelData.hash
                            value: modelData.to
                            onCopied: function (v) { root.lastCopiedValue = v }
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1
                    color: Theme.palette.borderTertiaryMuted
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.medium
        spacing: Theme.spacing.small

        // ── header: the account these figures are about, and the chain they came from ──
        //
        // It stays over a pushed screen. A detail screen replaces only the pane under the tab
        // strip, so it is a place INSIDE the tab it opened from — and which account and which
        // chain its figures belong to is exactly what must not be left behind.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            AccountPicker {
                id: accountPicker
                objectName: "accountPicker"
                Layout.preferredWidth: 220
                addresses: root.accounts
                enabled: root.ready && root.accounts.length > 0
                onActivated: if (root.ready) root.backend.selectAccount(root.accounts[currentIndex])

                // Re-asserted, not bound: ComboBox writes currentIndex imperatively on a click,
                // which breaks a declarative binding for good — and the picker naming a
                // different account from the address beside it is two answers to one question.
                function syncIndex() { currentIndex = root.accountIndex(root.selected) }
                Component.onCompleted: syncIndex()
                onAddressesChanged: syncIndex()
            }

            // This picker only ever READS the account set — creating, importing and deleting
            // belong to whoever holds the keystore's custodian role. Asking for the
            // capability is how a wallet that holds no keys sends the user somewhere it
            // cannot go itself.
            //
            // An icon, with the label moved to a tooltip: it sits between the picker and the
            // address it names, where a word of chrome pushes the two apart. LogosIconButton
            // carries no text of its own, so the tooltip is the only thing naming it and is
            // not decoration.
            HoverIcon {
                objectName: "manageAccountsButton"
                size: 32
                iconSize: 16
                iconSource: LogosIcons.grid
                ToolTip.text: "Accounts"
                ToolTip.visible: hovered
                ToolTip.delay: 400
                onClicked: root.askFor("evm.accounts.manage",
                                       "No app on this device manages accounts.")
            }

            Item { Layout.fillWidth: true }
        }

        // The selected account's address and the device-wide portfolio scope. Send has its own
        // explicit chain picker below.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            // The one identifier a user hands out, so it is copyable wherever it appears.
            LogosSelectableText {
                objectName: "addressLabel"
                text: root.shortAddr(root.selected)
                color: Theme.palette.textSecondary
                font.family: Theme.typography.mono
            }
            LogosCopyButton {
                // Named like the two buttons beside it in the address book row, which had one
                // each while this had none — the only unlabelled control in the group.
                ToolTip.text: "Copy"
                ToolTip.visible: hovered
                ToolTip.delay: 400
                objectName: "addressCopyButton"
                value: root.selected
                onCopied: function (v) { root.lastCopiedValue = v }
            }

            Item { Layout.fillWidth: true }

            // This is a portfolio scope, not an "active network": the read-only tabs now
            // compose every enabled chain in the selected scope.
            LogosBadge {
                objectName: "chainChip"
                text: root.networkScope === "testnets" ? "TESTNETS"
                    : root.networkScope === "both" ? "MAINNETS + TESTNETS" : "MAINNETS"
                color: root.networkScope === "testnets" || root.networkScope === "both"
                       ? Theme.palette.accentOrange : Theme.palette.success
            }

        }

        // A badge cannot carry an instruction. When the wallet is showing nothing because the
        // proxy is unusable, this says so and what to do about it. Outside the stack, so a
        // detail screen carries the same warning as the list it was opened from.
        LogosFrame {
            objectName: "verifiedBanner"
            Layout.fillWidth: true
            visible: root.ready && root.vp.blocking === true

            // The frame's contentItem, NOT a child: LogosFrame overrides none, so a plain
            // child is sized to its own implicit width and fillWidth/wrapMode never apply.
            contentItem: ColumnLayout {
                spacing: Theme.spacing.tiny
                LogosText {
                    objectName: "verifiedBannerMessage"
                    Layout.fillWidth: true
                    // Backend-authored.
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Theme.palette.error
                    text: root.vp.message !== undefined ? root.vp.message : ""
                }
                LogosText {
                    objectName: "verifiedBannerAction"
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Theme.palette.textSecondary
                    text: root.actionHint(root.vp.action)
                }
                LogosButton {
                    objectName: "openVerifiedProxyButton"
                    // `wait` is the one action with nothing to go and do: the proxy is
                    // running and catching up on its own.
                    visible: root.vp.action !== undefined && root.vp.action.length > 0
                             && root.vp.action !== "wait"
                    text: "Open Verified Proxy"
                    onClicked: root.askFor("evm.verified_routing.operate",
                                           "Nothing on this device offers to do that — follow the note above.")
                }
                LogosText {
                    objectName: "intentNote"
                    Layout.fillWidth: true
                    visible: root.intentNote.length > 0
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Theme.palette.textSecondary
                    text: root.intentNote
                }
            }
        }

        // A row can be frozen at "pending" by the proxy on ITS OWN chain, which may differ
        // from Send's local network cursor. Keep that chain on the row.
        LogosFrame {
            objectName: "blockedChainsFrame"
            Layout.fillWidth: true
            visible: root.ready && root.blockedChains.length > 0

            contentItem: ColumnLayout {
                spacing: Theme.spacing.tiny
                Repeater {
                    model: root.blockedChains
                    LogosText {
                        objectName: "blockedChain_" + modelData.chainId
                        Layout.fillWidth: true
                        // Carries the backend's own message.
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: Theme.palette.warning
                        text: root.blockedLine(modelData)
                    }
                }
            }
        }

        // A nonce that holds up later sends, and the one-click way past it: the same transfer,
        // pinned to that nonce, priced so a node takes it as the replacement.
        LogosFrame {
            objectName: "blockedNoncesFrame"
            Layout.fillWidth: true
            visible: root.ready && root.blockedNonces.length > 0

            contentItem: ColumnLayout {
                spacing: Theme.spacing.small
                Repeater {
                    model: root.blockedNonces
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.small
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.tiny
                            LogosText {
                                objectName: "stuckNonce_" + modelData.chainId
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                                color: Theme.palette.warning
                                text: root.stuckNonceLine(modelData)
                            }
                            LogosText {
                                objectName: "stuckNonceHint_" + modelData.chainId
                                visible: text.length > 0
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                                color: Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText
                                text: root.stuckNonceHint(modelData)
                            }
                        }
                        LogosButton {
                            objectName: "resendNonceButton_" + modelData.chainId
                            visible: modelData.resend !== undefined
                            enabled: root.ready && !root.sendPending && !root.resendLoading
                            text: root.resendLoading ? "Resending…" : "Resend with current fees"
                            onClicked: root.backend.resendBlockedNonce(modelData.chainId)
                        }
                    }
                }
            }
        }

        // The banner and the only way out of it. A failed first read otherwise left the
        // wallet with no re-read a user could reach: nothing in this view calls `refresh`,
        // the network retry covers a network read alone, and the receipt sweep cannot arm
        // on a refusal.
        RowLayout {
            objectName: "errorRow"
            Layout.fillWidth: true
            // A Layout nested in a Layout defaults to fillHeight TRUE — this row took the
            // whole view and pushed everything below it off the bottom.
            Layout.fillHeight: false
            // Gated here rather than on each child: an invisible item is excluded from the
            // layout, so with no error the row occupies nothing at all.
            visible: root.ready && root.backend.lastError.length > 0
            spacing: 8

            LogosText {
                objectName: "errorLabel"
                Layout.fillWidth: true
                // Backend-authored; may contain anything.
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Theme.palette.error
                text: root.ready ? root.backend.lastError : ""
            }
            LogosButton {
                objectName: "errorRetryButton"
                enabled: root.ready
                text: "Retry"
                // `refresh` clears lastError on entry, so the banner and this button leave
                // together and a second failure brings both back.
                onClicked: root.backend.refresh()
            }
        }

        // NO headline figure. A wallet's hero number is a PORTFOLIO total, and this build has
        // no prices and will not fetch any — so the only honest candidate was one asset's
        // balance at 34px, which reads as a total and is not one.

        // ── five sections ──
        LogosTabBar {
            id: tabs
            objectName: "tabs"
            Layout.fillWidth: true
            // Through selectTab, so a CLICK obeys the same rule the function does. It used to
            // set the page index alone, which left a pushed screen sitting over the tab the
            // user had just chosen: the strip said Send, the pane still showed Address book.
            // Unreachable until the strip moved outside the StackView and stayed on screen.
            // No loop — selectTab assigns the index it was given, and an unchanged value
            // emits nothing.
            onCurrentIndexChanged: root.selectTab(currentIndex)
            LogosTabButton { text: "Tokens" }
            LogosTabButton { text: "Send" }
            LogosTabButton { text: "Receive" }
            LogosTabButton { text: "Activity" }
            LogosTabButton { text: "Settings" }
        }

        LogosStackView {
            id: nav
            objectName: "nav"
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ONLY the pane under the tab strip. A detail screen replaces this, so the
            // account, the network and the tabs stay put behind it — a token's screen is a
            // place inside the Tokens tab, not a different application.
            //
            // An inline Item, not a Component: StackView destroys only what it created, so
            // `pages` keeps its identity and selectTab() keeps working. Detail screens are
            // Components, so their absence is a real "the screen is closed".
            initialItem: Item {
                id: walletHome
                objectName: "walletHome"

                StackLayout {
                    id: pages
                    objectName: "pages"
                    anchors.fill: parent

                    // Tokens. spacing 0 with an explicit divider per row:
                    // LogosItemDelegate carries the hover/press/focus behaviour but
                    // ships no separator.
                    Item {
                        // The sort strip. The order itself is the BACKEND's — this says
                        // which one is on and asks for the other. Hidden with nothing to
                        // order: a control that can only be a no-op is noise.
                        RowLayout {
                            id: tokenSortStrip
                            objectName: "tokenSortStrip"
                            visible: root.tokens.length > 0
                            anchors {
                                top: parent.top; left: parent.left; right: parent.right
                            }
                            spacing: Theme.spacing.tiny
                            Item { Layout.fillWidth: true }
                            // Per-chain balance failures live beside their rows rather than in
                            // the global error banner, so its Retry button is intentionally not
                            // present for them. Keep an explicit way to ask every balance again.
                            HoverIcon {
                                objectName: "balancesRefreshButton"
                                size: 32
                                iconSize: 16
                                iconSource: root.iconRefresh
                                enabled: root.ready && !root.balancesLoading
                                ToolTip.text: "Refresh balances"
                                ToolTip.visible: hovered
                                ToolTip.delay: 400
                                onClicked: root.backend.refresh()
                            }
                            // Always on screen, so the order in force is readable without
                            // opening the menu that changes it.
                            LogosText {
                                objectName: "tokenSortLabel"
                                textFormat: Text.PlainText
                                text: root.tokenSortLabel(root.tokenSort)
                                color: Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText
                            }
                            // `id`, not objectName alone: an objectName does not enter the
                            // QML scope chain, so popupUnder() could not name it.
                            HoverIcon {
                                id: tokenSortButton
                                objectName: "tokenSortButton"
                                size: 32
                                iconSize: 16
                                iconSource: root.iconList
                                enabled: root.ready
                                onClicked: tokenSortMenu.popupUnder(tokenSortButton)
                            }
                        }

                        LogosListView {
                            objectName: "tokenList"
                            // Under the strip, so a row never scrolls behind the control
                            // that orders it.
                            anchors {
                                top: tokenSortStrip.visible ? tokenSortStrip.bottom : parent.top
                                left: parent.left; right: parent.right
                                bottom: parent.bottom
                            }
                            visible: root.tokens.length > 0
                            // The order is the backend's — see `orderedTokens`.
                            model: root.orderedTokens
                            spacing: 0
                            // Keyed on the contract throughout — objectName included: two
                            // rows named tokenRow_LIT are one row said twice, to a reader
                            // and to the harness alike.
                            delegate: LogosItemDelegate {
                                id: tokenRow
                                objectName: "tokenRow_" + root.tokenKey(modelData)
                                readonly property var balanceFailure: root.balanceFailureFor(modelData)
                                width: ListView.view ? ListView.view.width : 0
                                // The component hard-binds 36; a taller contentItem clips
                                // without this.
                                implicitHeight: 56
                                radius: Theme.spacing.radiusSmall
                                onClicked: root.openTokenDetail(root.tokenKey(modelData))

                                contentItem: RowLayout {
                                    spacing: Theme.spacing.small

                                    TokenGlyph {
                                        symbol: modelData.symbol
                                        logoSource: root.localLogo(modelData)
                                    }

                                    ColumnLayout {
                                        spacing: 0
                                        RowLayout {
                                            spacing: Theme.spacing.tiny
                                            LogosText {
                                                textFormat: Text.PlainText
                                                text: modelData.symbol
                                                font.weight: Theme.typography.weightMedium
                                            }
                                            LogosBadge {
                                                objectName: "tokenChain_" + root.tokenKey(modelData)
                                                text: modelData.network !== undefined
                                                      ? modelData.network : root.networkNameFor(modelData.chainId)
                                                color: modelData.testnet === true
                                                       ? Theme.palette.accentOrange
                                                       : Theme.palette.textSecondary
                                            }
                                        }
                                        RowLayout {
                                            spacing: Theme.spacing.tiny
                                            LogosText {
                                                objectName: "tokenName_" + root.tokenKey(modelData)
                                                textFormat: Text.PlainText
                                                text: modelData.name
                                                color: Theme.palette.textSecondary
                                                font.pixelSize: Theme.typography.secondaryText
                                            }
                                            // Present only where another row wears this
                                            // row's symbol, and then it is the contract.
                                            LogosText {
                                                objectName: "tokenContract_" + root.tokenKey(modelData)
                                                visible: text.length > 0
                                                textFormat: Text.PlainText
                                                text: root.disambiguator(modelData, root.tokenDupSymbols)
                                                color: Theme.palette.textSecondary
                                                font.pixelSize: Theme.typography.secondaryText
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    LogosSpinner {
                                        objectName: "balanceSpinner_" + root.tokenKey(modelData)
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitWidth: 16
                                        implicitHeight: 16
                                        visible: root.balancesPending
                                        running: visible
                                        ringColor: Theme.palette.textSecondary
                                    }
                                    LogosText {
                                        objectName: "balance_" + root.tokenKey(modelData)
                                        visible: !root.balancesPending && tokenRow.balanceFailure === null
                                        textFormat: Text.PlainText
                                        text: root.balanceDisplay(modelData)
                                    }
                                    LogosIcon {
                                        id: balanceErrorIcon
                                        objectName: "balanceError_" + root.tokenKey(modelData)
                                        readonly property string description:
                                            root.balanceFailureDescription(modelData)
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: 18
                                        Layout.preferredHeight: 18
                                        visible: !root.balancesPending && tokenRow.balanceFailure !== null
                                        source: LogosIcons.warning
                                        color: Theme.palette.error
                                        // warning.svg ships dark; normalize its luminance so the
                                        // error tint is visible on both idle and hovered rows.
                                        brightness: 1.0
                                        HoverHandler { id: balanceErrorHover }
                                        ToolTip.text: balanceErrorIcon.description
                                        ToolTip.visible: balanceErrorHover.hovered
                                        ToolTip.delay: 400
                                    }
                                }

                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    height: 1
                                    color: Theme.palette.borderTertiaryMuted
                                }
                            }
                        }

                        LogosText {
                            objectName: "tokensEmpty"
                            anchors.centerIn: parent
                            visible: root.tokensKnown && root.tokens.length === 0
                            text: "No assets in this scope"
                            color: Theme.palette.textSecondary
                        }
                        // A list nothing read is not a network with no tokens on it. No
                        // spinner: list_tokens is read synchronously inside refresh(), so
                        // "unknown" here always means the read failed, and errorLabel above
                        // is already carrying the reason.
                        LogosText {
                            objectName: "tokensUnknown"
                            anchors.centerIn: parent
                            visible: !root.tokensKnown
                            text: "—"
                            color: Theme.palette.textSecondary
                        }
                        // Two orders, and a line under the second saying what it orders
                        // by. MetaMask's own label for it is "($ high-low)"; this wallet
                        // has no prices and will not fetch any — asking a price server
                        // which tokens to quote hands it the user's holdings.
                        LogosMenu {
                            id: tokenSortMenu
                            objectName: "tokenSortMenu"
                            // Menu leaves contentWidth at 0 unless it is told: every row
                            // then renders at the background's width, which puts the tick
                            // on top of the label it belongs to. Measured, offscreen.
                            contentWidth: {
                                var w = 0
                                for (var i = 0; i < count; ++i)
                                    w = Math.max(w, itemAt(i).implicitWidth)
                                return w
                            }
                            Instantiator {
                                model: [
                                    { order: "alpha", note: "" },
                                    { order: "balance",
                                      note: "By token amount, not by value" }
                                ]
                                delegate: LogosMenuItem {
                                    id: sortItem
                                    objectName: "tokenSort_" + modelData.order
                                    text: root.tokenSortLabel(modelData.order)
                                    // LogosMenuItem hard-binds 32; the second line clips
                                    // without this. The right padding is the tick's own
                                    // column, so no label can run under it.
                                    implicitHeight: sortLabel.implicitHeight
                                                    + Theme.spacing.small * 2
                                    rightPadding: Theme.spacing.xxlarge
                                    onTriggered: root.setTokenSort(modelData.order)

                                    contentItem: ColumnLayout {
                                        id: sortLabel
                                        spacing: 0
                                        LogosText {
                                            leftPadding: Theme.spacing.medium
                                            textFormat: Text.PlainText
                                            text: sortItem.text
                                        }
                                        LogosText {
                                            objectName: "tokenSortNote_" + modelData.order
                                            visible: modelData.note.length > 0
                                            leftPadding: Theme.spacing.medium
                                            textFormat: Text.PlainText
                                            text: modelData.note
                                            color: Theme.palette.textSecondary
                                            font.pixelSize: Theme.typography.secondaryText
                                        }
                                    }

                                    // The order in force, ticked where it is chosen. Drawn
                                    // by the view rather than left to the style's own check:
                                    // a `checkable` row TOGGLES on the click, overwriting
                                    // the binding that reads the persisted order.
                                    LogosIcon {
                                        objectName: "tokenSortTick_" + modelData.order
                                        visible: root.tokenSort === modelData.order
                                        anchors {
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                            rightMargin: Theme.spacing.medium
                                        }
                                        width: 16
                                        height: 16
                                        source: LogosIcons.check
                                    }
                                }
                                onObjectAdded: function (i, o) {
                                    tokenSortMenu.insertItem(i, o)
                                }
                                onObjectRemoved: function (i, o) {
                                    tokenSortMenu.removeItem(o)
                                }
                            }
                        }
                    }

                    // Send. A section like the two beside it: comparing a balance against
                    // what you are about to send costs a tab, not a cancelled draft.
                    Item {
                        id: sendPage
                        objectName: "sendPage"

                        // WHICH ASSET LEAVES THE ACCOUNT, in the two fields the backend's SendRequest takes.
                        //
                        // `token` is the symbol — "ETH" included, because a built-in symbol still resolves to
                        // the native token. `tokenAddress` is the CONTRACT, and the backend resolves it first:
                        // a symbol two enabled contracts share is refused outright rather than guessed, so the
                        // address is what makes a send of either of them deliverable at all. Empty address is
                        // the native currency. Both are empty only until `openSend` seeds them on the way in.
                        property string token: ""
                        property string tokenAddress: ""

                        // The one place either is written. A null token is the native currency.
                        function selectToken(t) {
                            sendPage.token = t && t.symbol !== undefined ? String(t.symbol) : ""
                            sendPage.tokenAddress = t && t.native !== true
                                                      && typeof t.address === "string" ? t.address : ""
                        }

                        // Where the chosen token sits in the cursor chain's offered set, 0 (the native
                        // currency) when it is not there. By identity: symbols can collide.
                        function tokenIndex() {
                            var selectedToken = { chainId: root.chainId,
                                                  native: sendPage.tokenAddress.length === 0 }
                            if (sendPage.tokenAddress.length)
                                selectedToken.address = sendPage.tokenAddress
                            var k = root.tokenKey(selectedToken)
                            for (var i = 0; i < root.chainTokens.length; ++i)
                                if (root.tokenKey(root.chainTokens[i]) === k) return i
                            return 0
                        }

                        // Everything the last send left behind, except which token is leaving. Run on an
                        // accepted send and on Cancel — deliberately NOT on entry: what this protects is
                        // the NEXT send inheriting a stale recipient, and a section, unlike a popup, is
                        // stepped away from and back into mid-send.
                        //
                        // The fee overrides go too, and `advanced` closes over them. An override left armed
                        // under a collapsed disclosure prices the next send at the last one's gas.
                        function clearForm() {
                            toField.text = ""
                            amountField.text = ""
                            advanced.clear()
                            tierGroup.tier = "normal"
                        }
                        // Entering and leaving, in place of onOpened/onClosed: StackLayout
                        // gives exactly one child `visible`, and it falls the same way when
                        // a detail screen covers the home item — which is also when the
                        // quote poll should stop. Clears nothing; see clearForm.
                        onVisibleChanged: {
                            if (!root.ready) return
                            if (visible) { tokenPicker.syncIndex(); sendForm.reprice() }
                            root.backend.setQuoteAutoRefresh(visible)
                        }

                        LogosScrollView {
                            id: sendScroll
                            objectName: "sendScroll"
                            anchors.fill: parent
                            // As txDetailScroll: the component hard-binds contentWidth to
                            // its own width, and this form must never scroll sideways.
                            contentWidth: availableWidth

                            ColumnLayout {
                                id: sendForm
                                objectName: "sendForm"
                                // An explicit width, not fillWidth: a layout inside a
                                // Flickable is otherwise unconstrained and collapses to
                                // its own implicit width.
                                width: sendScroll.availableWidth
                                spacing: Theme.spacing.small

                                function request() {
                                    var r = {
                                        chainId: root.chainId,
                                        from: root.selected,
                                        to: toField.text.trim(),
                                        // TOKEN units — "0.1" ETH, not 10^17 wei. `amount` still means base units
                                        // on the wire, so the two are separate fields and never reinterpreted.
                                        amountUnits: amountField.text.trim(),
                                        tier: tierGroup.tier
                                    }
                                    if (sendPage.token.length) r.token = sendPage.token
                                    // The contract, exactly. `token` is a label two of them may share; this is the
                                    // field that decides which one moves, and the backend resolves it first.
                                    if (sendPage.tokenAddress.length) r.tokenAddress = sendPage.tokenAddress
                                    // Both fee fields or neither: an older fee_module prices a lone one at the tier.
                                    var o = advanced.overrides
                                    if (o.maxFeePerGas !== undefined) {
                                        r.maxFeePerGas = o.maxFeePerGas
                                        r.maxPriorityFeePerGas = o.maxPriorityFeePerGas
                                    }
                                    if (o.gasLimits !== undefined && o.gasLimits[0] !== null) r.gasLimit = o.gasLimits[0]
                                    if (o.nonce !== undefined) r.nonce = o.nonce
                                    return JSON.stringify(r)
                                }

                                // What the form describes RIGHT NOW. A binding, so every edit re-evaluates it —
                                // which is what makes a change no control re-priced impossible to miss.
                                readonly property string formRequest: request()
                                // The figures, only while they priced the request above. Hooking the REQUEST
                                // rather than each control is the difference between withdrawing a stale number
                                // and hoping the handler that would have withdrawn it ran.
                                readonly property var q: root.quoteRequest.length > 0
                                                         && root.quoteRequest === sendForm.formRequest
                                                         ? root.quote : ({})

                                function reprice() { if (root.ready) root.backend.quote(sendForm.formRequest) }
                                // Every way the form can change, including the ones no control caused: the token
                                // list being re-read under an open dialog, the account moving beneath it.
                                onFormRequestChanged: if (sendPage.visible) reprice()

                                // Sending is deliberately single-chain even though the read-only wallet is a
                                // portfolio. This picker moves only this view's cursor; it changes no device state.
                                LogosComboBox {
                                    id: sendNetworkPicker
                                    objectName: "sendNetworkPicker"
                                    Layout.fillWidth: true
                                    model: root.networks.map(function (n) { return root.networkNameFor(n.chainId) })
                                    enabled: root.ready && root.networks.length > 0 && !root.sendPending
                                    onActivated: root.backend.selectChain(root.networks[currentIndex].chainId)
                                }
                                Binding {
                                    target: sendNetworkPicker
                                    property: "currentIndex"
                                    value: root.networkIndex(root.chainId)
                                    restoreMode: Binding.RestoreNone
                                }

                                // Which token is leaving the account. Without this the header Send could only
                                // ever move the native currency.
                                LogosComboBox {
                                    id: tokenPicker
                                    objectName: "sendTokenPicker"
                                    Layout.fillWidth: true
                                    // A composed string model, not textRole: it matches accountPicker's shape and
                                    // needs no role plumbing.
                                    model: root.chainTokens.map(function (t) { return root.tokenPickerLabel(t) })
                                    enabled: root.ready && root.chainTokens.length > 0
                                    onActivated: sendPage.selectToken(root.chainTokens[currentIndex])

                                    // Re-asserted, not bound, exactly as accountPicker: ComboBox rewrites
                                    // currentIndex imperatively and resets it when the model is re-read — and the
                                    // picker naming a different token from the amount field beside it is two
                                    // answers to one question.
                                    function syncIndex() {
                                        currentIndex = sendPage.tokenIndex()
                                        if (root.chainTokens.length)
                                            sendPage.selectToken(root.chainTokens[Math.max(0, currentIndex)])
                                    }
                                    Component.onCompleted: syncIndex()
                                    onModelChanged: syncIndex()
                                }

                                // Free text stays the single source of truth: the picker writes into the field
                                // rather than becoming a second one.
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacing.tiny
                                    LogosTextField {
                                        id: toField
                                        objectName: "toField"
                                        Layout.fillWidth: true
                                        placeholderText: "Recipient address (0x…)"
                                    }
                                    // `id`, not objectName alone: an objectName does not enter the QML scope
                                    // chain, so `popupUnder(toAccountsButton)` below was a ReferenceError that
                                    // aborted the handler before the menu was ever asked to open.
                                    HoverIcon {
                                        id: toAccountsButton
                                        objectName: "toAccountsButton"
                                        size: 32
                                        iconSize: 16
                                        iconSource: root.iconTriangleDown
                                        // Always offered now. It used to hide itself when there was no SECOND
                                        // account, which was right while my-accounts was all it held — the
                                        // address book and the add form are reachable with one account, or none.
                                        onClicked: toAccountsMenu.popupUnder(toAccountsButton)
                                    }
                                }

                                // Three places an address can come from, and they are different KINDS of
                                // answer rather than one list with sections: who you have paid, who you chose to
                                // remember, and who you already are. A row writes into the field above rather
                                // than becoming a second source of truth — the free text stays authoritative.
                                LogosMenu {
                                    id: toAccountsMenu
                                    objectName: "toAccountsMenu"
                                    implicitWidth: 420

                                    function addressAt(tab, i) {
                                        if (tab === 0) return root.recentRecipients[i]
                                        if (tab === 1) return root.contacts[i].address
                                        return root.accounts[i]
                                    }

                                    ColumnLayout {
                                        width: parent.width
                                        spacing: Theme.spacing.tiny

                                        LogosTabBar {
                                            id: toTabs
                                            objectName: "toTabs"
                                            Layout.fillWidth: true
                                            LogosTabButton { objectName: "toTabRecent"; text: "Recents" }
                                            LogosTabButton { objectName: "toTabBook"; text: "Address book" }
                                            LogosTabButton { objectName: "toTabMine"; text: "My addresses" }
                                        }

                                        StackLayout {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 220
                                            currentIndex: toTabs.currentIndex

                                            // ── who this account has paid ──
                                            LogosListView {
                                                objectName: "toRecentList"
                                                clip: true
                                                model: root.recentRecipients
                                                delegate: PickableAddress {
                                                    objectName: "toRecent_" + index
                                                    width: ListView.view.width
                                                    address: modelData
                                                    onClicked: { toField.text = modelData; toAccountsMenu.close() }
                                                }
                                            }

                                            // ── who you chose to remember ──
                                            //
                                            // Read-only here. Managing the book from inside a send is a mis-tap
                                            // during a transaction costing a saved address, so this offers rows
                                            // and the Address book screen owns the rest.
                                            ColumnLayout {
                                                LogosListView {
                                                    objectName: "toBookList"
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    clip: true
                                                    model: root.contacts
                                                    delegate: PickableAddress {
                                                        objectName: "toContact_" + index
                                                        width: ListView.view.width
                                                        address: modelData.address
                                                        onClicked: {
                                                            toField.text = modelData.address
                                                            toAccountsMenu.close()
                                                        }
                                                    }
                                                }
                                                LogosText {
                                                    objectName: "toBookEmpty"
                                                    Layout.fillWidth: true
                                                    visible: root.contacts.length === 0
                                                    textFormat: Text.PlainText
                                                    wrapMode: Text.WordWrap
                                                    color: Theme.palette.textSecondary
                                                    text: "No saved addresses yet. Add them from the Address book."
                                                }
                                            }

                                            // ── who you already are ──
                                            LogosListView {
                                                objectName: "toMineList"
                                                clip: true
                                                model: root.accounts
                                                delegate: PickableAddress {
                                                    objectName: "toAccount_" + index
                                                    width: ListView.view.width
                                                    address: modelData
                                                    onClicked: { toField.text = modelData; toAccountsMenu.close() }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Warned, not refused: the backend builds a self-send happily, and a rule the UI
                                // enforces alone is a second copy of a rule free to drift from it.
                                LogosText {
                                    objectName: "selfSendWarning"
                                    visible: root.sameHex(toField.text.trim(), root.selected)
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WordWrap
                                    color: Theme.palette.warning
                                    text: "This sends to the account you are sending from. It costs gas and moves nothing."
                                }

                                LogosTextField {
                                    id: amountField
                                    objectName: "amountField"
                                    Layout.fillWidth: true
                                    // Token units, so "0.1" means a tenth of an ETH. The backend parses it against
                                    // the resolved token's decimals with exact integer arithmetic.
                                    // Never "Amount in ETH" on a network we could not read: the native currency
                                    // is not ETH everywhere, and a unit is a claim like any other.
                                    placeholderText: sendPage.token.length ? "Amount in " + sendPage.token
                                                   : root.nativeSymbol.length ? "Amount in " + root.nativeSymbol
                                                                              : "Amount"
                                }

                                // Low / Market / Fast, the wire names fee_module's slow / normal / fast.
                                Kit.FeeTierPicker { id: tierGroup }

                                // Where the numbers came from. A wallet quietly pricing off legacy gasPrice is how
                                // an overpayment goes unnoticed, so the source is on screen rather than in a log.
                                // The read is asynchronous now, so this line has a "reading" state of its own.
                                LogosSpinner {
                                    objectName: "feeSourceSpinner"
                                    implicitWidth: 14
                                    implicitHeight: 14
                                    visible: root.feesPending
                                    running: visible
                                    ringColor: Theme.palette.textSecondary
                                }
                                // What the quote priced, only while it priced the form on screen.
                                Kit.TxFeeSummary {
                                    id: feeSummary
                                    objectName: "sendFeeSummary"
                                    quote: sendForm.q.ok === true ? sendForm.q : ({})
                                    tier: tierGroup.tier
                                    nativeSymbol: root.nativeSymbol
                                }

                                // The chip in the header speaks for the balances only. These figures come from
                                // fee_module and the proxy's own execution provider, and `feeRoute` says so.
                                LogosText {
                                    objectName: "feeRouteNote"
                                    visible: root.verificationOn
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    color: Theme.palette.textSecondary
                                    font.pixelSize: Theme.typography.secondaryText
                                    text: "Fee figures are " + root.routeNote(sendForm.q.feeRoute)
                                }

                                // WHICH CONTRACT THE FIGURES PRICED, taken from prepare_send's own reply rather
                                // than from the form that asked. A symbol two offered tokens share names no asset,
                                // and this is the last screen before a signature — so where the symbol settles
                                // nothing, the contract is stated here. In the error colour if the backend priced
                                // a contract the picker did not choose, which is a send about to move the wrong one.
                                LogosText {
                                    objectName: "quoteTokenNote"
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    readonly property string priced: sendForm.q.ok === true
                                                                     && typeof sendForm.q.tokenAddress === "string"
                                                                     ? sendForm.q.tokenAddress : ""
                                    readonly property bool mismatch: priced.length > 0
                                                                     && !root.sameHex(priced, sendPage.tokenAddress)
                                    visible: priced.length > 0
                                             && (mismatch || root.tokenDupSymbols[sendPage.token] === true)
                                    color: mismatch ? Theme.palette.error : Theme.palette.textSecondary
                                    text: {
                                        if (priced.length === 0) return ""
                                        var t = root.tokenByKey(priced.toLowerCase())
                                        var named = (t && t.name ? t.name + " " : "") + root.shortAddr(priced)
                                        return mismatch ? "These figures priced a DIFFERENT contract: " + named
                                                        : "Priced for " + named
                                    }
                                }

                                // The figures are withdrawn the moment the request changes, so this is the only
                                // thing standing where they were. Text, not a spinner: this column already speaks
                                // in sentences and a fourth idiom would not read as one screen.
                                LogosText {
                                    objectName: "quotePricingNote"
                                    visible: root.quoteLoading && sendForm.q.ok !== true
                                    Layout.fillWidth: true
                                    color: Theme.palette.textSecondary
                                    text: "Pricing…"
                                }

                                LogosText {
                                    objectName: "quoteStaleNote"
                                    visible: root.quoteStale && sendForm.q.ok === true
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    color: Theme.palette.warning
                                    text: "The fee estimate could not be refreshed. The send is re-priced when "
                                          + "you submit it."
                                }

                                // The user's own fees, gas limit and nonce, in wei per gas, over the quote's.
                                Kit.TxAdvancedFields {
                                    id: advanced
                                    quote: sendForm.q.ok === true ? sendForm.q : ({})
                                }

                                // Beside the control that caused it, rather than on the wallet's own error
                                // line: that line sits above the tab bar, so a send refused after a scroll
                                // down to Advanced would report itself off-screen.
                                LogosText {
                                    objectName: "sendErrorLabel"
                                    visible: root.ready && root.backend.sendError.length > 0
                                    Layout.fillWidth: true
                                    // Backend-authored.
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WordWrap
                                    color: Theme.palette.error
                                    text: root.ready ? root.backend.sendError : ""
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    LogosButton {
                                        objectName: "sendCancelButton"
                                        text: "Cancel"
                                        onClicked: { sendPage.clearForm(); root.selectTab(0) }
                                    }
                                    Item { Layout.fillWidth: true }
                                    // Names the network, so the last click before a signature says where it lands.
                                    // No close() here: the dialog closes on pendingRequestId, so a refusal stays
                                    // on screen with its reason instead of vanishing behind the wallet.
                                    LogosSpinner {
                                        objectName: "sendSubmitSpinner"
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitWidth: 18
                                        implicitHeight: 18
                                        visible: root.sendSubmitting
                                        running: visible
                                        ringColor: Theme.palette.textSecondary
                                    }
                                    LogosButton {
                                        objectName: "sendSubmitButton"
                                        text: root.netKnown ? "Send on " + root.networkLabel() : "Send"
                                        enabled: root.ready && !root.sendPending && !root.sendSubmitting
                                                 && sendForm.q.ok === true && advanced.error.length === 0
                                        onClicked: sendReview.open()
                                    }
                                }
                            }
                        }
                    }

                    // Receive: the account's address, as something a phone can read and
                    // as text a human can check against it. No amount field — an amount
                    // makes this an EIP-681 URI, and a wallet that scans one and ignores
                    // the amount sends the wrong figure with nothing on screen saying so.
                    Item {
                        id: receivePage
                        objectName: "receivePage"

                        // The bare EIP-55 address, and never uppercased: the mixed case IS the checksum,
                        // and folding it throws away the only thing that catches a mistyped address.
                        readonly property string payload: root.selected
                        // Encoded only while the section shows. A StackLayout keeps every page
                        // alive, so an ungated binding re-encodes on every account switch for a
                        // tab the user may never open.
                        readonly property var qr: visible ? root.qrModules(payload) : null

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.medium
                            spacing: Theme.spacing.small

                            // An EVM address is the same on every chain, so the network chip above does
                            // not narrow what this code is for. A user who reads it as "Sepolia only"
                            // would ask for a second address they do not have.
                            LogosText {
                                objectName: "receiveNote"
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                                color: Theme.palette.textSecondary
                                text: "One address, every EVM chain. What arrives depends on the network "
                                      + "the sender is on, not the one selected here."
                            }

                            Item { Layout.fillHeight: true }

                            // Plain Rectangles, for the reason qrModules() gives.
                            Rectangle {
                                id: qrBox
                                objectName: "receiveQrBox"
                                Layout.alignment: Qt.AlignHCenter
                                readonly property var qr: receivePage.qr
                                readonly property int quiet: 4
                                // Floored, and the BOX then takes the size that falls out. A fractional
                                // cell leaves hairline seams between the rectangles, and a scanner reads
                                // some of those as module boundaries.
                                readonly property int cell: qr ? Math.max(1, Math.floor(240 / (qr.size + quiet * 2))) : 0
                                // Literal, not Theme: a palette colour inverts in dark mode, and an
                                // inverted code does not scan. Do not "fix" these.
                                color: "#ffffff"
                                visible: !!qr
                                Layout.preferredWidth: qr ? cell * (qr.size + quiet * 2) : 0
                                Layout.preferredHeight: Layout.preferredWidth

                                Repeater {
                                    model: root.qrRuns(qrBox.qr)
                                    Rectangle {
                                        x: (modelData[0] + qrBox.quiet) * qrBox.cell
                                        y: (modelData[1] + qrBox.quiet) * qrBox.cell
                                        width: modelData[2] * qrBox.cell
                                        height: qrBox.cell
                                        color: "#000000"
                                    }
                                }
                            }

                            LogosText {
                                objectName: "receiveUnavailable"
                                Layout.alignment: Qt.AlignHCenter
                                visible: !receivePage.qr
                                textFormat: Text.PlainText
                                color: Theme.palette.textSecondary
                                // `qr` is null for BOTH an empty selection and an encoder that
                                // threw, and the address line beside this one keys off the
                                // payload — so saying "no account" under a visible address is a
                                // screen contradicting itself.
                                text: receivePage.payload.length > 0
                                      ? "This address could not be encoded, so there is no code to show."
                                      : "No account is selected, so there is nothing to receive to."
                            }

                            // The WHOLE address, wrapped rather than shortened: this screen is where a
                            // user checks it character by character against what they were given, and
                            // the elided form in the header cannot be checked against anything.
                            LogosSelectableText {
                                objectName: "receiveAddress"
                                Layout.fillWidth: true
                                visible: receivePage.payload.length > 0
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: TextEdit.WrapAnywhere
                                font.family: Theme.typography.mono
                                text: receivePage.payload
                            }

                            LogosCopyButton {
                                // Its own name. Reusing `addressCopyButton` from the header would give
                                // two controls one name, and a harness that finds by objectName and
                                // ignores visibility would reach whichever came first.
                                objectName: "receiveAddressCopyButton"
                                Layout.alignment: Qt.AlignHCenter
                                ToolTip.text: "Copy"
                                ToolTip.visible: hovered
                                ToolTip.delay: 400
                                visible: receivePage.payload.length > 0
                                value: receivePage.payload
                                onCopied: function (v) { root.lastCopiedValue = v }
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }

                    // Activity
                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Theme.spacing.tiny

                            // The chip speaks for the balances. A status badge is a
                            // receipt read, which the backend labels with no route at all.
                            LogosText {
                                objectName: "activityRouteNote"
                                visible: root.verificationOn
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText
                                text: "Status below is read from a receipt and forwarded "
                                      + "on trust — not proved, whatever the chip says."
                            }

                            LogosText {
                                objectName: "sweepNote"
                                visible: root.sweeping
                                Layout.fillWidth: true
                                color: Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText
                                text: "Checking for confirmations…"
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                LogosText {
                                    objectName: "historyEmpty"
                                    anchors.centerIn: parent
                                    visible: root.historyKnown && root.history.length === 0
                                    text: "No transactions yet"
                                    color: Theme.palette.textSecondary
                                }
                                // Unknown is not empty: the line above is an answer about
                                // an account whose history has not been read.
                                ColumnLayout {
                                    objectName: "historyUnknown"
                                    anchors.centerIn: parent
                                    spacing: Theme.spacing.small
                                    visible: !root.historyKnown
                                    LogosSpinner {
                                        objectName: "historySpinner"
                                        Layout.alignment: Qt.AlignHCenter
                                        implicitWidth: 24
                                        implicitHeight: 24
                                        visible: root.dataLoading
                                        running: visible
                                        ringColor: Theme.palette.textSecondary
                                    }
                                    LogosText {
                                        objectName: "historyUnknownNote"
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.dataLoading ? "Loading transactions…" : "—"
                                        color: Theme.palette.textSecondary
                                    }
                                }
                                LogosListView {
                                    objectName: "historyList"
                                    anchors.fill: parent
                                    visible: root.history.length > 0
                                    model: root.history
                                    spacing: 0
                                    delegate: txRowDelegate
                                }
                            }
                        }
                    }

                    // Wallet-owned settings are pushed onto `nav`. Token membership belongs to
                    // Token Lists, so that row hands off through its declared capability.
                    Item {
                        id: settingsPage
                        objectName: "settingsPage"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.medium
                            spacing: Theme.spacing.tiny

                            SettingsEntry {
                                objectName: "addressBookEntry"
                                text: "Address book"
                                chevron: root.iconTriangleDown
                                onClicked: root.openAddressBook()
                            }
                            SettingsEntry {
                                objectName: "networksEntry"
                                text: "Networks"
                                chevron: root.iconTriangleDown
                                onClicked: root.openNetworks()
                            }
                            SettingsEntry {
                                objectName: "tokenListsEntry"
                                text: "Token lists"
                                chevron: root.iconTriangleDown
                                onClicked: root.askFor("evm.token_lists.configure",
                                                       "Nothing on this device manages token lists.")
                            }
                            LogosText {
                                objectName: "tokenListsIntentNote"
                                Layout.fillWidth: true
                                visible: root.intentNote.length > 0
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                                color: Theme.palette.textSecondary
                                text: root.intentNote
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }
        }
    }

    // ── token detail ──────────────────────────────────────────────────────────────
    // Resolved out of root.tokens on every render, so a balance refresh or a token-list
    // change reaches an open screen. No price, no buy, no swap, no fiat: this wallet has no
    // market data, and a screen that implied otherwise would be inventing it.
    Component {
        id: tokenDetailComponent

        Item {
            id: tokenPage
            objectName: "tokenDetailPage"
            // The token's identity, not its symbol: the by-symbol form of this made the
            // second of two same-symbol contracts an unreachable screen.
            property string key: ""

            readonly property bool tokKnown: root.tokenByKey(tokenPage.key) !== null
            readonly property var tok: tokKnown ? root.tokenByKey(tokenPage.key) : ({})
            readonly property string symbol: tokKnown ? String(tokenPage.tok.symbol) : ""
            readonly property var balanceFailure: tokKnown
                                                   ? root.balanceFailureFor(tokenPage.tok) : null
            // Only a list we have READ can say this token is not on this network. While it is
            // unknown the screen stays and shows dashes, rather than closing under the user
            // every time the network is re-read.
            readonly property bool gone: root.tokensKnown && !tokKnown
            onGoneChanged: if (gone) root.back()

            // A token we have no entry for matches NOTHING: with no address to compare against,
            // the comparison that stood here answered TRUE for every native row on the account.
            readonly property var activity: !tokenPage.tokKnown ? [] : root.history.filter(function (r) {
                return tokenPage.tok.native === true ? r.kind === "native"
                     : root.sameHex(r.token, tokenPage.tok.address)
            })

            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    HoverIcon {
                        objectName: "detailBackButton"
                        size: 32
                        iconSize: 20
                        iconSource: root.iconArrowLeft
                        onClicked: root.back()
                    }
                    LogosText {
                        objectName: "tokenDetailTitle"
                        textFormat: Text.PlainText
                        text: tokenPage.symbol
                        font.pixelSize: Theme.typography.panelTitleText
                        font.weight: Theme.typography.weightMedium
                    }
                    Item { Layout.fillWidth: true }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.spacing.small
                    TokenGlyph {
                        symbol: tokenPage.symbol
                        logoSource: root.localLogo(tokenPage.tok)
                    }
                    LogosText {
                        objectName: "tokenDetailName"
                        textFormat: Text.PlainText
                        text: tokenPage.tok.name !== undefined ? tokenPage.tok.name : ""
                        color: Theme.palette.textSecondary
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.spacing.small
                    LogosText {
                        objectName: "tokenDetailBalance"
                        visible: !root.balancesPending && tokenPage.balanceFailure === null
                        textFormat: Text.PlainText
                        font.pixelSize: 34
                        // EXACT here, bounded in the list: a balance of 1 wei has to be readable
                        // somewhere, and this is the screen that exists to say so.
                        text: root.balanceExact(tokenPage.tok) + " " + tokenPage.symbol
                    }
                    LogosSpinner {
                        objectName: "tokenDetailBalanceSpinner"
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 20
                        implicitHeight: 20
                        visible: root.balancesPending
                        running: visible
                        ringColor: Theme.palette.textSecondary
                    }
                    LogosIcon {
                        id: tokenDetailBalanceError
                        objectName: "tokenDetailBalanceError"
                        readonly property string description:
                            root.balanceFailureDescription(tokenPage.tok)
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        visible: !root.balancesPending && tokenPage.balanceFailure !== null
                        source: LogosIcons.warning
                        color: Theme.palette.error
                        brightness: 1.0
                        HoverHandler { id: tokenDetailBalanceErrorHover }
                        ToolTip.text: tokenDetailBalanceError.description
                        ToolTip.visible: tokenDetailBalanceErrorHover.hovered
                        ToolTip.delay: 400
                    }
                }

                LogosButton {
                    objectName: "tokenDetailSendButton"
                    Layout.alignment: Qt.AlignHCenter
                    text: "Send " + tokenPage.symbol
                    enabled: root.ready && !root.sendPending
                    onClicked: {
                        root.openSend(tokenPage.tok)
                    }
                }

                LogosText {
                    text: "Token details"
                    font.pixelSize: Theme.typography.subtitleText
                    font.weight: Theme.typography.weightMedium
                }

                LogosFrame {
                    objectName: "tokenDetailsCard"
                    Layout.fillWidth: true

                    contentItem: ColumnLayout {
                        spacing: Theme.spacing.small

                        DetailRow {
                            label: "Network"
                            value: tokenPage.tok.network !== undefined
                                   ? tokenPage.tok.network
                                     + (tokenPage.tok.testnet === true ? " (testnet)" : "")
                                   : root.networkNameFor(tokenPage.tok.chainId)
                        }
                        RowDivider {}
                        // The native currency has no contract. An empty chip would read as an
                        // address we failed to fetch rather than as a category that has none.
                        DetailRow {
                            objectName: "tokenContractRow"
                            label: "Contract address"
                            mono: tokenPage.tok.native !== true
                            value: tokenPage.tok.native === true ? "Native currency"
                                 : tokenPage.tok.address !== undefined
                                   ? root.shortAddr(tokenPage.tok.address) : "—"
                            copyValue: tokenPage.tok.native === true
                                       ? "" : (tokenPage.tok.address || "")
                            onCopied: function (v) { root.lastCopiedValue = v }
                        }
                        RowDivider {}
                        DetailRow {
                            objectName: "tokenDecimalsRow"
                            label: "Token decimals"
                            value: tokenPage.tok.decimals !== undefined
                                   ? String(tokenPage.tok.decimals) : "—"
                        }
                        RowDivider {}
                        // Where this row's name and decimals came from. The boolean this
                        // replaces said "No" for the native currency on every chain, forever:
                        // ETH has no contract address to match a list entry against.
                        DetailRow {
                            objectName: "tokenMetadataRow"
                            label: "Metadata"
                            // Every name the backend documents, not three of them. "shipped"
                            // was never one of its answers, so that branch was dead — and the
                            // else caught `embedded`, `custom`, `enabled` and `unknown` and
                            // called all four this wallet's own list, which is what a row
                            // enabled from a token list wrongly said.
                            value: tokenPage.tok.metadataSource === "native"     ? "Defined by the network"
                                 : tokenPage.tok.metadataSource === "allowlist"  ? "This wallet's built-in list"
                                 : tokenPage.tok.metadataSource === "embedded"   ? "A token list shipped with this device"
                                 : tokenPage.tok.metadataSource === "downloaded" ? "A token list downloaded on this device"
                                 : tokenPage.tok.metadataSource === "custom"     ? "A token list you added"
                                 : tokenPage.tok.metadataSource === "enabled"    ? "A snapshot taken when you enabled it"
                                 : tokenPage.tok.metadataSource === "unknown"    ? "A token list that did not say which"
                                                                                 : "—"
                        }

                        // Only where the row above leaves something unsaid. It used to be
                        // unconditional and claimed this wallet downloads no token lists —
                        // untrue since token_list arrived, and printed over rows that had come
                        // from a downloaded list.
                        LogosText {
                            objectName: "tokenListNote"
                            Layout.fillWidth: true
                            visible: text.length > 0
                            wrapMode: Text.WordWrap
                            textFormat: Text.PlainText
                            color: Theme.palette.textSecondary
                            font.pixelSize: Theme.typography.secondaryText
                            text: tokenPage.tok.metadataSource === "allowlist"
                                  ? "Named by this wallet's own table. No token list on this "
                                    + "device carries this contract."
                                  : tokenPage.tok.metadataSource === "enabled"
                                    ? "You enabled this from a list that no longer carries it, "
                                      + "so the name and decimals here are the snapshot taken then."
                                    : ""
                        }
                    }
                }

                LogosText {
                    text: "Your activity"
                    font.pixelSize: Theme.typography.subtitleText
                    font.weight: Theme.typography.weightMedium
                }

                LogosText {
                    objectName: "tokenActivityEmpty"
                    visible: root.historyKnown && tokenPage.tokKnown && tokenPage.activity.length === 0
                    text: "No transactions yet"
                    color: Theme.palette.textSecondary
                }

                LogosText {
                    objectName: "tokenActivityUnknown"
                    visible: !root.historyKnown || !tokenPage.tokKnown
                    text: root.dataLoading ? "Loading transactions…" : "—"
                    color: Theme.palette.textSecondary
                }

                LogosListView {
                    objectName: "tokenActivityList"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: tokenPage.activity.length > 0
                    model: tokenPage.activity
                    spacing: 0
                    delegate: txRowDelegate
                }
            }
        }
    }

    // ── transaction detail ────────────────────────────────────────────────────────
    // Resolved out of root.history on every render, so the pending-to-confirmed sweep
    // updates an open screen with no wiring of its own. A field the backend never recorded
    // is an em-dash: older rows carry no receipt numbers, and a zero would be a claim.
    Component {
        id: txDetailComponent

        Item {
            id: txPage
            objectName: "txDetailPage"
            property string hash: ""

            readonly property var rec: root.txByHash(txPage.hash) || ({})
            // Extra detail is published for ONE transaction and carries the hash it is about,
            // so a fetch made on the previous screen cannot fill this one's rows.
            readonly property var det: root.sameHex(root.txDetails.hash, txPage.hash)
                                       ? root.txDetails : ({})
            // The tip: the row's own where it was recorded with one, the fetch's otherwise.
            // Both are the backend's rendering, in the backend's unit — neither is derived.
            readonly property var tip: txPage.rec.maxPriorityFeePerGasDisplay !== undefined
                                       ? txPage.rec
                                       : (txPage.det.transaction || ({}))
            readonly property var transfers: txPage.rec.transfers !== undefined
                                             ? txPage.rec.transfers : []
            // The transaction's own calldata, sourced exactly as `tip` above: the row's where
            // it was recorded with one, the fetch's otherwise. Empty is UNKNOWN — an older row
            // carries no `txInput` at all, and the Fetch button at the bottom backfills it.
            readonly property string txInput: txPage.rec.txInput !== undefined
                                              ? txPage.rec.txInput
                                              : ((txPage.det.transaction || ({})).input || "")
            // A length, not an amount: two hex characters per byte, and "0x" is not one of them.
            readonly property int dataBytes: (txPage.txInput.length - 2) / 2
            // An erc20 send whose receipt has not landed decodes no transfers, and the raw card
            // above carries the CONTRACT — so the recipient the user typed would be nowhere.
            readonly property bool recipientRecorded: txPage.rec.kind === "erc20"
                                                      && txPage.transfers.length === 0
            // The ceiling belongs beside a fee that was PAID. While the row is pending the fee
            // row already shows the ceiling, and one number under two labels explains nothing.
            readonly property bool feeCeilingShown: txPage.rec.feeWeiDisplay !== undefined
                                                    && txPage.rec.feeCeilingWeiDisplay !== undefined
            // The two exist to be COMPARED, and on a real send both bounded strings came out
            // "<0.00001": 35% of headroom rendered as a verbatim duplicate of the row above.
            // When they collide, both rows print every digit — a string test, not arithmetic.
            readonly property bool feesCollide: txPage.feeCeilingShown
                && txPage.rec.feeWeiDisplay === txPage.rec.feeCeilingWeiDisplay
            // Nothing is left to ask for: the block landed and neither leg reported a failure.
            readonly property bool detailsComplete: txPage.det.block !== undefined
                                                    && txPage.det.blockError === undefined
                                                    && txPage.det.transactionError === undefined
            // The backend's own words, rendered beside the rows they are about. NOT lastError:
            // the header sits outside the nav stack, where this would be read under whatever
            // screen replaces this one.
            readonly property string detailsError: txPage.det.ok === false
                ? (txPage.det.error || "")
                : [txPage.det.blockError, txPage.det.transactionError]
                  .filter(function (e) { return e !== undefined && e.length > 0 }).join(" · ")
            // A transaction belongs to the account it was sent from: when the selection moves
            // this screen is about the previous one and closes. A history we merely could not
            // re-read leaves it open showing dashes — the row did not go anywhere.
            readonly property bool gone: !root.scoped
                                         || (root.historyKnown && root.txByHash(txPage.hash) === null)
            onGoneChanged: if (gone) root.back()

            LogosScrollView {
                id: txScroll
                objectName: "txDetailScroll"
                anchors.fill: parent
                // The component hard-binds contentWidth to its own width; this page wants the
                // width inside the scrollbar gutter, and must never scroll sideways.
                contentWidth: availableWidth

                // An explicit width, not fillWidth: a layout inside a Flickable is otherwise
                // unconstrained and collapses to its own implicit width.
                ColumnLayout {
                    width: txScroll.availableWidth
                    spacing: Theme.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        HoverIcon {
                            objectName: "detailBackButton"
                            size: 32
                            iconSize: 20
                            iconSource: root.iconArrowLeft
                            onClicked: root.back()
                        }
                        LogosText {
                            objectName: "txDetailTitle"
                            textFormat: Text.PlainText
                            text: root.txTitle(txPage.rec)
                            font.pixelSize: Theme.typography.panelTitleText
                            font.weight: Theme.typography.weightMedium
                        }
                        Item { Layout.fillWidth: true }
                        // Also offered on a settled row with no fee recorded: the sweep never
                        // re-polls a settled row, so only this can backfill an older one.
                        HoverIcon {
                            objectName: "txDetailRefresh"
                            size: 32
                            iconSize: 18
                            iconSource: root.iconRefresh
                            // `txTo` present means a receipt was absorbed by a build carrying the
                            // fields below; an older settled row has a fee and would never have
                            // been offered the re-poll that backfills them.
                            enabled: root.ready && !root.txStatusLoading
                                     && (txPage.rec.status === "pending"
                                         || txPage.rec.feeWei === undefined
                                         || txPage.rec.txTo === undefined)
                            onClicked: root.backend.refreshTxStatus(txPage.hash)
                        }
                        // The call is asynchronous, so the window stays live while it runs and
                        // the only thing left to say it is running is this.
                        LogosSpinner {
                            objectName: "txDetailRefreshSpinner"
                            implicitWidth: 18
                            implicitHeight: 18
                            visible: root.txStatusLoading
                            running: visible
                            ringColor: Theme.palette.textSecondary
                        }
                    }

                    // Always negative: this history records only what this wallet broadcast.
                    LogosText {
                        objectName: "txDetailAmount"
                        Layout.alignment: Qt.AlignHCenter
                        textFormat: Text.PlainText
                        font.pixelSize: 34
                        // Exact: the title above already carries the bounded figure.
                        text: root.txAmountExact(txPage.rec)
                    }

                    // Frozen, not stalled: the chain was never asked, because the verified proxy
                    // for THIS row's own network is blocking. The frame at the top of the screen
                    // carries the proxy's own words and what to do about it.
                    LogosText {
                        objectName: "txDetailBlockedNote"
                        visible: txPage.rec.verificationBlocked === true
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: Theme.palette.warning
                        text: "Not being checked: verification is blocking on this transaction's "
                              + "own network, so its receipt is not being read."
                    }

                    // A reverted transaction moved the FEE and nothing else. There is no total for
                    // one — the fee row below is the whole of what left — so this names the number
                    // that did move rather than leaving "Total amount" to imply the amount did.
                    LogosText {
                        objectName: "txDetailFailedNote"
                        visible: txPage.rec.status === "failed"
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: Theme.palette.error
                        text: "This transaction failed on chain. The amount above never left this "
                              + "account; the network fee below was still charged."
                    }

                    LogosText {
                        objectName: "txDetailReplacedNote"
                        visible: txPage.rec.replaced === true
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: Theme.palette.textSecondary
                        text: "Another transaction at nonce " + txPage.rec.nonce + " was mined, so this "
                              + "one never will be. Nothing in it left this account."
                    }

                    LogosText {
                        objectName: "txDetailStalledNote"
                        visible: txPage.rec.stalled === true && txPage.rec.replaced !== true
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: Theme.palette.warning
                        text: "Broadcast over an hour ago and never seen on chain. Checking has "
                              + "stopped; refresh to ask again."
                    }

                    LogosFrame {
                        objectName: "txDetailCard"
                        Layout.fillWidth: true

                        contentItem: ColumnLayout {
                            spacing: Theme.spacing.small

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacing.medium
                                LogosText {
                                    text: "Status"
                                    color: Theme.palette.textSecondary
                                    font.pixelSize: Theme.typography.secondaryText
                                    Layout.preferredWidth: 132
                                }
                                Item { Layout.fillWidth: true }
                                LogosBadge {
                                    objectName: "txDetailStatus"
                                    text: root.statusText(txPage.rec)
                                    color: root.statusColor(txPage.rec)
                                }
                            }
                            RowDivider {}
                            DetailRow {
                                objectName: "txDetailBroadcastRow"
                                label: "Broadcast"
                                value: root.txWhen(txPage.rec)
                            }
                            RowDivider {}
                            // Empty until the fetch below reads the block header: no receipt
                            // carries a time, and the broadcast row above is a different fact.
                            DetailRow {
                                objectName: "txDetailMinedRow"
                                label: "Mined"
                                value: root.txMined(txPage.det, txPage.rec)
                            }
                            RowDivider {}
                            NamedAddressRow {
                                objectName: "txDetailFromRow"
                                label: "From"
                                address: txPage.rec.from || ""
                                onCopied: function (v) { root.lastCopiedValue = v }
                            }
                            // This card carries RAW transaction fields and nothing interpreted, so
                            // both rows below render the transaction's OWN `to` and the row shown
                            // is chosen by what that field means. A native send addressed the
                            // recipient; an erc20 send addressed the token contract and has no
                            // recipient field at all — the interpretation lives further down.
                            RowDivider {}
                            DetailRow {
                                objectName: "txDetailToRow"
                                visible: txPage.rec.kind === "native"
                                label: "To"
                                mono: true
                                value: root.rawToDisplay(txPage.rec)
                                copyValue: root.rawTo(txPage.rec)
                                onCopied: function (v) { root.lastCopiedValue = v }
                            }
                            DetailRow {
                                objectName: "txDetailInteractedRow"
                                visible: txPage.rec.kind !== "native"
                                label: "Interacted with"
                                mono: true
                                value: root.rawToDisplay(txPage.rec)
                                copyValue: root.rawTo(txPage.rec)
                                onCopied: function (v) { root.lastCopiedValue = v }
                            }
                            // A call another app made from this account: who asked, in the
                            // runtime's words, and what it claimed the call was for, in its
                            // own. Both backend-authored, both plain text.
                            RowDivider { visible: txPage.rec.kind === "call" }
                            DetailRow {
                                objectName: "txDetailOriginRow"
                                visible: txPage.rec.kind === "call"
                                label: "Asked by"
                                value: txPage.rec.origin && txPage.rec.origin.length
                                       ? txPage.rec.origin : "another app"
                            }
                            RowDivider { visible: txPage.rec.kind === "call"
                                                  && txPage.rec.purpose !== undefined
                                                  && txPage.rec.purpose.length > 0 }
                            DetailRow {
                                objectName: "txDetailPurposeRow"
                                visible: txPage.rec.kind === "call"
                                         && txPage.rec.purpose !== undefined
                                         && txPage.rec.purpose.length > 0
                                label: "Purpose (claimed)"
                                value: txPage.rec.purpose || ""
                            }
                            // The bytes the contract was actually called with — wrapped, not
                            // elided, because they are the point of the row rather than a label
                            // for it. A native send has no calldata and gets no row.
                            RowDivider { visible: txPage.rec.kind !== "native" }
                            ColumnLayout {
                                objectName: "txDetailDataRow"
                                visible: txPage.rec.kind !== "native"
                                Layout.fillWidth: true
                                spacing: Theme.spacing.tiny

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacing.small
                                    LogosText {
                                        objectName: "txDetailDataLabel"
                                        text: txPage.txInput.length > 0
                                              ? "Data · " + txPage.dataBytes + " bytes" : "Data"
                                        color: Theme.palette.textSecondary
                                        font.pixelSize: Theme.typography.secondaryText
                                    }
                                    Item { Layout.fillWidth: true }
                                    LogosCopyButton {
                                        // Named like the two buttons beside it in the address book row, which had one
                                        // each while this had none — the only unlabelled control in the group.
                                        ToolTip.text: "Copy"
                                        ToolTip.visible: hovered
                                        ToolTip.delay: 400
                                        objectName: "txDetailDataCopy"
                                        visible: txPage.txInput.length > 0
                                        value: txPage.txInput
                                        onCopied: function (v) { root.lastCopiedValue = v }
                                    }
                                }
                                LogosSelectableText {
                                    objectName: "txDetailDataValue"
                                    Layout.fillWidth: true
                                    // WrapAnywhere: calldata is one unbroken word, so WordWrap
                                    // would leave the whole of it on a single clipped line.
                                    wrapMode: TextEdit.WrapAnywhere
                                    font.family: Theme.typography.mono
                                    font.pixelSize: Theme.typography.secondaryText
                                    text: txPage.txInput.length > 0 ? txPage.txInput : "—"
                                }
                            }
                            RowDivider {}
                            DetailRow {
                                label: "Network"
                                value: root.networkNameFor(txPage.rec.chainId)
                            }
                            RowDivider {}
                            DetailRow {
                                objectName: "txDetailHashRow"
                                label: "Transaction ID"
                                mono: true
                                value: root.shortHash(txPage.rec.hash)
                                copyValue: txPage.rec.hash || ""
                                onCopied: function (v) { root.lastCopiedValue = v }
                            }
                            RowDivider {}
                            DetailRow {
                                objectName: "txDetailNonceRow"
                                label: "Nonce"
                                value: txPage.rec.nonce !== undefined ? String(txPage.rec.nonce) : "—"
                            }
                            RowDivider {}
                            DetailRow {
                                objectName: "txDetailBlockRow"
                                label: "Block"
                                value: txPage.rec.blockNumber !== undefined
                                       ? String(txPage.rec.blockNumber) : "—"
                            }
                        }
                    }

                    // ── tokens transferred ────────────────────────────────────────
                    // Decoded from the receipt's OWN logs, so it costs nothing and is a fact rather
                    // than a guess: an event topic0 is the full 32-byte keccak of the signature and
                    // does not practically collide, unlike a 4-byte function selector.
                    //
                    // ABSENT, not "none", when there are none: a row whose receipt we never read
                    // carries no `transfers` key at all, so this never claims that nothing moved.
                    LogosText {
                        objectName: "txDetailTransfersHeading"
                        visible: txPage.transfers.length > 0 || txPage.recipientRecorded
                        text: "Tokens transferred"
                        font.pixelSize: Theme.typography.subtitleText
                        font.weight: Theme.typography.weightMedium
                    }

                    LogosFrame {
                        objectName: "txDetailTransfersCard"
                        visible: txPage.transfers.length > 0
                        Layout.fillWidth: true

                        contentItem: ColumnLayout {
                            spacing: Theme.spacing.small

                            Repeater {
                                model: txPage.transfers
                                ColumnLayout {
                                    objectName: "txDetailTransfer_" + index
                                    Layout.fillWidth: true
                                    spacing: 2
                                    DetailRow {
                                        objectName: "txDetailTransferAmount_" + index
                                        label: modelData.mine === true ? "Sent" : "Transferred"
                                        value: root.transferAmount(modelData)
                                        // The exact figure where we have one; the raw integer is
                                        // already exact, and is what a user would paste elsewhere.
                                        copyValue: modelData.amountExact !== undefined
                                                   ? modelData.amountExact : modelData.amount
                                        onCopied: function (v) { root.lastCopiedValue = v }
                                    }
                                    // Once a receipt decodes a transfer, the recorded-recipient
                                    // card below goes away and these are the ONLY rendering of
                                    // the recipient left — so they are copyable like every
                                    // other address here, not a truncated line.
                                    NamedAddressRow {
                                        objectName: "txDetailTransferFrom_" + index
                                        label: "From"
                                        address: modelData.from || ""
                                        onCopied: function (v) { root.lastCopiedValue = v }
                                    }
                                    NamedAddressRow {
                                        objectName: "txDetailTransferTo_" + index
                                        label: "To"
                                        address: modelData.to || ""
                                        onCopied: function (v) { root.lastCopiedValue = v }
                                    }
                                    LogosText {
                                        objectName: "txDetailUnknownToken_" + index
                                        visible: modelData.known !== true
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        wrapMode: Text.WordWrap
                                        color: Theme.palette.warning
                                        font.pixelSize: Theme.typography.secondaryText
                                        text: modelData.contract + " is not in this wallet's token "
                                              + "list, so its decimals are unknown. The figure above "
                                              + "is the raw on-chain amount, not a token amount."
                                    }
                                }
                            }

                            // What the cap dropped, counted rather than quietly forgotten.
                            LogosText {
                                objectName: "txDetailTransfersMore"
                                visible: txPage.rec.transfersMore !== undefined
                                         && txPage.rec.transfersMore > 0
                                color: Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText
                                text: "+" + txPage.rec.transfersMore + " more transfers in this "
                                      + "transaction"
                            }
                        }
                    }

                    // Standing in for the transfers above until a receipt is read. Deliberately in
                    // the interpreted section and NOT in the raw card: this is what this wallet
                    // asked for, not a field of the transaction, and the note says so.
                    LogosFrame {
                        objectName: "txDetailRecordedCard"
                        visible: txPage.recipientRecorded
                        Layout.fillWidth: true

                        contentItem: ColumnLayout {
                            spacing: Theme.spacing.tiny

                            NamedAddressRow {
                                objectName: "txDetailRecordedToRow"
                                label: "Recorded recipient"
                                address: txPage.rec.to || ""
                                onCopied: function (v) { root.lastCopiedValue = v }
                            }
                            LogosText {
                                objectName: "txDetailRecordedNote"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText
                                text: "This wallet's own record of the address it was asked to pay. "
                                      + "The receipt has not been read yet, so nothing here was "
                                      + "decoded off the chain."
                            }
                        }
                    }

                    LogosText {
                        text: "Fee"
                        font.pixelSize: Theme.typography.subtitleText
                        font.weight: Theme.typography.weightMedium
                    }

                    LogosFrame {
                        objectName: "txDetailFeeCard"
                        Layout.fillWidth: true

                        contentItem: ColumnLayout {
                            spacing: Theme.spacing.small

                            // Every figure in this card carries its exact string on a copy button:
                            // the row is bounded to five places, and five places is where a fee
                            // and its ceiling stop being different numbers.
                            DetailRow {
                                objectName: "txDetailFeeRow"
                                label: "Network fee"
                                value: root.txFee(txPage.rec, txPage.feesCollide)
                                copyValue: root.exactOf(txPage.rec.feeWeiExact)
                                onCopied: function (v) { root.lastCopiedValue = v }
                            }
                            // Settled rows only. While pending, "Network fee" IS the ceiling, and
                            // printing the same number twice under two labels says nothing.
                            RowDivider { visible: txPage.feeCeilingShown }
                            DetailRow {
                                objectName: "txDetailCeilingRow"
                                visible: txPage.feeCeilingShown
                                label: "Fee ceiling"
                                value: root.txCeiling(txPage.rec, txPage.feesCollide)
                                copyValue: root.exactOf(txPage.rec.feeCeilingWeiExact)
                                onCopied: function (v) { root.lastCopiedValue = v }
                            }
                            RowDivider {}
                            DetailRow {
                                objectName: "txDetailGasUsedRow"
                                label: "Gas used"
                                value: root.txGasUsed(txPage.rec, txPage.det)
                            }
                            RowDivider {}
                            DetailRow {
                                objectName: "txDetailGasPriceRow"
                                label: "Gas price"
                                value: root.perGas(txPage.rec.effectiveGasPriceDisplay,
                                                   txPage.rec.gasPriceUnit)
                                copyValue: root.exactOf(txPage.rec.effectiveGasPriceExact)
                                onCopied: function (v) { root.lastCopiedValue = v }
                            }
                            RowDivider {}
                            DetailRow {
                                objectName: "txDetailPriorityRow"
                                label: "Max priority fee"
                                value: root.perGas(txPage.tip.maxPriorityFeePerGasDisplay,
                                                   txPage.rec.gasPriceUnit)
                                copyValue: root.exactOf(txPage.tip.maxPriorityFeePerGasExact)
                                onCopied: function (v) { root.lastCopiedValue = v }
                            }
                            RowDivider { visible: txPage.rec.totalWeiExact !== undefined }
                            // Native sends only, and CONFIRMED ones only: a token amount and a
                            // native fee do not add up, and a failed transaction moved the fee
                            // alone. The backend omits the total in both cases and this row with it.
                            DetailRow {
                                objectName: "txDetailTotalRow"
                                visible: txPage.rec.totalWeiExact !== undefined
                                label: "Total amount"
                                value: (txPage.rec.totalWeiExact !== undefined ? txPage.rec.totalWeiExact : "—")
                                       + " " + (txPage.rec.nativeSymbol !== undefined ? txPage.rec.nativeSymbol : "")
                                copyValue: root.exactOf(txPage.rec.totalWeiExact)
                                onCopied: function (v) { root.lastCopiedValue = v }
                            }

                            // The rows above that a receipt cannot fill, read on demand. Not the
                            // header's refresh icon: that re-reads the receipt, which is a
                            // different question with a different answer.
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacing.small
                                LogosButton {
                                    objectName: "txDetailFetchButton"
                                    Layout.fillWidth: true
                                    text: root.txDetailsLoading ? "Fetching…"
                                          : (txPage.detailsError.length > 0 ? "Try again"
                                                                            : "Fetch block details")
                                    enabled: root.ready && !root.txDetailsLoading
                                             && txPage.rec.blockNumber !== undefined
                                             && !txPage.detailsComplete
                                    onClicked: root.backend.fetchTxDetails(txPage.hash)
                                }
                                // One spinner, on the control that was pressed. The rows it will
                                // fill keep their em-dashes: four spinners for one action read as
                                // four things going wrong at once.
                                LogosSpinner {
                                    objectName: "txDetailFetchSpinner"
                                    implicitWidth: 18
                                    implicitHeight: 18
                                    visible: root.txDetailsLoading
                                    running: visible
                                    ringColor: Theme.palette.textSecondary
                                }
                            }

                            LogosText {
                                objectName: "txDetailFetchNote"
                                visible: txPage.rec.blockNumber === undefined
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText
                                text: "There is no block to read yet — this transaction has not "
                                      + "been mined."
                            }

                            LogosText {
                                objectName: "txDetailFetchError"
                                visible: txPage.detailsError.length > 0
                                Layout.fillWidth: true
                                // The backend's own words, so no rule about them lives here.
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                                color: Theme.palette.error
                                font.pixelSize: Theme.typography.secondaryText
                                text: txPage.detailsError
                            }
                        }
                    }
                }
            }
        }
    }

    // ── networks ──────────────────────────────────────────────────────────────────
    // Which networks this portfolio includes, and whether each is routed through verification.
    //
    // This was a popup with three links in it. A dialog whose whole content is links to
    // other places is a click in front of each of them, so the places are the screens now
    // and the popup is gone.
    Component {
        id: networksComponent

        Item {
            objectName: "networksPage"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacing.medium
                spacing: Theme.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    HoverIcon {
                        objectName: "networksBack"
                        size: 32
                        iconSize: 20
                        iconSource: root.iconArrowLeft
                        onClicked: root.back()
                    }
                    LogosText { text: "Networks"; font.pixelSize: 20 }
                    Item { Layout.fillWidth: true }
                }

                LogosText {
                    objectName: "rpcSettingsNote"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    color: Theme.palette.textSecondary
                    text: "These are the networks in the device-wide portfolio scope. "
                          + "Enablement, scope, endpoints and verified routing are managed "
                          + "in Ethereum RPC."
                }
                LogosButton {
                    objectName: "openRpcSettingsButton"
                    text: "Change network settings"
                    onClicked: root.askFor("evm.rpc.configure",
                                           "Nothing on this device offers to change them.")
                }
                LogosText {
                    objectName: "settingsIntentNote"
                    Layout.fillWidth: true
                    visible: root.intentNote.length > 0
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Theme.palette.textSecondary
                    text: root.intentNote
                }

                LogosText {
                    visible: root.mainnetChains.length > 0
                    text: "Mainnets"
                    color: Theme.palette.textSecondary
                }
                Repeater {
                    model: root.mainnetChains
                    delegate: RowLayout {
                        objectName: "walletNetworkRow_" + modelData.chainId
                        required property var modelData
                        Layout.fillWidth: true
                        LogosText {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: modelData.name + " · " + modelData.chainId
                        }
                        LogosBadge {
                            objectName: "walletNetworkVerification_" + modelData.chainId
                            text: root.verificationText(modelData)
                            color: root.verificationColor(modelData)
                        }
                    }
                }

                LogosText {
                    visible: root.testnetChains.length > 0
                    text: "Testnets"
                    color: Theme.palette.textSecondary
                }
                Repeater {
                    model: root.testnetChains
                    delegate: RowLayout {
                        objectName: "walletNetworkRow_" + modelData.chainId
                        required property var modelData
                        Layout.fillWidth: true
                        LogosText {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: modelData.name + " · " + modelData.chainId
                        }
                        LogosBadge {
                            objectName: "walletNetworkVerification_" + modelData.chainId
                            text: root.verificationText(modelData)
                            color: root.verificationColor(modelData)
                        }
                    }
                }
                LogosText {
                    objectName: "walletNetworksEmpty"
                    visible: root.networks.length === 0
                    text: "No networks are currently in scope."
                    color: Theme.palette.textSecondary
                }
                Item { Layout.fillHeight: true }
            }
        }
    }

    // The address book, and the ONE place it is edited. The Send picker offers these rows
    // and can do nothing else to them: a control that both selects a recipient and deletes
    // one is a control where a mis-tap during a transaction costs a saved address.
    Component {
        id: addressBookComponent

        Item {
            objectName: "addressBookPage"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacing.medium
                spacing: Theme.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    HoverIcon {
                        objectName: "addressBookBack"
                        size: 32
                        iconSize: 20
                        iconSource: root.iconArrowLeft
                        onClicked: root.back()
                    }
                    LogosText { text: "Address book"; font.pixelSize: 20 }
                    Item { Layout.fillWidth: true }
                }

                // These are COUNTERPARTIES. Saying so is worth a line: a user who reads this
                // as "my accounts" would look here for one and conclude it had been lost.
                LogosText {
                    objectName: "addressBookNote"
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Theme.palette.textSecondary
                    text: "Names for addresses you send to. Your own accounts are managed in "
                          + "the Keystore app and are always offered alongside these."
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.tiny
                    LogosTextField {
                        id: bookNewName
                        objectName: "bookNewName"
                        Layout.preferredWidth: 160
                        placeholderText: "Name (optional)"
                    }
                    LogosTextField {
                        id: bookNewAddress
                        objectName: "bookNewAddress"
                        Layout.fillWidth: true
                        placeholderText: "Address (0x…)"
                    }
                    // Armed by an address alone: a name is optional, because an address worth
                    // remembering is worth remembering before its owner has one.
                    LogosButton {
                        objectName: "bookAdd"
                        text: "Add"
                        enabled: root.ready && bookNewAddress.text.trim().length > 0
                        onClicked: {
                            root.backend.saveContact(bookNewAddress.text.trim(),
                                                     bookNewName.text.trim())
                            bookNewAddress.text = ""
                            bookNewName.text = ""
                        }
                    }
                }

                // The backend's own words. This view does not parse an address, so a refusal
                // has to come from the party that does, and be shown as it was given.
                LogosText {
                    objectName: "bookError"
                    Layout.fillWidth: true
                    visible: root.ready && root.backend.contactsError.length > 0
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Theme.palette.error
                    text: root.ready ? root.backend.contactsError : ""
                }

                LogosText {
                    objectName: "bookEmpty"
                    Layout.fillWidth: true
                    visible: root.contacts.length === 0
                    textFormat: Text.PlainText
                    color: Theme.palette.textSecondary
                    text: "No saved addresses yet."
                }

                LogosListView {
                    objectName: "bookList"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.contacts
                    delegate: LogosFrame {
                        id: bookRow
                        width: ListView.view.width
                        // Held, not read through `modelData` from a handler: the model is a
                        // plain array and a row's index moves when an earlier one is forgotten.
                        readonly property var contact: modelData

                        // READ-ONLY until asked. A name that is always an open field is a name
                        // one stray keystroke rewrites, and this list is what a user checks a
                        // recipient against — so editing is a mode you enter, confirm or
                        // abandon, and leaving the screen abandons it.
                        property bool editing: false

                        function beginEdit() {
                            bookNameField.text = bookRow.contact.name
                            bookRow.editing = true
                            bookNameField.textInput.forceActiveFocus()
                        }
                        function confirmEdit() {
                            var name = bookNameField.text.trim()
                            bookRow.editing = false
                            // Unchanged is not a write. The backend would accept it happily,
                            // but a re-read that moves nothing still rebuilds this list under
                            // the pointer.
                            if (name !== bookRow.contact.name)
                                root.backend.saveContact(bookRow.contact.address, name)
                        }
                        function cancelEdit() {
                            bookNameField.text = bookRow.contact.name
                            bookRow.editing = false
                        }

                        // A frame, because the name and the address are one thing: without it
                        // the address reads as orphaned rather than as what the name is for.
                        contentItem: ColumnLayout {
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacing.tiny

                                LogosText {
                                    objectName: "bookName_" + index
                                    Layout.fillWidth: true
                                    visible: !bookRow.editing
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    text: bookRow.contact.name.length > 0
                                          ? bookRow.contact.name : "Unnamed"
                                    // Dimmed when it is the placeholder rather than a name, so
                                    // "Unnamed" cannot be mistaken for what someone called it.
                                    color: bookRow.contact.name.length > 0
                                           ? Theme.palette.text : Theme.palette.textTertiary
                                }
                                LogosTextField {
                                    id: bookNameField
                                    objectName: "bookNameField_" + index
                                    Layout.fillWidth: true
                                    visible: bookRow.editing
                                    text: modelData.name
                                    placeholderText: "Name"
                                }

                                HoverIcon {
                                    objectName: "bookEdit_" + index
                                    visible: !bookRow.editing
                                    size: 32
                                    iconSize: 16
                                    iconSource: Qt.resolvedUrl("assets/edit.svg")
                                    ToolTip.text: "Rename"
                                    ToolTip.visible: hovered
                                    ToolTip.delay: 400
                                    onClicked: bookRow.beginEdit()
                                }
                                HoverIcon {
                                    objectName: "bookConfirm_" + index
                                    visible: bookRow.editing
                                    size: 32
                                    iconSize: 16
                                    iconSource: LogosIcons.check
                                    ToolTip.text: "Confirm"
                                    ToolTip.visible: hovered
                                    ToolTip.delay: 400
                                    onClicked: bookRow.confirmEdit()
                                }
                                HoverIcon {
                                    objectName: "bookCancel_" + index
                                    visible: bookRow.editing
                                    size: 32
                                    iconSize: 16
                                    iconSource: LogosIcons.close
                                    ToolTip.text: "Cancel"
                                    ToolTip.visible: hovered
                                    ToolTip.delay: 400
                                    onClicked: bookRow.cancelEdit()
                                }

                                // Copying and forgetting are about the ADDRESS, which editing a
                                // name does not touch — but they leave while a rename is open
                                // so the row offers one decision at a time.
                                LogosCopyButton {
                                    // Named like the two buttons beside it in the address book row, which had one
                                    // each while this had none — the only unlabelled control in the group.
                                    ToolTip.text: "Copy"
                                    ToolTip.visible: hovered
                                    ToolTip.delay: 400
                                    objectName: "bookCopy_" + index
                                    visible: !bookRow.editing
                                    value: bookRow.contact.address
                                    onCopied: function (v) { root.lastCopiedValue = v }
                                }
                                HoverIcon {
                                    objectName: "bookForget_" + index
                                    visible: !bookRow.editing
                                    size: 32
                                    iconSize: 16
                                    iconSource: root.iconTrash
                                    ToolTip.text: "Forget"
                                    ToolTip.visible: hovered
                                    ToolTip.delay: 400
                                    onClicked: root.backend.forgetContact(bookRow.contact.address)
                                }
                            }

                            // Enter confirms and Escape abandons, because a field with two
                            // buttons beside it is still a field people press Enter in.
                            Connections {
                                target: bookNameField.textInput
                                function onAccepted() { bookRow.confirmEdit() }
                            }
                            Keys.onEscapePressed: if (bookRow.editing) bookRow.cancelEdit()

                            // IN FULL, and indented to the field's own text rather than the
                            // frame's edge, so it sits under the name instead of beside it.
                            LogosSelectableText {
                                objectName: "bookAddress_" + index
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.spacing.small
                                text: bookRow.contact.address
                                color: Theme.palette.textSecondary
                                font.family: Theme.typography.mono
                                font.pixelSize: Theme.typography.secondaryText
                                wrapMode: Text.WrapAnywhere
                            }
                        }
                    }
                }
            }
        }
    }

   // ── another app asks to send ─────────────────────────────────────────────────
    //
    // What the app handed over, in full, before anything is asked of the signer: who asked
    // (attested by the shell), what they claim it is for, every call with its contract and
    // value, and the fee ceiling the sender priced. Declining answers the app `cancelled`;
    // sending makes it the wallet's own pending send, and the app hears the outcome.
    Kit.TxReviewDialog {
        objectName: "intentSendDialog"
        title: "An app asks to send"
        prefix: "intentSend"
        width: 480
        visible: root.intentSendOpen
        readonly property var fee: root.intentSend.fee !== undefined ? root.intentSend.fee : ({})
        quote: fee
        nativeSymbol: root.nativeSymbol
        pricing: root.intentSendPricing
        feeError: root.intentSend.feeError !== undefined ? String(root.intentSend.feeError) : ""
        rows: [
            { name: "intentSendRequester", label: "Asked by",
              value: root.intentSend.requester !== undefined && String(root.intentSend.requester).length
                     ? String(root.intentSend.requester) : "an app the shell did not name" },
            { name: "intentSendPurpose", label: "Purpose (claimed)",
              value: root.intentSend.purpose !== undefined ? String(root.intentSend.purpose) : "" },
            { name: "intentSendFrom", label: "From", mono: true, value: root.namedAddr(root.intentSend.from || "") },
            { name: "intentSendNetwork", label: "Network", value: root.networkNameFor(root.intentSend.chainId) }
        ].concat(fee.valueWeiDisplay !== undefined
                 ? [{ name: "intentSendValue", label: "Ether sent", value: fee.valueWeiDisplay + " " + (fee.nativeSymbol || root.nativeSymbol) }]
                 : [])
        callList: root.intentSend.calls !== undefined ? root.intentSend.calls : []
        showCallData: true
        nameOf: root.namedAddr
        note: "The signer asks once for all of them. Nothing is sent until it says yes, and the app is told how it ended."
        error: root.intentSend.sendError !== undefined ? String(root.intentSend.sendError) : ""
        cancelText: "Decline"
        confirmText: root.intentSend.chainId !== undefined ? "Send on " + root.networkNameFor(root.intentSend.chainId) : "Send"
        confirmEnabled: root.ready && !root.sendPending && !root.intentSendPricing
        onCancelled: {
            root.backend.declineIntentSend()
            root.answerIntent(false, ({}), "cancelled")
        }
        onConfirmed: root.backend.acceptIntentSend()
    }

    // ── review, before anything is asked of the sender ────────────────────────────
    //
    // What the signer will be asked to approve, in the wallet's own terms, with the fee
    // ceiling and the nonce. Confirm is the old Send: a refusal stays here, beside its reason.
    Kit.TxReviewDialog {
        id: sendReview
        objectName: "sendReviewDialog"
        title: "Review send"
        prefix: "sendReview"
        readonly property var sq: sendForm.q.ok === true ? sendForm.q : ({})
        quote: sq
        tier: tierGroup.tier
        nativeSymbol: root.nativeSymbol
        rows: root.transferRows(sq, "sendReview", root.networkLabel())
        callList: root.transferCalls(sq)
        nameOf: root.namedAddr
        error: root.ready ? root.backend.sendError : ""
        confirmText: "Confirm send"
        busy: root.sendSubmitting
        confirmEnabled: root.ready && !root.sendPending && sendForm.q.ok === true
        onConfirmed: {
            root.sendSubmitting = true
            root.backend.submitSend(sendForm.formRequest)
        }
        onCancelled: close()
    }

    // ── a stuck nonce's resend, reviewed ─────────────────────────────────────────
    //
    // The same transfer, pinned to the nonce holding the queue up, at fees a node takes as its
    // replacement. Confirm goes out through submitSend, like any send.
    Kit.TxReviewDialog {
        objectName: "resendReviewDialog"
        title: "Resend with current fees"
        prefix: "resendReview"
        readonly property var rq: root.resendReview.quote !== undefined ? root.resendReview.quote : ({})
        visible: root.ready && root.resendReview.request !== undefined
        quote: rq
        tier: "normal"
        nativeSymbol: root.nativeSymbol
        rows: root.transferRows(rq, "resendReview", root.networkNameFor(rq.chainId))
        callList: root.transferCalls(rq)
        nameOf: root.namedAddr
        error: root.ready ? root.backend.sendError : ""
        confirmText: "Resend"
        busy: root.sendSubmitting
        confirmEnabled: root.ready && !root.sendPending
        onConfirmed: {
            root.sendSubmitting = true
            root.resendSubmitted = true
            root.backend.submitSend(JSON.stringify(root.resendReview.request))
        }
        onCancelled: root.backend.dismissResend()
    }

    // ── pending approval ──────────────────────────────────────────────────────────
    LogosDialog {
        objectName: "pendingDialog"
        title: "Waiting for approval"
        anchors.centerIn: parent
        visible: root.sendPending
        contentItem: ColumnLayout {
            LogosText {
                objectName: "pendingLabel"
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                // The note only appears when nobody was taken there — the normal path hands
                // the user to the signer, so this dialog is behind them while they decide.
                text: root.approvalNote.length > 0
                      ? root.approvalNote
                      : "Waiting for this transaction to be approved."
            }
            LogosButton {
                objectName: "cancelSendButton"
                text: "Cancel send"
                onClicked: root.backend.cancelSend()
            }
        }
    }

    // ── what the last send came to ────────────────────────────────────────────────
    //
    // Not decoration. Answering an intent returns the user to this app, and the waiting
    // dialog closes in the same turn — without something taking its place the shell appears
    // to have moved them for no reason. This is the one part of the round trip the shell
    // cannot do: it knows the request finished, not what finishing meant here.
    LogosDialog {
        objectName: "sendOutcomeDialog"
        // `stuck` is a broadcast that never answered: it may be on chain, so never "Not sent".
        title: root.sendOutcome.status === "broadcast" ? "Sent"
             : root.sendOutcome.status === "stuck" ? "Not confirmed" : "Not sent"
        anchors.centerIn: parent
        visible: root.showOutcome
        contentItem: ColumnLayout {
            LogosText {
                objectName: "sendOutcomeLabel"
                Layout.maximumWidth: 420
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: {
                    var o = root.sendOutcome
                    if (o.status === "broadcast") return "Sent to the network."
                    if (o.status === "rejected")  return "The signer rejected this transaction."
                    if (o.status === "cancelled") return "This send was cancelled."
                    if (o.reason !== undefined && o.reason.length) return o.reason
                    return "This send did not go out."
                }
            }
            // The hash is the receipt, so it is copyable here exactly as the address is in
            // the header: shortened for reading, whole on the clipboard. A truncated hash a
            // user retypes is worse than none.
            RowLayout {
                objectName: "sendOutcomeHashRow"
                visible: root.outcomeHash.length > 0
                spacing: Theme.spacing.small
                LogosSelectableText {
                    objectName: "sendOutcomeHash"
                    text: root.shortHash(root.outcomeHash)
                    color: Theme.palette.textSecondary
                    font.family: Theme.typography.mono
                }
                LogosCopyButton {
                    // Named like the two buttons beside it in the address book row, which had one
                    // each while this had none — the only unlabelled control in the group.
                    ToolTip.text: "Copy"
                    ToolTip.visible: hovered
                    ToolTip.delay: 400
                    objectName: "sendOutcomeCopyButton"
                    value: root.outcomeHash
                    onCopied: function (v) { root.lastCopiedValue = v }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosButton {
                    objectName: "sendOutcomeDismiss"
                    text: "Done"
                    onClicked: root.dismissOutcome()
                }
                Item { Layout.fillWidth: true }
                // Only once the row is actually in history. `openTxDetail` refuses a hash it
                // cannot find and refuses it SILENTLY, so an always-enabled button would
                // close the receipt and go nowhere — and this is the one moment the row is
                // still arriving, because the send settled a beat ago.
                LogosButton {
                    objectName: "sendOutcomeViewTx"
                    visible: root.outcomeHash.length > 0
                    enabled: root.txByHash(root.outcomeHash) !== null
                    text: "View transaction"
                    onClicked: {
                        var h = root.outcomeHash
                        root.dismissOutcome()
                        root.openTxDetail(h)
                    }
                }
            }
        }
    }

}
