// The kit's rules, as strings throughout: wei outgrows a JS number, and a rounded fee is a
// claim nobody made. Components format with these; doctests/fees_table.mjs runs them.
// Plain JavaScript, no `.pragma library`: the functions hold no state, and CodeQL cannot read one.

function tierName(tier) {
    return tier === "slow" ? "Low" : tier === "normal" ? "Market" : tier === "fast" ? "Fast" : String(tier || "")
}

function isWhole(s) {
    return /^[0-9]+$/.test(String(s))
}

function text(v) {
    return v === undefined || v === null ? "" : String(v).trim()
}

// Wei as gwei, exactly and without trailing zeros; "" for anything that is not wei.
function gwei(wei) {
    var s = text(wei)
    if (!isWhole(s)) return ""
    s = s.replace(/^0+/, "")
    while (s.length < 10) s = "0" + s
    var frac = s.slice(-9).replace(/0+$/, "")
    return s.slice(0, -9) + (frac.length ? "." + frac : "")
}

// The gas limit of each call a quote priced, from its legs or its one total.
function gasLimits(quote) {
    if (quote && quote.legs && quote.legs.length)
        return quote.legs.map(function (l) { return text(l.gasLimit) })
    return quote && text(quote.gasLimit).length ? [text(quote.gasLimit)] : []
}

// The numbers a quote would use: one per call, from its first.
function nonces(quote, calls) {
    if (!quote || !isWhole(text(quote.nonce))) return []
    var out = []
    for (var i = 0; i < Math.max(1, calls); ++i) out.push(Number(quote.nonce) + i)
    return out
}

// "at most 0.00006 ETH (Market)": a ceiling, never "the fee". Fees the user set read custom.
function ceiling(quote, tier, symbol) {
    if (!quote || text(quote.feeCeilingWeiDisplay).length === 0) return ""
    var basis = quote.feeSource === "custom" ? "custom" : tierName(tier)
    return "at most " + quote.feeCeilingWeiDisplay + " " + (quote.nativeSymbol || symbol || "")
         + (basis.length ? " (" + basis + ")" : "")
}

// What the Advanced fields add to a request. Both fee fields travel together, the empty one
// from the quote, because an older fee_module prices a lone one at the tier. Gas limits are
// per call, null leaving a call estimated; a nonce pins a single call only.
function overrides(f, quote, calls) {
    var o = {}
    var fee = text(f.maxFee), tip = text(f.priorityFee)
    if (fee.length || tip.length) {
        o.maxFeePerGas = fee.length ? fee : text(quote && quote.maxFeePerGas)
        o.maxPriorityFeePerGas = tip.length ? tip : text(quote && quote.maxPriorityFeePerGas)
    }
    var g = (f.gasLimits || []).map(function (x) { return text(x).length ? text(x) : null })
    if (g.some(function (x) { return x !== null })) o.gasLimits = g
    if (text(f.nonce).length && calls === 1) o.nonce = Number(text(f.nonce))
    return o
}

// The first field a backend would refuse, in words; "" when every field set is well formed.
function fieldError(f, calls) {
    var named = [["Max fee", f.maxFee], ["Priority fee", f.priorityFee], ["Nonce", f.nonce]]
    ;(f.gasLimits || []).forEach(function (g, i) {
        named.push([calls > 1 ? "Gas limit " + (i + 1) : "Gas limit", g])
    })
    for (var i = 0; i < named.length; ++i) {
        var t = text(named[i][1])
        if (t.length && !isWhole(t)) return named[i][0] + " must be a whole number"
        if (t.length && named[i][0].indexOf("Gas limit") === 0 && /^0+$/.test(t))
            return named[i][0] + " must be more than zero"
    }
    return ""
}

// The review's note on a pinned nonce that outbids a transaction still pending there.
function replacesText(quote) {
    var r = quote && quote.replaces
    if (!r || r.nonce === undefined) return ""
    return "Replaces the transaction still pending at nonce " + r.nonce
         + (r.raised === true ? ". Its fees are raised past that one's, as nodes require." : ".")
}
