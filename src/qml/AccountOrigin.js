// Public source metadata from the signer manager. Never a recovery phrase's words.
.pragma library
function shortId(id) { return id ? String(id).split(":").pop().slice(0, 8) : "" }
function device(wallet) {
    var w = wallet || {}, origin = w.origin || {}, devices = origin.devices || []
    var device = devices.map(function(d) {
        if (d.kind === "keystore") return "This device (Keystore)"
        var kind = d.kind === "keycard" ? "Keycard" : d.kind === "keycard_shell" ? "Keycard Shell (USB)" : "Device"
        return kind + (d.name ? " “" + d.name + "”" : "") + (d.id ? " · " + shortId(d.id) : "")
    }).join(" / ")
    if (!device) device = w.signer === "keycard_module" ? "Keycard (unidentified)"
        : w.signer === "keystore_module" ? "This device (Keystore)" : "Device unknown"
    return device
}
function wallet(wallet) {
    var origin = (wallet || {}).origin || {}
    var phrase = origin.phrase
    var phraseText = phrase && phrase.id
        ? "Wallet" + (phrase.name ? " “" + phrase.name + "”" : "") + " · " + shortId(phrase.id)
        : origin.kind === "imported-key" ? "Imported key · no phrase recorded"
        : origin.kind === "imported-json" ? "Imported file · no phrase recorded"
        : origin.kind === "random" ? "Generated key · no phrase"
        : "Wallet unknown"
    return phraseText
}
function source(w) { return device(w) + " — " + wallet(w) }
// Hide the middle line only when the device has one known wallet. Missing origin
// metadata cannot prove that two accounts belong to the same wallet.
function showWallet(w, inventory) {
    var origin = (w || {}).origin || {}, phrase = origin.phrase
    if (!phrase || !phrase.id) return false
    if (phrase.name) return true
    var devices = origin.devices || []
    function sameDevice(other) {
        var theirs = ((other || {}).origin || {}).devices || []
        if (!devices.length || !theirs.length) return w.signer === other.signer
        return devices.some(function(d) { return theirs.some(function(t) { return d.kind === t.kind && d.id === t.id }) })
    }
    return inventory.some(function(other) {
        if (!other || !sameDevice(other)) return false
        var p = (other.origin || {}).phrase
        return !p || !p.id || p.id !== phrase.id
    })
}
function account(address, name, shortAddress) {
    return (name ? name + " — " : "") + shortAddress
}
function summary(wallet, address, name, shortAddress) {
    return source(wallet) + " — " + account(address, name, shortAddress)
}
