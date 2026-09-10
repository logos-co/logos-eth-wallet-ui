.pragma library

/*
 * QR Code generator library (JavaScript)
 *
 * Copyright (c) Project Nayuki. (MIT License)
 * https://www.nayuki.io/page/qr-code-generator-library
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 * - The above copyright notice and this permission notice shall be included in all
 *   copies or substantial portions of the Software.
 * - The Software is provided "as is", without warranty of any kind, express or
 *   implied, including but not limited to the warranties of merchantability,
 *   fitness for a particular purpose and noninfringement. In no event shall the
 *   authors or copyright holders be liable for any claim, damages or other
 *   liability, whether in an action of contract, tort or otherwise, arising from,
 *   out of or in connection with the Software or the use or other dealings in the
 *   Software.
 */

// Adapted for QML: the classes are flattened to top-level functions and the published build's
// UMD preamble is dropped, because `module`, `exports` and `window` are all undefined in a QML
// JS import and probing them throws before a single module is placed. Byte mode only — an
// address is ASCII, and the alphanumeric mode's character set does not contain lowercase hex.

var ECL_MEDIUM = 1

// Rows are L, M, Q, H; columns are version 1..40, with index 0 unreachable.
var ECC_CODEWORDS_PER_BLOCK = [
    [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
    [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30]
]
var NUM_ERROR_CORRECTION_BLOCKS = [
    [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
    [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
    [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
    [-1, 1, 1, 2, 4, 4, 4, 5, 5, 8, 9, 9, 11, 13, 15, 19, 23, 17, 19, 34, 34, 28, 31, 39, 46, 49, 48, 57, 60, 63, 72, 80, 89, 98, 109, 121, 133, 142, 150, 161, 180]
]
var ECC_FORMAT_BITS = [1, 0, 3, 2]

function getBit(x, i) { return ((x >>> i) & 1) !== 0 }

function appendBits(val, len, bb) {
    for (var i = len - 1; i >= 0; i--)
        bb.push((val >>> i) & 1)
}

function newRow(n) {
    var r = []
    for (var i = 0; i < n; i++) r.push(false)
    return r
}

// encodeURIComponent is the shortest correct UTF-8 encoder in a JS dialect with no TextEncoder.
function toUtf8(str) {
    var out = []
    var esc = encodeURIComponent(str)
    for (var i = 0; i < esc.length; i++) {
        if (esc.charAt(i) === "%") {
            out.push(parseInt(esc.substr(i + 1, 2), 16))
            i += 2
        } else {
            out.push(esc.charCodeAt(i))
        }
    }
    return out
}

function getNumRawDataModules(ver) {
    var result = (16 * ver + 128) * ver + 64
    if (ver >= 2) {
        var numAlign = Math.floor(ver / 7) + 2
        result -= (25 * numAlign - 10) * numAlign - 55
        if (ver >= 7) result -= 36
    }
    return result
}

function getNumDataCodewords(ver, ecl) {
    return Math.floor(getNumRawDataModules(ver) / 8)
        - ECC_CODEWORDS_PER_BLOCK[ecl][ver] * NUM_ERROR_CORRECTION_BLOCKS[ecl][ver]
}

function numCharCountBits(ver) { return ver <= 9 ? 8 : 16 }

function reedSolomonMultiply(x, y) {
    var z = 0
    for (var i = 7; i >= 0; i--) {
        z = (z << 1) ^ ((z >>> 7) * 0x11D)
        z ^= ((y >>> i) & 1) * x
    }
    return z & 0xFF
}

function reedSolomonComputeDivisor(degree) {
    var result = []
    for (var i = 0; i < degree - 1; i++) result.push(0)
    result.push(1)
    var root = 1
    for (var i = 0; i < degree; i++) {
        for (var j = 0; j < result.length; j++) {
            result[j] = reedSolomonMultiply(result[j], root)
            if (j + 1 < result.length) result[j] ^= result[j + 1]
        }
        root = reedSolomonMultiply(root, 0x02)
    }
    return result
}

function reedSolomonComputeRemainder(data, divisor) {
    var result = divisor.map(function () { return 0 })
    for (var k = 0; k < data.length; k++) {
        var factor = data[k] ^ result.shift()
        result.push(0)
        for (var i = 0; i < divisor.length; i++)
            result[i] ^= reedSolomonMultiply(divisor[i], factor)
    }
    return result
}

function addEccAndInterleave(data, version, ecl) {
    var numBlocks = NUM_ERROR_CORRECTION_BLOCKS[ecl][version]
    var blockEccLen = ECC_CODEWORDS_PER_BLOCK[ecl][version]
    var rawCodewords = Math.floor(getNumRawDataModules(version) / 8)
    var numShortBlocks = numBlocks - rawCodewords % numBlocks
    var shortBlockLen = Math.floor(rawCodewords / numBlocks)

    var blocks = []
    var rsDiv = reedSolomonComputeDivisor(blockEccLen)
    for (var i = 0, k = 0; i < numBlocks; i++) {
        var dat = data.slice(k, k + shortBlockLen - blockEccLen + (i < numShortBlocks ? 0 : 1))
        k += dat.length
        var ecc = reedSolomonComputeRemainder(dat, rsDiv)
        if (i < numShortBlocks) dat.push(0)
        blocks.push(dat.concat(ecc))
    }

    var result = []
    for (var i = 0; i < blocks[0].length; i++) {
        for (var j = 0; j < blocks.length; j++) {
            if (i !== shortBlockLen - blockEccLen || j >= numShortBlocks)
                result.push(blocks[j][i])
        }
    }
    return result
}

function setFunctionModule(qr, x, y, isDark) {
    qr.modules[y][x] = isDark
    qr.isFunction[y][x] = true
}

function drawFinderPattern(qr, x, y) {
    for (var dy = -4; dy <= 4; dy++) {
        for (var dx = -4; dx <= 4; dx++) {
            var dist = Math.max(Math.abs(dx), Math.abs(dy))
            var xx = x + dx, yy = y + dy
            if (0 <= xx && xx < qr.size && 0 <= yy && yy < qr.size)
                setFunctionModule(qr, xx, yy, dist !== 2 && dist !== 4)
        }
    }
}

function drawAlignmentPattern(qr, x, y) {
    for (var dy = -2; dy <= 2; dy++)
        for (var dx = -2; dx <= 2; dx++)
            setFunctionModule(qr, x + dx, y + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1)
}

function getAlignmentPatternPositions(version) {
    if (version === 1) return []
    var numAlign = Math.floor(version / 7) + 2
    var step = (version === 32) ? 26
        : Math.ceil((version * 4 + 17 - 13) / (numAlign * 2 - 2)) * 2
    var result = [6]
    for (var pos = version * 4 + 10; result.length < numAlign; pos -= step)
        result.splice(1, 0, pos)
    return result
}

function drawFormatBits(qr, mask) {
    var data = ECC_FORMAT_BITS[qr.ecl] << 3 | mask
    var rem = data
    for (var i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537)
    var bits = (data << 10 | rem) ^ 0x5412

    for (var i = 0; i <= 5; i++) setFunctionModule(qr, 8, i, getBit(bits, i))
    setFunctionModule(qr, 8, 7, getBit(bits, 6))
    setFunctionModule(qr, 8, 8, getBit(bits, 7))
    setFunctionModule(qr, 7, 8, getBit(bits, 8))
    for (var i = 9; i < 15; i++) setFunctionModule(qr, 14 - i, 8, getBit(bits, i))

    var size = qr.size
    for (var i = 0; i < 8; i++) setFunctionModule(qr, size - 1 - i, 8, getBit(bits, i))
    for (var i = 8; i < 15; i++) setFunctionModule(qr, 8, size - 15 + i, getBit(bits, i))
    setFunctionModule(qr, 8, size - 8, true)
}

function drawVersion(qr) {
    if (qr.version < 7) return
    var rem = qr.version
    for (var i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1F25)
    var bits = qr.version << 12 | rem
    for (var i = 0; i < 18; i++) {
        var color = getBit(bits, i)
        var a = qr.size - 11 + i % 3
        var b = Math.floor(i / 3)
        setFunctionModule(qr, a, b, color)
        setFunctionModule(qr, b, a, color)
    }
}

function drawFunctionPatterns(qr) {
    var size = qr.size
    for (var i = 0; i < size; i++) {
        setFunctionModule(qr, 6, i, i % 2 === 0)
        setFunctionModule(qr, i, 6, i % 2 === 0)
    }
    drawFinderPattern(qr, 3, 3)
    drawFinderPattern(qr, size - 4, 3)
    drawFinderPattern(qr, 3, size - 4)

    var pos = getAlignmentPatternPositions(qr.version)
    for (var i = 0; i < pos.length; i++) {
        for (var j = 0; j < pos.length; j++) {
            var corner = (i === 0 && j === 0) || (i === 0 && j === pos.length - 1)
                || (i === pos.length - 1 && j === 0)
            if (!corner) drawAlignmentPattern(qr, pos[i], pos[j])
        }
    }
    drawFormatBits(qr, 0)
    drawVersion(qr)
}

function drawCodewords(qr, data) {
    var size = qr.size
    var i = 0
    for (var right = size - 1; right >= 1; right -= 2) {
        if (right === 6) right = 5
        for (var vert = 0; vert < size; vert++) {
            for (var j = 0; j < 2; j++) {
                var x = right - j
                var upward = ((right + 1) & 2) === 0
                var y = upward ? size - 1 - vert : vert
                if (!qr.isFunction[y][x] && i < data.length * 8) {
                    qr.modules[y][x] = getBit(data[i >>> 3], 7 - (i & 7))
                    i++
                }
            }
        }
    }
}

function applyMask(qr, mask) {
    for (var y = 0; y < qr.size; y++) {
        for (var x = 0; x < qr.size; x++) {
            if (qr.isFunction[y][x]) continue
            var invert = false
            switch (mask) {
            case 0: invert = (x + y) % 2 === 0; break
            case 1: invert = y % 2 === 0; break
            case 2: invert = x % 3 === 0; break
            case 3: invert = (x + y) % 3 === 0; break
            case 4: invert = (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0; break
            case 5: invert = x * y % 2 + x * y % 3 === 0; break
            case 6: invert = (x * y % 2 + x * y % 3) % 2 === 0; break
            case 7: invert = ((x + y) % 2 + x * y % 3) % 2 === 0; break
            }
            if (invert) qr.modules[y][x] = !qr.modules[y][x]
        }
    }
}

function finderPenaltyAddHistory(currentRunLength, runHistory, size) {
    if (runHistory[0] === 0) currentRunLength += size
    runHistory.pop()
    runHistory.unshift(currentRunLength)
}

function finderPenaltyCountPatterns(runHistory) {
    var n = runHistory[1]
    var core = n > 0 && runHistory[2] === n && runHistory[3] === n * 3
        && runHistory[4] === n && runHistory[5] === n
    return (core && runHistory[0] >= n * 4 && runHistory[6] >= n ? 1 : 0)
        + (core && runHistory[6] >= n * 4 && runHistory[0] >= n ? 1 : 0)
}

function finderPenaltyTerminateAndCount(currentRunColor, currentRunLength, runHistory, size) {
    if (currentRunColor) {
        finderPenaltyAddHistory(currentRunLength, runHistory, size)
        currentRunLength = 0
    }
    currentRunLength += size
    finderPenaltyAddHistory(currentRunLength, runHistory, size)
    return finderPenaltyCountPatterns(runHistory)
}

function getPenaltyScore(qr) {
    var size = qr.size
    var result = 0
    var x, y, runLen, runColor, runHistory

    for (y = 0; y < size; y++) {
        runColor = false; runLen = 0; runHistory = [0, 0, 0, 0, 0, 0, 0]
        for (x = 0; x < size; x++) {
            if (qr.modules[y][x] === runColor) {
                runLen++
                if (runLen === 5) result += 3
                else if (runLen > 5) result++
            } else {
                finderPenaltyAddHistory(runLen, runHistory, size)
                if (!runColor) result += finderPenaltyCountPatterns(runHistory) * 40
                runColor = qr.modules[y][x]
                runLen = 1
            }
        }
        result += finderPenaltyTerminateAndCount(runColor, runLen, runHistory, size) * 40
    }
    for (x = 0; x < size; x++) {
        runColor = false; runLen = 0; runHistory = [0, 0, 0, 0, 0, 0, 0]
        for (y = 0; y < size; y++) {
            if (qr.modules[y][x] === runColor) {
                runLen++
                if (runLen === 5) result += 3
                else if (runLen > 5) result++
            } else {
                finderPenaltyAddHistory(runLen, runHistory, size)
                if (!runColor) result += finderPenaltyCountPatterns(runHistory) * 40
                runColor = qr.modules[y][x]
                runLen = 1
            }
        }
        result += finderPenaltyTerminateAndCount(runColor, runLen, runHistory, size) * 40
    }

    for (y = 0; y < size - 1; y++) {
        for (x = 0; x < size - 1; x++) {
            var c = qr.modules[y][x]
            if (c === qr.modules[y][x + 1] && c === qr.modules[y + 1][x]
                    && c === qr.modules[y + 1][x + 1])
                result += 3
        }
    }

    var dark = 0
    for (y = 0; y < size; y++)
        for (x = 0; x < size; x++)
            if (qr.modules[y][x]) dark++
    var total = size * size
    result += (Math.ceil(Math.abs(dark * 20 - total * 10) / total) - 1) * 10
    return result
}

function makeQr(dataCodewords, version, ecl) {
    var size = version * 4 + 17
    var qr = { size: size, version: version, ecl: ecl, mask: -1, modules: [], isFunction: [] }
    for (var i = 0; i < size; i++) {
        qr.modules.push(newRow(size))
        qr.isFunction.push(newRow(size))
    }

    drawFunctionPatterns(qr)
    drawCodewords(qr, addEccAndInterleave(dataCodewords, version, ecl))

    var mask = 0, minPenalty = Infinity
    for (var m = 0; m < 8; m++) {
        applyMask(qr, m)
        drawFormatBits(qr, m)
        var penalty = getPenaltyScore(qr)
        if (penalty < minPenalty) { mask = m; minPenalty = penalty }
        applyMask(qr, m)
    }
    qr.mask = mask
    applyMask(qr, mask)
    drawFormatBits(qr, mask)
    return qr
}

function encodeBytes(data, ecl) {
    var version, capacityBits
    for (version = 1; ; version++) {
        capacityBits = getNumDataCodewords(version, ecl) * 8
        if (4 + numCharCountBits(version) + data.length * 8 <= capacityBits) break
        if (version >= 40) throw new RangeError("data too long for a QR code")
    }

    var bb = []
    appendBits(0x4, 4, bb)
    appendBits(data.length, numCharCountBits(version), bb)
    for (var i = 0; i < data.length; i++) appendBits(data[i], 8, bb)

    appendBits(0, Math.min(4, capacityBits - bb.length), bb)
    appendBits(0, (8 - bb.length % 8) % 8, bb)
    for (var pad = 0xEC; bb.length < capacityBits; pad ^= 0xEC ^ 0x11)
        appendBits(pad, 8, bb)

    var codewords = []
    for (var i = 0; i < bb.length / 8; i++) codewords.push(0)
    for (var i = 0; i < bb.length; i++)
        codewords[i >>> 3] |= bb[i] << (7 - (i & 7))

    return makeQr(codewords, version, ecl)
}

// The one entry point the view uses. Row-major, one character per module, so the drawing side
// needs no knowledge of any of the above — and the shape matches what the Monero wallet's
// backend publishes, which is where the run-length drawing came from.
function modules(text) {
    var qr = encodeBytes(toUtf8(text === undefined || text === null ? "" : String(text)),
                         ECL_MEDIUM)
    var bits = ""
    for (var y = 0; y < qr.size; y++)
        for (var x = 0; x < qr.size; x++)
            bits += qr.modules[y][x] ? "1" : "0"
    return { size: qr.size, bits: bits }
}
