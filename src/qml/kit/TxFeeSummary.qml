import QtQuick 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "fees.js" as Fees

// What a quote priced, where the send is composed: the ceiling, the gas limit and fee per gas,
// the nonce, and where the figures came from. `quote` is tx_sender's `prepare` reply.
ColumnLayout {
    id: summary
    property var quote: ({})
    property string tier: "normal"
    property string nativeSymbol: ""
    property int calls: 1

    readonly property var q: quote ? quote : ({})
    readonly property bool priced: q.maxFeePerGas !== undefined && q.maxFeePerGas !== null
    readonly property var nonces: Fees.nonces(q, calls)

    Layout.fillWidth: true
    spacing: Theme.spacing.small

    DetailRow {
        objectName: "feeRow"
        label: "Network fee"
        value: Fees.ceiling(summary.q, summary.tier, summary.nativeSymbol) || "—"
    }
    LogosText {
        objectName: "feeErrorLabel"
        visible: text.length > 0
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: Theme.palette.error
        text: summary.q.ok === false && summary.q.error ? "Fee: " + summary.q.error : ""
    }
    DetailRow {
        objectName: "gasLimitRow"
        visible: summary.priced
        label: summary.calls > 1 ? "Gas limits" : "Gas limit"
        value: Fees.gasLimits(summary.q).join(" + ")
    }
    DetailRow {
        objectName: "maxFeeRow"
        visible: summary.priced
        label: "Max fee"
        value: Fees.gwei(summary.q.maxFeePerGas) + " gwei"
    }
    DetailRow {
        objectName: "priorityFeeRow"
        visible: summary.priced
        label: "Priority fee"
        value: Fees.gwei(summary.q.maxPriorityFeePerGas) + " gwei"
    }
    DetailRow {
        objectName: "nonceRow"
        visible: summary.nonces.length > 0
        label: summary.calls > 1 ? "Nonces" : "Nonce"
        value: summary.nonces.join(", ") + (summary.q.replaces ? " · replaces a pending transaction" : "")
    }
    LogosText {
        objectName: "feeSourceLabel"
        visible: text.length > 0
        textFormat: Text.PlainText
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
        text: summary.priced && summary.q.feeSource ? "Fee basis: " + summary.q.feeSource : ""
    }
}
