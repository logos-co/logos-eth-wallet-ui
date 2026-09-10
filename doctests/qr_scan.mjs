// Render the encoder's output as PGM images for a real scanner to read.
//
// The tables next door check structure and parameters; nothing there proves the thing SCANS.
// This writes what the Receive screen draws — same encoder, same quiet zone — and qr_scan.sh
// hands it to zbar. A corrupted GF polynomial passes every structural check and produces a
// code no reader can decode; only this catches that.
import { readFileSync, writeFileSync } from "fs"
import { dirname, join } from "path"
import { fileURLToPath } from "url"

const here = dirname(fileURLToPath(import.meta.url))
const src = readFileSync(join(here, "..", "src", "qml", "qrcodegen.js"), "utf8")
  .split("\n").filter((l) => !l.startsWith(".pragma")).join("\n")
const { modules } = new Function(`${src}\nreturn { modules }`)()

// The quiet zone and cell size the view uses, so the image is what a camera would see.
const QUIET = 4
const SCALE = 8

export const PAYLOADS = [
  "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199", // a real EIP-55 address, mixed case
  "0x0000000000000000000000000000000000000000",
  "a",
  "x".repeat(100),
  "y".repeat(300),
]

const outDir = process.argv[2]
if (!outDir) { console.error("usage: node qr_scan.mjs <out-dir>"); process.exit(2) }
PAYLOADS.forEach((payload, i) => {
  const qr = modules(payload)
  const dim = (qr.size + 2 * QUIET) * SCALE
  const px = Buffer.alloc(dim * dim, 255)
  for (let y = 0; y < qr.size; y++)
    for (let x = 0; x < qr.size; x++) {
      if (qr.bits[y * qr.size + x] !== "1") continue
      for (let dy = 0; dy < SCALE; dy++)
        for (let dx = 0; dx < SCALE; dx++)
          px[((y + QUIET) * SCALE + dy) * dim + ((x + QUIET) * SCALE + dx)] = 0
    }
  writeFileSync(join(outDir, `qr_${i}.pgm`), Buffer.concat([Buffer.from(`P5\n${dim} ${dim}\n255\n`), px]))
  writeFileSync(join(outDir, `qr_${i}.txt`), payload)
})
