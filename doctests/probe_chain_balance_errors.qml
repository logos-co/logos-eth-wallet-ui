// One failed chain remains one failed chain: successful balances stay visible, while every
// token on the failed chain gets an error symbol whose hover text says what happened. The
// same state is preserved on token detail, and verification is reported per chain only on
// Settings > Networks — never as an aggregate claim in the header.
import QtQuick

Item {
    id: probe
    width: 1100
    height: 800

    property int failures: 0
    readonly property string me: "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"

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
    function shown(name) {
        var o = find(view.item, name)
        return o ? o.visible : "<absent>"
    }

    readonly property string networks: JSON.stringify([
        { chainId: 1, name: "Ethereum", nativeSymbol: "ETH", testnet: false,
          enabled: true, inScope: true, verifiedProxyMode: "required",
          verifiedProxy: { mode: "required", state: "ready", usable: true } },
        { chainId: 11155111, name: "Sepolia", nativeSymbol: "ETH", testnet: true,
          enabled: true, inScope: true, verifiedProxyMode: "off",
          verifiedProxy: { mode: "off", state: "disabled", usable: true } }
    ])
    readonly property string tokens: JSON.stringify([
        { chainId: 1, network: "Ethereum", symbol: "ETH", name: "Ether", decimals: 18,
          native: true, testnet: false },
        { chainId: 11155111, network: "Sepolia", symbol: "ETH", name: "Sepolia Ether",
          decimals: 18, native: true, testnet: true }
    ])
    readonly property string balances: JSON.stringify([
        { chainId: 1, network: "Ethereum", symbol: "ETH", native: true,
          display: "1.25", exact: "1.25", route: "verified" },
        { chainId: 11155111, network: "Sepolia", testnet: true, blocked: true,
          error: "endpoint timed out" }
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
        property string verifiedProxyJson: JSON.stringify({ mode: "required", state: "ready",
                                                            usable: true, blocking: false })
        property string accountsJson: JSON.stringify([probe.me])
        property string selectedAccount: probe.me
        property string accountLabelsJson: "{}"
        property string accountWalletsJson: "{}"
        property string contactsJson: "[]"
        property string contactsError: ""
        property string balancesJson: probe.balances
        property string balancesRoute: "verified"
        property string tokensJson: probe.tokens
        property string tokenSort: "alpha"
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
        property string pendingApprovalHandle: ""
        property string lastSendOutcomeJson: ""
        property string intentSendJson: ""
        property bool intentSendPricing: false
        function refresh() {}
        function chooseTokenSort(order) {}
        function refreshVerifiedProxy() {}
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
                console.log("one chain answered and the other failed")
                check("the successful figure stays", find(view.item, "balance_1:native").text, "1.25")
                check("it has no error symbol", shown("balanceError_1:native"), false)
                check("the failed figure is hidden", shown("balance_11155111:native"), false)
                check("the failed chain has an error symbol", shown("balanceError_11155111:native"), true)
                check("the symbol carries the explanation",
                      find(view.item, "balanceError_11155111:native").description,
                      "Sepolia balances unavailable: endpoint timed out")
                check("there is no detached failure banner", find(view.item, "balanceFailuresFrame"), null)
                check("the header says scope only", find(view.item, "chainChip").text,
                      "MAINNETS + TESTNETS")
                check("the header makes no aggregate verification claim",
                      find(view.item, "verifiedChip"), null)

                view.item.openTokenDetail("11155111:native")
            } else if (probe.phase === 2) {
                console.log("")
                console.log("the token detail preserves the same failure")
                check("detail amount is hidden", shown("tokenDetailBalance"), false)
                check("detail error is visible", shown("tokenDetailBalanceError"), true)
                check("detail error carries the explanation",
                      find(view.item, "tokenDetailBalanceError").description,
                      "Sepolia balances unavailable: endpoint timed out")
                view.item.openNetworks()
            } else {
                console.log("")
                console.log("verification is reported per in-scope network")
                check("Ethereum is listed", find(view.item, "walletNetworkRow_1") !== null, true)
                check("Ethereum's state is local to its row",
                      find(view.item, "walletNetworkVerification_1").text,
                      "Verification on · ready")
                check("Sepolia is listed", find(view.item, "walletNetworkRow_11155111") !== null, true)
                check("Sepolia's state is local to its row",
                      find(view.item, "walletNetworkVerification_11155111").text,
                      "Verification off")
                check("there is no wallet-owned scope selector",
                      find(view.item, "walletNetworkScopePicker"), null)
                check("there is no wallet-owned enable switch",
                      find(view.item, "walletChainEnabled_1"), null)
                check("the Ethereum RPC handoff remains",
                      find(view.item, "openRpcSettingsButton").text, "Change network settings")

                console.log("")
                console.log("RESULT: " + (probe.failures ? probe.failures + " FAILED" : "ALL PASS"))
                Qt.exit(probe.failures ? 1 : 0)
            }
        }
    }

    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/EthWalletView.qml")
}
