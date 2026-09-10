#!/usr/bin/env bash
# Decode what the Receive screen draws, with a real scanner.
#
# zbar is a reader, not this encoder run backwards, so it is the only check here that can say
# the code is READABLE rather than merely well-shaped. Absence of zbar is a FAILURE, not a
# skip: a silent skip is how a test stops covering the thing it was written for.
set -euo pipefail
cd "$(dirname "$0")"
command -v zbarimg >/dev/null || { echo "qr_scan: zbarimg not found (nix shell nixpkgs#zbar)"; exit 1; }
command -v node    >/dev/null || { echo "qr_scan: node not found"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
node qr_scan.mjs "$tmp"
rc=0
for img in "$tmp"/qr_*.pgm; do
  want="$(cat "${img%.pgm}.txt")"
  got="$(zbarimg --quiet --raw "$img" 2>/dev/null | head -1 | tr -d '\n')" || got=""
  if [ "$got" = "$want" ]; then
    printf '  PASS  scans back to its payload (%s bytes)\n' "${#want}"
  else
    printf '  FAIL  %s bytes: got %q\n' "${#want}" "$got"; rc=1
  fi
done
[ "$rc" = 0 ] && echo "RESULT: ALL PASS" || echo "RESULT: FAILURES"
exit $rc
