// A recovery phrase, typed one word to a numbered field and shown as typed: a hidden phrase can't
// be checked against the paper it was written on. Pasting a phrase into any field spreads it over
// the fields from there; so does setting `text`, which reads back as the words, one space apart.
// Read-only, it shows a phrase to be written down, numbered as it will be typed back.
import QtQuick
import QtQuick.Layouts
import Logos.Controls
import Logos.Theme

ColumnLayout {
    id: grid
    spacing: Theme.spacing.small

    /// How many words: one of `counts`.
    property int count: 12
    /// The words typed so far, one space apart.
    property string text: ""
    /// Each field's word, by position.
    property var words: []
    /// The lengths the chooser offers. An app whose phrases have one length gives that one alone,
    /// and the chooser hides.
    property var counts: [12, 15, 18, 21, 24]
    /// Shows the words without letting them change, and hides the chooser.
    property bool readOnly: false
    /// Every field has a word.
    readonly property bool complete: words.length === count && words.every(function (w) { return w.length > 0 })
    property bool writing: false
    property bool placing: false

    function clear() {
        text = ""
    }

    // Put `list` into the fields from `from`, growing to the length a whole phrase needs.
    function place(list, from) {
        placing = true
        const ws = words.slice()
        const need = from + list.length
        if (need > count) {
            const fits = counts.filter(function (n) { return n >= need })
            if (fits.length) count = fits[0]
        }
        while (ws.length < count) ws.push("")
        for (let i = 0; i < list.length && from + i < count; ++i)
            ws[from + i] = list[i].toLowerCase()
        ws.length = count
        words = ws
        publish()
        placing = false
        show()
    }

    function publish() {
        writing = true
        text = words.filter(function (w) { return w.length > 0 }).join(" ")
        writing = false
    }

    // The fields say what `words` says.
    function show() {
        for (let i = 0; i < fields.count; ++i) {
            const f = fields.itemAt(i) as LogosTextField
            if (f && f.text !== (words[i] || "")) f.text = words[i] || ""
        }
    }

    // A field's text as typed: a word, or a phrase pasted into it.
    function edit(i, value) {
        const parts = value.trim().split(/\s+/).filter(function (p) { return p.length > 0 })
        if (parts.length > 1) {
            place(parts, i)
            return
        }
        const ws = words.slice()
        while (ws.length < count) ws.push("")
        ws[i] = (parts[0] || "").toLowerCase()
        words = ws
        publish()
        // A space after a word moves on to the next field.
        if (parts.length === 1 && /\s$/.test(value) && i + 1 < fields.count) {
            const here = fields.itemAt(i) as LogosTextField
            const next = fields.itemAt(i + 1) as LogosTextField
            if (here) here.text = parts[0].toLowerCase()
            if (next) next.forceActiveFocus()
        }
    }

    onTextChanged: if (!writing) {
        words = []
        place(text.trim().length ? text.trim().split(/\s+/) : [], 0)
    }
    onCountChanged: if (!placing) place([], 0)
    // A count the app does not offer becomes its first.
    onCountsChanged: if (counts.indexOf(count) < 0) count = counts[0]
    // A field made after the words came (the count grew) shows its word too.
    Component.onCompleted: {
        if (counts.indexOf(count) < 0) count = counts[0]
        show()
    }

    RowLayout {
        Layout.fillWidth: true
        visible: grid.counts.length > 1 && !grid.readOnly
        LogosText { text: "Words"; color: Theme.palette.textSecondary }
        LogosComboBox {
            objectName: grid.objectName + "Count"
            model: grid.counts.map(String)
            currentIndex: Math.max(0, grid.counts.indexOf(grid.count))
            onActivated: function (i) { grid.count = grid.counts[i] }
        }
        Item { Layout.fillWidth: true }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: width < 380 ? 2 : 3
        columnSpacing: Theme.spacing.small
        rowSpacing: Theme.spacing.small
        Repeater {
            id: fields
            model: grid.count
            delegate: LogosTextField {
                required property int index
                objectName: grid.objectName + "_" + index
                Layout.fillWidth: true
                leftPadding: 36
                readOnly: grid.readOnly
                Component.onCompleted: {
                    textInput.inputMethodHints = Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData
                    text = grid.words[index] || ""
                }
                Connections {
                    target: textInput
                    function onTextEdited() { grid.edit(index, textInput.text) }
                }
                LogosText {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: index + 1
                    color: Theme.palette.textTertiary
                }
            }
        }
    }
}
