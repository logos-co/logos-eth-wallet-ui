import QtQuick 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "fees.js" as Fees

// The last screen before the signer: the app's own rows first, then what every send shares,
// the fee ceiling, the nonce and any replacement, and each transaction to approve. The parts a
// test finds are named `prefix` + Fee, FeeError, Nonce, Replaces, Call_<i>, CallData_<i>,
// Note, Error, Cancel and Confirm.
LogosDialog {
    id: review
    property string prefix: "review"
    // [{ label, value, name?, mono? }]
    property var rows: []
    // tx_sender's `prepare` reply for the send.
    property var quote: ({})
    // [{ label, to, value?, data? }]
    property var callList: []
    property bool showCallData: false
    property string tier: ""
    property string nativeSymbol: ""
    property bool pricing: false
    property string feeError: ""
    // How an address is shown: shortened, or by a name the app knows it by.
    property var nameOf: function (address) { return String(address || "") }
    property string note: "The signer asks once for all of them. Nothing is sent until it says yes."
    property string error: ""
    property string cancelText: "Back"
    property string confirmText: "Confirm"
    property bool confirmEnabled: true
    property bool busy: false
    signal confirmed()
    signal cancelled()

    readonly property var q: quote ? quote : ({})
    readonly property var nonces: Fees.nonces(q, Math.max(1, callList.length))

    anchors.centerIn: parent
    width: 460

    contentItem: ColumnLayout {
        spacing: Theme.spacing.small

        Repeater {
            model: review.rows
            DetailRow {
                objectName: modelData.name || ""
                label: modelData.label || ""
                value: modelData.value !== undefined && modelData.value !== null ? String(modelData.value) : ""
                mono: modelData.mono === true
            }
        }
        DetailRow {
            objectName: review.prefix + "Fee"
            label: "Network fee"
            value: review.pricing ? "Pricing…" : (Fees.ceiling(review.q, review.tier, review.nativeSymbol) || "—")
        }
        LogosText {
            objectName: review.prefix + "FeeError"
            visible: review.feeError.length > 0
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Theme.palette.error
            text: "Fee: " + review.feeError
        }
        DetailRow {
            objectName: review.prefix + "Nonce"
            visible: review.nonces.length > 0
            label: review.nonces.length > 1 ? "Nonces" : "Nonce"
            value: review.nonces.join(", ")
        }
        LogosText {
            objectName: review.prefix + "Replaces"
            visible: text.length > 0
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Theme.palette.warning
            text: Fees.replacesText(review.q)
        }
        LogosText {
            visible: review.callList.length > 0
            text: "Transactions to approve"
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }
        Repeater {
            model: review.callList
            ColumnLayout {
                id: call
                Layout.fillWidth: true
                spacing: 0
                readonly property string wei: modelData.value !== undefined ? String(modelData.value) : ""
                LogosText {
                    objectName: review.prefix + "Call_" + index
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    text: (index + 1) + ". " + (modelData.label || modelData.kind || "") + " · "
                          + review.nameOf(modelData.to)
                          + (call.wei.length && !/^(0x)?0*$/.test(call.wei) ? " · carries ether" : "")
                }
                LogosText {
                    objectName: review.prefix + "CallData_" + index
                    visible: review.showCallData && modelData.data !== undefined && String(modelData.data).length > 2
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    color: Theme.palette.textSecondary
                    font.family: Theme.typography.mono
                    font.pixelSize: Theme.typography.secondaryText
                    text: modelData.data !== undefined ? String(modelData.data) : ""
                }
            }
        }
        LogosText {
            objectName: review.prefix + "Note"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
            text: review.note
        }
        LogosText {
            objectName: review.prefix + "Error"
            visible: review.error.length > 0
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Theme.palette.error
            text: review.error
        }
        RowLayout {
            Layout.fillWidth: true
            LogosButton {
                objectName: review.prefix + "Cancel"
                text: review.cancelText
                onClicked: review.cancelled()
            }
            Item { Layout.fillWidth: true }
            LogosSpinner {
                implicitWidth: 18
                implicitHeight: 18
                visible: review.busy
                running: visible
                ringColor: Theme.palette.textSecondary
            }
            LogosButton {
                objectName: review.prefix + "Confirm"
                variant: LogosButton.Variant.Primary
                text: review.confirmText
                enabled: review.confirmEnabled && !review.busy
                onClicked: review.confirmed()
            }
        }
    }
}
