#!/usr/bin/env node
// The receive code's encoder, run as a table. No app, no inspector, no Qt.
//
// src/qml/qrcodegen.js is plain JavaScript behind a `.pragma library` line, so it is loaded
// here by stripping that line and evaluating the rest — the SAME text the view imports, not a
// copy of it. A copy is what drifts, and what this file is about is a code that scans.
//
// Nothing below reads the payload back out: a decoder here would be this encoder run
// backwards, and would agree with it however wrong both were. So the assertions are against
// facts the ISO spec fixes independently — the version a 42-character byte segment needs, the
// finder and timing patterns, and the published format-information string for level M.
//
// Run: node doctests/qr_table.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "src", "qml", "qrcodegen.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const names = [...src.matchAll(/^function\s+(\w+)\s*\(/gm)].map((m) => m[1]);
const Q = new Function(`${src}\nreturn { ${names.join(", ")} };`)();

let failed = 0;
function check(label, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    const ok = g === w;
    if (!ok) failed++;
    console.log(`  ${ok ? "PASS" : "FAIL"}  ${label}${ok ? "" : `\n        got  ${g}\n        want ${w}`}`);
}

// A real EIP-55 address, mixed case and all. Encoded bare — not as an EIP-681 URI, and never
// uppercased, because that case IS the checksum.
const ADDR = "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199";

const qr = Q.modules(ADDR);
const at = (x, y) => qr.bits.charAt(y * qr.size + x) === "1";

console.log("1) the wire shape: a size and one character per module, row-major");
check("bits are exactly size²", qr.bits.length, qr.size * qr.size);
check("...and nothing but 0 and 1", /^[01]+$/.test(qr.bits), true);

console.log("2) an address is a version-3 code, which is the spec's arithmetic, not ours");
// 42 bytes = 4 mode bits + 8 count bits + 336 = 348. Version 2-M holds 224 data bits and
// version 3-M holds 352. Anything else here means the version search or the capacity tables
// moved, and a code one version too small silently loses the tail of the address.
check("size 29", qr.size, 29);
check("...which is version 3", (qr.size - 17) / 4, 3);

console.log("3) the three finder patterns, which is what a scanner locks onto first");
// 1:1:3:1:1 across the centre of each, in both axes. A code with two of these is not read.
for (const [name, fx, fy] of [["top-left", 3, 3], ["top-right", qr.size - 4, 3],
                              ["bottom-left", 3, qr.size - 4]]) {
    const line = (h) => [-3, -2, -1, 0, 1, 2, 3]
        .map((d) => (h ? at(fx + d, fy) : at(fx, fy + d)) ? "1" : "0").join("");
    check(`${name} across`, line(true), "1011101");
    check(`${name} down`, line(false), "1011101");
}

console.log("3a) …and the timing patterns that tell it how wide one module is");
const between = [...Array(qr.size - 16).keys()].map((i) => i + 8);
check("row 6 alternates between the finders",
      between.map((i) => at(i, 6)), between.map((i) => i % 2 === 0));
check("column 6 too", between.map((i) => at(6, i)), between.map((i) => i % 2 === 0));

console.log("4) the error-correction level is MEDIUM, read off the code rather than asserted");
// The 15-bit format strings are fixed by the spec, one per (level, mask). Reading the copy
// beside the top-left finder back and finding it in level M's row is the only assertion here
// that a level change could not pass: an L or Q code is a different string entirely.
const M_FORMAT = ["101010000010010", "101000100100101", "101111001111100", "101101101001011",
                  "100010111111001", "100000011001110", "100111110010111", "100101010100000"];
let fmt = "";
for (let i = 14; i >= 0; i--)
    fmt += (i <= 5 ? at(8, i) : i === 6 ? at(8, 7) : i === 7 ? at(8, 8)
            : i === 8 ? at(7, 8) : at(14 - i, 8)) ? "1" : "0";
check("the format string is one of level M's", M_FORMAT.indexOf(fmt) >= 0, true);
// The mask is chosen by penalty score, so it is a fact about this payload, not a constant.
check("...naming mask 2 for this address", M_FORMAT.indexOf(fmt), 2);
check("and the dark module the spec fixes is dark", at(8, qr.size - 8), true);

console.log("5) one character changes the code, which is the whole point of encoding it");
// The failure this catches is a cached or hardcoded matrix: a screen that draws the same
// picture for every account sends every payment to one of them.
const near = Q.modules("0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1198");
check("same size", near.size, qr.size);
check("...different bits", near.bits === qr.bits, false);
check("and the same address twice is the same code", Q.modules(ADDR).bits, qr.bits);
check("a lowercased address is a DIFFERENT payload, so a different code",
      Q.modules(ADDR.toLowerCase()).bits === qr.bits, false);

console.log("6) the degenerate inputs a view hands over before an account is chosen");
// The view's own qrModules() answers null for these rather than drawing anything. What is
// asserted here is that reaching the encoder with one is not an exception: a throw inside a
// binding takes the whole screen, not just the code.
for (const [label, arg] of [["empty string", ""], ["undefined", undefined], ["null", null]])
    check(`${label} encodes rather than throwing`, (() => {
        try { return Q.modules(arg).size > 0 } catch (e) { return String(e) }
    })(), true);
check("...and they all encode the same nothing", Q.modules("").bits, Q.modules(null).bits);

console.log("7) longer payloads still encode, so the version search is not pinned to 3");
// Not a case this screen reaches, but the search and the multi-block interleave are shared
// code, and a table that only ever asks for 42 bytes exercises neither.
check("100 bytes grows the code", Q.modules("x".repeat(100)).size > qr.size, true);
check("...and 300 grows it again", Q.modules("x".repeat(300)).size > Q.modules("x".repeat(100)).size, true);
check("4000 bytes is beyond version 40 and says so", (() => {
    try { Q.modules("x".repeat(4000)); return "no error" } catch (e) { return e instanceof RangeError }
})(), true);

console.log(`\nRESULT: ${failed ? "FAILURES" : "ALL PASS"}`);
process.exit(failed ? 1 : 0);
