import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// The Ethereum wallet.
//
// Information design follows MetaMask: one question per screen, everything else behind a
// disclosure. Two tabs, one action, and the active network visible at all times — a user must
// never be able to mistake which chain they are spending on.
//
// This view holds no secret. It requests signatures and reads which accounts exist; the vault
// password is taken only by signer_ui, and seed phrases only ever reach keystore_ui.
//
// Rendering rule: every item showing a string this view did not author sets
// `textFormat: Text.PlainText`. LogosText is a bare Text with no textFormat, i.e. Qt's AutoText
// HTML autodetection — an account label or an error message containing markup would otherwise
// render as markup.
Item {
    id: root
    anchors.fill: parent

    // Paint the surface. Without this the QQuickWidget's white clear colour shows through and
    // LogosText's default (light) colour renders white-on-white.
    Rectangle { anchors.fill: parent; color: Theme.palette.background }

    readonly property var backend: logos.module("eth_wallet_ui")

    // Must be a writable property fed by the signal, NOT a binding: a binding containing a
    // function call evaluates once at creation, before ui-host has finished handing over, and
    // then latches false forever.
    property bool ready: false

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "eth_wallet_ui") root.ready = isReady && root.backend !== null
        }
    }

    function j(text, fallback) {
        try { return JSON.parse(text && text.length ? text : fallback) }
        catch (e) { return JSON.parse(fallback) }
    }

    readonly property var net: ready ? j(backend.activeNetworkJson, "{}") : ({})
    readonly property var networks: ready ? j(backend.networksJson, "[]") : []
    readonly property var accounts: ready ? j(backend.accountsJson, "[]") : []
    readonly property var tokens: ready ? j(backend.tokensJson, "[]") : []
    readonly property var history: ready ? j(backend.historyJson, "[]") : []
    readonly property var fees: ready ? j(backend.feeTiersJson, "{}") : ({})
    readonly property var quote: ready ? j(backend.quoteJson, "{}") : ({})
    readonly property var sendState: ready ? j(backend.sendStatusJson, "{}") : ({})

    // Empty means "not read yet" — rendered as an em-dash, never as a zero and never as the
    // previous network's number.
    readonly property bool balancesKnown: ready && backend.balancesJson.length > 0
    readonly property var balances: balancesKnown ? j(backend.balancesJson, "[]") : []

    readonly property string netName: net.name !== undefined ? net.name : ""
    readonly property bool isTestnet: net.testnet === true
    readonly property bool sendPending: ready && backend.pendingRequestId.length > 0

    // qt-mcp cannot click a TabButton, so the harness drives tabs through this.
    function selectTab(i) { tabs.currentIndex = i; pages.currentIndex = i }

    function shortAddr(a) {
        if (!a || a.length < 12) return a || ""
        return a.substring(0, 6) + "…" + a.substring(a.length - 4)
    }

    function amountOf(sym) {
        for (var i = 0; i < balances.length; ++i)
            if (balances[i].symbol === sym) {
                var raw = balances[i].raw
                if (!raw || raw.length === 0) return "—"
                // 18 decimals, trimmed. Display only; every calculation stays in the backend.
                var s = raw.length > 18 ? raw : ("0".repeat(19 - raw.length) + raw)
                var whole = s.substring(0, s.length - 18)
                var frac = s.substring(s.length - 18, s.length - 14)
                return whole + "." + frac
            }
        return "—"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.medium
        spacing: Theme.spacing.small

        // ── header: account, address, and the chain chip that is always on screen ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            LogosComboBox {
                id: accountPicker
                objectName: "accountPicker"
                Layout.preferredWidth: 220
                model: root.accounts
                enabled: root.ready && root.accounts.length > 0
                onActivated: if (root.ready) root.backend.selectAccount(root.accounts[currentIndex])
            }

            LogosText {
                objectName: "addressLabel"
                textFormat: Text.PlainText
                text: root.ready ? root.shortAddr(root.backend.selectedAccount) : ""
                color: Theme.palette.textSecondary
            }

            Item { Layout.fillWidth: true }

            // The active network, on every tab. Testnets are visually distinct so mainnet
            // cannot be mistaken for one.
            LogosBadge {
                objectName: "chainChip"
                text: root.isTestnet
                      ? root.netName.toUpperCase() + " · TESTNET"
                      : root.netName.toUpperCase()
                color: root.isTestnet ? Theme.palette.accentOrange : Theme.palette.success
            }

            LogosButton {
                objectName: "settingsButton"
                text: "Settings"
                onClicked: settingsDialog.open()
            }
        }

        LogosText {
            objectName: "errorLabel"
            Layout.fillWidth: true
            visible: root.ready && root.backend.lastError.length > 0
            // Backend-authored; may contain anything.
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Theme.palette.danger
            text: root.ready ? root.backend.lastError : ""
        }

        // ── balance + the one action ──
        LogosText {
            objectName: "primaryBalance"
            Layout.alignment: Qt.AlignHCenter
            textFormat: Text.PlainText
            font.pixelSize: 34
            text: root.amountOf(root.net.nativeSymbol !== undefined ? root.net.nativeSymbol : "ETH")
                  + " " + (root.net.nativeSymbol !== undefined ? root.net.nativeSymbol : "")
        }

        LogosButton {
            objectName: "openSendButton"
            Layout.alignment: Qt.AlignHCenter
            text: "Send"
            enabled: root.ready && !root.sendPending
            onClicked: sendDialog.open()
        }

        // ── two tabs ──
        LogosTabBar {
            id: tabs
            objectName: "tabs"
            Layout.fillWidth: true
            onCurrentIndexChanged: pages.currentIndex = currentIndex
            LogosTabButton { text: "Tokens" }
            LogosTabButton { text: "Activity" }
        }

        StackLayout {
            id: pages
            objectName: "pages"
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Tokens
            LogosListView {
                objectName: "tokenList"
                model: root.tokens
                delegate: RowLayout {
                    width: ListView.view ? ListView.view.width : 0
                    LogosText {
                        textFormat: Text.PlainText
                        text: modelData.symbol + "  " + modelData.name
                    }
                    Item { Layout.fillWidth: true }
                    LogosText {
                        objectName: "balance_" + modelData.symbol
                        textFormat: Text.PlainText
                        text: root.amountOf(modelData.symbol)
                    }
                }
            }

            // Activity
            Item {
                LogosText {
                    objectName: "historyEmpty"
                    anchors.centerIn: parent
                    visible: root.history.length === 0
                    text: "No transactions yet"
                    color: Theme.palette.textSecondary
                }
                LogosListView {
                    objectName: "historyList"
                    anchors.fill: parent
                    visible: root.history.length > 0
                    model: root.history
                    delegate: ColumnLayout {
                        width: ListView.view ? ListView.view.width : 0
                        LogosText {
                            textFormat: Text.PlainText
                            text: (modelData.kind === "erc20" ? "Sent token" : "Sent ETH")
                                  + " · " + modelData.status
                        }
                        LogosText {
                            textFormat: Text.PlainText
                            color: Theme.palette.textSecondary
                            text: "To: " + root.shortAddr(modelData.to)
                        }
                    }
                }
            }
        }
    }

    // ── Send ──────────────────────────────────────────────────────────────────────
    LogosDialog {
        id: sendDialog
        objectName: "sendDialog"
        title: "Send"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 520)

        function request() {
            var r = {
                from: root.backend.selectedAccount,
                to: toField.text.trim(),
                amount: amountField.text.trim(),
                tier: tierGroup.selected
            }
            if (advanced.checked) {
                if (maxFeeField.text.length) r.maxFeePerGas = maxFeeField.text.trim()
                if (maxPriorityFeeField.text.length) r.maxPriorityFeePerGas = maxPriorityFeeField.text.trim()
                if (gasLimitField.text.length) r.gasLimit = gasLimitField.text.trim()
                if (nonceField.text.length) r.nonce = parseInt(nonceField.text.trim())
            }
            return JSON.stringify(r)
        }
        function reprice() { if (root.ready && toField.text.length && amountField.text.length) root.backend.quote(request()) }

        contentItem: ColumnLayout {
            spacing: Theme.spacing.small

            LogosTextField {
                id: toField
                objectName: "toField"
                Layout.fillWidth: true
                placeholderText: "Recipient address (0x…)"
                onTextChanged: sendDialog.reprice()
            }
            LogosTextField {
                id: amountField
                objectName: "amountField"
                Layout.fillWidth: true
                placeholderText: "Amount in wei"
                onTextChanged: sendDialog.reprice()
            }

            // Fee tiers. Labelled Low / Market / Advanced after the reference; the wire names
            // stay slow/normal/fast, which is what fee_module speaks.
            RowLayout {
                id: tierGroup
                property string selected: "normal"
                spacing: Theme.spacing.tiny
                LogosButton {
                    objectName: "tierSlow"; text: "Low"
                    onClicked: { tierGroup.selected = "slow"; sendDialog.reprice() }
                }
                LogosButton {
                    objectName: "tierNormal"; text: "Market"
                    onClicked: { tierGroup.selected = "normal"; sendDialog.reprice() }
                }
                LogosButton {
                    objectName: "tierFast"; text: "Fast"
                    onClicked: { tierGroup.selected = "fast"; sendDialog.reprice() }
                }
            }

            // Where the numbers came from. A wallet quietly pricing off legacy gasPrice is how
            // an overpayment goes unnoticed, so the source is on screen rather than in a log.
            LogosText {
                objectName: "feeSourceLabel"
                textFormat: Text.PlainText
                color: Theme.palette.textSecondary
                text: root.quote.feeSource !== undefined
                      ? "Fee basis: " + root.quote.feeSource
                      : (root.fees.source !== undefined ? "Fee basis: " + root.fees.source : "")
            }

            LogosText {
                objectName: "quoteSummary"
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                text: root.quote.ok === true
                      ? "Gas limit " + root.quote.gasLimit
                        + " · max fee " + root.quote.maxFeePerGas
                        + " · nonce " + root.quote.nonce
                      : ""
            }

            LogosCheckbox {
                id: advanced
                objectName: "advancedToggle"
                text: "Advanced"
                onCheckedChanged: sendDialog.reprice()
            }

            // Prefilled from the quote, so every field shows where its value came from rather
            // than sitting empty.
            ColumnLayout {
                visible: advanced.checked
                Layout.fillWidth: true
                LogosTextField {
                    id: maxFeeField; objectName: "maxFeeField"; Layout.fillWidth: true
                    placeholderText: root.quote.maxFeePerGas !== undefined
                                     ? "Max fee per gas (suggested " + root.quote.maxFeePerGas + ")"
                                     : "Max fee per gas (wei)"
                    onTextChanged: sendDialog.reprice()
                }
                LogosTextField {
                    id: maxPriorityFeeField; objectName: "maxPriorityFeeField"; Layout.fillWidth: true
                    placeholderText: root.quote.maxPriorityFeePerGas !== undefined
                                     ? "Priority fee (suggested " + root.quote.maxPriorityFeePerGas + ")"
                                     : "Priority fee per gas (wei)"
                    onTextChanged: sendDialog.reprice()
                }
                LogosTextField {
                    id: gasLimitField; objectName: "gasLimitField"; Layout.fillWidth: true
                    placeholderText: root.quote.gasLimit !== undefined
                                     ? "Gas limit (estimated " + root.quote.gasLimit + ")"
                                     : "Gas limit"
                    onTextChanged: sendDialog.reprice()
                }
                LogosTextField {
                    id: nonceField; objectName: "nonceField"; Layout.fillWidth: true
                    placeholderText: root.quote.nonce !== undefined
                                     ? "Nonce (next is " + root.quote.nonce + ")"
                                     : "Nonce"
                    onTextChanged: sendDialog.reprice()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                LogosButton {
                    objectName: "sendCancelButton"
                    text: "Cancel"
                    onClicked: sendDialog.close()
                }
                Item { Layout.fillWidth: true }
                // Names the network, so the last click before a signature says where it lands.
                LogosButton {
                    objectName: "sendSubmitButton"
                    text: "Send on " + root.netName + (root.isTestnet ? " (testnet)" : "")
                    enabled: root.ready && !root.sendPending && root.quote.ok === true
                    onClicked: { root.backend.submitSend(sendDialog.request()); sendDialog.close() }
                }
            }
        }
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
                text: "Approve this transaction in the signer to send it."
            }
            LogosButton {
                objectName: "cancelSendButton"
                text: "Cancel send"
                onClicked: root.backend.cancelSend()
            }
        }
    }

    // ── Settings, where the network selector is deliberately buried ────────────────
    LogosDialog {
        id: settingsDialog
        objectName: "settingsDialog"
        title: "Settings"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 520)

        contentItem: ColumnLayout {
            spacing: Theme.spacing.small

            LogosText {
                textFormat: Text.PlainText
                color: Theme.palette.textSecondary
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                text: "Endpoints are shared with other Logos wallets on this device."
            }

            LogosTextField {
                id: rpcField
                objectName: "rpcUrlField"
                Layout.fillWidth: true
                placeholderText: "JSON-RPC endpoint"
                text: root.net.rpcUrl !== undefined ? root.net.rpcUrl : ""
            }
            LogosButton {
                objectName: "saveRpcButton"
                text: "Save endpoint"
                onClicked: root.backend.setRpcUrl(root.net.chainId, rpcField.text)
            }

            LogosSwitch {
                objectName: "verifiedProxySwitch"
                text: "Route through the verified proxy"
                checked: root.net.verifiedProxyMode === "required"
                onToggled: root.backend.setVerifiedProxyMode(
                               root.net.chainId, checked ? "required" : "off")
            }

            LogosText { text: "Network"; color: Theme.palette.textSecondary }
            Repeater {
                model: root.networks
                LogosButton {
                    objectName: "network_" + modelData.key
                    text: modelData.name + (modelData.testnet ? " (testnet)" : "")
                    enabled: root.ready && modelData.chainId !== root.net.chainId
                    onClicked: root.backend.setActiveChain(modelData.chainId)
                }
            }
        }
    }
}
