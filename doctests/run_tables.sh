#!/usr/bin/env bash
# Compile and run every table in this directory, then the view probe.
#
# The C++ tables are plain C++ over the pure headers in ../src and need a Qt6Core and nothing
# else — no app, no backend, no GUI. qr_table.mjs needs node. The probes need a Qt Quick runtime
# and skip without one.
#
# Qt is located in this order: $QT_DIR, then pkg-config, then the qtbase in the module's own
# nix closure. Framework and non-framework layouts both work.
set -uo pipefail
cd "$(dirname "$0")"

if [ -n "${QT_DIR:-}" ]; then
    QT="$QT_DIR"
elif pkg-config --exists Qt6Core 2>/dev/null; then
    QT=""
else
    # Qt6 ships CMake config rather than a .pc, so pkg-config often has nothing to say.
    QT=$(ls -d /nix/store/*-qtbase-external 2>/dev/null | head -1)
    [ -n "$QT" ] || { echo "no Qt6Core: set QT_DIR to a qtbase prefix"; exit 2; }
fi

# Includes and link flags are kept apart because GNU ld resolves left to right:
# a -lQt6Core sitting before the translation unit that needs it contributes
# nothing, and the whole of QtCore comes back undefined at link. Apple's linker
# does not care, so one list works everywhere until it reaches Linux.
if [ -n "$QT" ]; then
    if [ -d "$QT/lib/QtCore.framework" ]; then
        QTINC=(-I"$QT/lib/QtCore.framework/Headers" -F"$QT/lib")
        QTLIB=(-F"$QT/lib" -framework QtCore -Wl,-rpath,"$QT/lib")
    else
        QTINC=(-I"$QT/include" -I"$QT/include/QtCore")
        QTLIB=(-L"$QT/lib" -lQt6Core -Wl,-rpath,"$QT/lib")
    fi
else
    read -r -a QTINC <<< "$(pkg-config --cflags Qt6Core)"
    read -r -a QTLIB <<< "$(pkg-config --libs Qt6Core)"
fi

OUT=$(mktemp -d)
rc=0
# Compiled in parallel: five independent translation units, and each one parses the whole of
# QtCore.
for t in test_*.cpp; do
    ( c++ -std=c++17 -fPIC -I../src "${QTINC[@]}" "$t" "${QTLIB[@]}" -o "$OUT/${t%.cpp}" \
        2>"$OUT/${t%.cpp}.log" || touch "$OUT/${t%.cpp}.bad" ) &
done
wait
for t in test_*.cpp; do
    bin="$OUT/${t%.cpp}"
    if [ -e "$bin.bad" ]; then
        echo "  BUILD FAILED  $t"
        cat "$bin.log"
        rc=1
        continue
    fi
    echo "=== $t"
    "$bin" || rc=1
done
# The one table that is not C++: the view's QR encoder is JavaScript, and node runs the same
# text the view imports. Loud rather than quiet when node is absent — CI reads a SKIP as a fail.
echo
echo "=== qr_table.mjs"
if command -v node >/dev/null 2>&1; then
    node qr_table.mjs || rc=1
else
    echo "SKIP: no node to run qr_table.mjs"
fi

# And the half a C++ table cannot reach: the view's own bindings, evaluated. It SKIPS with 0
# when there is no Qt Quick runtime to hand, so this stays one command either way.
echo
echo "=== view probes"
./run_view_probe.sh || rc=1

echo
echo "TABLES: $([ $rc -eq 0 ] && echo 'ALL PASS' || echo 'FAILED')"
exit $rc
