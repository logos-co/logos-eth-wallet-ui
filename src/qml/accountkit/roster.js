// How one account, and the signers holding it, reads in every app. The input is an entry of
// the signer manager's `roster()` as is: { key, family, chain, address, path, label, labels,
// wallet: { fingerprint, name }, holders: [{ signer, accountId, kind, model, transport,
// presence, available, ... }] }. Plain JavaScript, no `.pragma library`, so CodeQL can read it;
// doctests/roster_table.mjs runs it.

function text(v) {
    return v === undefined || v === null ? "" : String(v).trim()
}

function isBitcoin(e) {
    return !!e && (e.family === "bitcoin" || e.family === "bitcoin_taproot")
}

// 0x9858…2a9C: the start and the end a person checks against another screen.
function shortAddress(a) {
    var s = text(a)
    return s.length > 14 ? s.slice(0, 6) + "…" + s.slice(-4) : s
}

function scriptType(e) {
    return !e ? "" : e.family === "bitcoin_taproot" ? "Taproot" : e.family === "bitcoin" ? "Native SegWit" : ""
}

// A Bitcoin account's number (m/84'/1'/0' is 0), or an EVM address's index (m/44'/60'/0'/0/3
// is 3); -1 when the path doesn't say.
function accountNumber(e) {
    var steps = text(e && e.path).split("/")
    var step = isBitcoin(e) ? steps[3] : steps.length > 1 ? steps[steps.length - 1] : undefined
    var n = parseInt(text(step), 10)
    return isNaN(n) ? -1 : n
}

// The name the person gave it. An unnamed EVM account is its address, so it has none; an
// unnamed Bitcoin account is "Bitcoin #<account>".
function name(e) {
    var l = text(e && e.label)
    if (l || !isBitcoin(e)) return l
    var n = accountNumber(e)
    return n >= 0 ? "Bitcoin #" + n : "Bitcoin"
}

// The account number beside a named Bitcoin account; an unnamed one carries it in its name.
function accountText(e) {
    var n = accountNumber(e)
    return isBitcoin(e) && text(e.label) && n >= 0 ? "account " + n : ""
}

// The first line, in words: an EVM account's name and address, a Bitcoin account's name,
// script type and number.
function title(e) {
    if (!e) return ""
    if (isBitcoin(e)) return [name(e), scriptType(e), accountText(e)].filter(Boolean).join(" · ")
    return [name(e), shortAddress(e.address)].filter(Boolean).join(" ")
}

// The wallet it comes from: its name and master fingerprint, with an EVM address's index. A
// `null` wallet (the roster's word for none) is an imported key; an absent one is unknown; an
// empty one is a wallet the app knows of but can't name.
function walletLine(e) {
    if (!e) return ""
    if (e.wallet === undefined) return "Wallet unknown"
    if (!e.wallet) return isBitcoin(e) ? "Wallet unknown" : "Imported key · no wallet"
    var fingerprint = text(e.wallet.fingerprint)
    var named = text(e.wallet.name)
    var parts = ["Wallet" + (named ? " “" + named + "”" : "")]
    if (fingerprint) parts.push(fingerprint)
    var n = accountNumber(e)
    if (!isBitcoin(e) && n >= 0) parts.push("account " + n)
    return parts.join(" · ")
}

// What a signer is called wherever it is offered.
function holderName(h) {
    if (!h) return ""
    var named = { keycard_shell: "Keycard Shell", ledger: "Ledger", trezor: "Trezor" }
    if (h.transport === "keystore") return "This device (Keystore)"
    if (h.transport === "reader") return "Keycard · reader"
    if (h.transport === "usb") return (named[h.kind] || text(h.model) || h.signer) + " · USB"
    if (h.transport === "qr") return text(h.model) && h.model !== "QR wallet" ? "QR · " + h.model : "QR wallet"
    return text(h.model) || text(h.signer)
}

// Ready, connected or not connected. A QR wallet needs no connection, so it is none of them.
function holderState(h) {
    var p = h && h.presence
    return p === "local" ? "ready" : p === "connected" ? "connected" : p === "absent" ? "not connected" : ""
}

// A chip: a filled dot for a signer that can sign now, a hollow one for one that isn't
// connected, none for a QR wallet.
function chip(h) {
    var p = h && h.presence
    var mark = p === "local" || p === "connected" ? "●" : p === "absent" ? "○" : ""
    return (mark ? mark + " " : "") + holderName(h)
}

// One line for a tooltip or an accessible name.
function summary(e) {
    if (!e) return ""
    var holders = (e.holders || []).map(holderName).join(", ")
    return [title(e), walletLine(e), holders].filter(Boolean).join(" — ")
}

// The entries an app lists: of these families, and for Bitcoin on this chain ("main" or "test").
function select(entries, families, chain) {
    return (entries || []).filter(function (e) {
        return families.indexOf(e.family) >= 0 && (!chain || !isBitcoin(e) || e.chain === chain)
    })
}

function sameId(e, a, b) {
    return isBitcoin(e) ? a === b : text(a).toLowerCase() === text(b).toLowerCase()
}

// The entry a roster key, or any holder's own id for the account, names.
function find(entries, keyOrId) {
    var list = entries || []
    for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (e.key === keyOrId) return e
        // An EVM key is the lowercase address, and apps hold it checksummed.
        if (!isBitcoin(e) && (sameId(e, e.key, keyOrId) || sameId(e, e.address, keyOrId))) return e
        var hs = e.holders || []
        for (var j = 0; j < hs.length; j++)
            if (sameId(e, hs[j].accountId, keyOrId)) return e
    }
    return null
}

function indexOf(entries, keyOrId) {
    var e = find(entries, keyOrId)
    return e ? (entries || []).indexOf(e) : -1
}

// Whether some signer holding it signs several transactions as one request, as a swap with an
// approval needs. Only a signer that takes bare hashes does: a device that shows what it signs
// takes one transaction at a time. Unknown signers are not held against it.
function signsBundles(e) {
    var hs = (e && e.holders) || []
    if (!hs.length) return true
    return hs.some(function (h) { return !h.requestKinds || h.requestKinds.indexOf("hash") >= 0 })
}

// The id a Bitcoin account opens under: a holder's that already has a wallet here, else the
// first holder's, which is the keystore's when it holds the account.
function homeId(e, opened) {
    var hs = (e && e.holders) || []
    var known = opened || []
    for (var i = 0; i < hs.length; i++)
        if (known.indexOf(hs[i].accountId) >= 0) return hs[i].accountId
    return hs.length ? hs[0].accountId : ""
}
