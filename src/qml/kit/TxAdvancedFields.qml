import QtQuick 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "fees.js" as Fees

// The fees, gas limits and nonce a user may set, in wei per gas, with the quote's figures as
// placeholders. `overrides` is what the request carries; a nonce pins a single call only.
ColumnLayout {
    id: adv
    property var quote: ({})
    property int calls: 1
    // Names for the gas limit fields of a send with several calls, one per call.
    property var callLabels: []
    property alias open: toggle.checked
    property var gasTexts: []
    // The quote's fees when the user first set one of the two. Read later, they would come
    // from a quote of the request these very fields shape, and chase their own tail.
    property string heldFee: ""
    property string heldTip: ""

    readonly property var q: quote ? quote : ({})
    // The last quote that priced anything: an edit here unpairs the current one until it is
    // priced again, and the fees the user was looking at must survive that.
    property var seen: ({})
    onQChanged: if (q.maxFeePerGas !== undefined) seen = q
    readonly property var fields: ({ maxFee: maxFee.text, priorityFee: priorityFee.text,
                                     gasLimits: gasTexts.slice(0, calls), nonce: nonce.text })
    readonly property var overrides: open
        ? Fees.overrides(fields, { maxFeePerGas: heldFee, maxPriorityFeePerGas: heldTip }, calls) : ({})
    readonly property string error: open ? Fees.fieldError(fields, calls) : ""

    // Limits and a pin set for one set of calls must not land on another's.
    onCallsChanged: {
        for (var i = 0; i < gasFields.count; ++i) gasFields.itemAt(i).text = ""
        gasTexts = []
        nonce.text = ""
    }

    function hold() {
        if (!maxFee.text.trim().length && !priorityFee.text.trim().length) {
            heldFee = ""
            heldTip = ""
        } else if (!heldFee.length && !heldTip.length) {
            heldFee = seen.maxFeePerGas !== undefined ? String(seen.maxFeePerGas) : ""
            heldTip = seen.maxPriorityFeePerGas !== undefined ? String(seen.maxPriorityFeePerGas) : ""
        }
    }

    function clear() {
        maxFee.text = ""
        priorityFee.text = ""
        nonce.text = ""
        for (var i = 0; i < gasFields.count; ++i) gasFields.itemAt(i).text = ""
        gasTexts = []
        toggle.checked = false
    }

    Layout.fillWidth: true
    spacing: Theme.spacing.small

    LogosCheckbox {
        id: toggle
        objectName: "advancedToggle"
        text: "Advanced"
    }

    ColumnLayout {
        visible: toggle.checked
        Layout.fillWidth: true

        LogosTextField {
            id: maxFee
            objectName: "maxFeeField"
            Layout.fillWidth: true
            placeholderText: adv.seen.maxFeePerGas !== undefined
                             ? "Max fee (wei per gas, suggested " + adv.seen.maxFeePerGas + ")" : "Max fee (wei per gas)"
            onTextChanged: adv.hold()
        }
        LogosTextField {
            id: priorityFee
            objectName: "maxPriorityFeeField"
            Layout.fillWidth: true
            placeholderText: adv.seen.maxPriorityFeePerGas !== undefined
                             ? "Priority fee (wei per gas, suggested " + adv.seen.maxPriorityFeePerGas + ")"
                             : "Priority fee (wei per gas)"
            onTextChanged: adv.hold()
        }
        Repeater {
            id: gasFields
            model: adv.calls
            LogosTextField {
                objectName: adv.calls > 1 ? "gasLimitField_" + index : "gasLimitField"
                Layout.fillWidth: true
                readonly property string estimated: Fees.gasLimits(adv.seen)[index] || ""
                readonly property string name: adv.calls > 1
                    ? (adv.callLabels[index] || "Call " + (index + 1)) + ": gas limit" : "Gas limit"
                placeholderText: name + (estimated.length ? " (estimated " + estimated + ")" : "")
                onTextChanged: {
                    var g = adv.gasTexts.slice()
                    g[index] = text
                    adv.gasTexts = g
                }
            }
        }
        // A nonce replaces ONE pending transaction, so a send of several cannot take one.
        LogosTextField {
            id: nonce
            objectName: "nonceField"
            Layout.fillWidth: true
            readOnly: adv.calls > 1
            placeholderText: adv.calls > 1
                ? "Nonces " + Fees.nonces(adv.seen, adv.calls).join(", ") + ": a send of " + adv.calls
                  + " transactions cannot be pinned"
                : adv.seen.nonce !== undefined ? "Nonce (next is " + adv.seen.nonce + ")" : "Nonce"
        }
        LogosText {
            objectName: "advancedError"
            visible: adv.error.length > 0
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Theme.palette.error
            text: adv.error
        }
    }
}
