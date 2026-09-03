#!/usr/bin/env bash
# Load the wallet view under an OFFSCREEN Qt and assert what it says. Every probe_*.qml beside
# this file is run, and one failing fails the lot.
#
# The C++ tables beside this run every rule that is a pure function; this runs the other half —
# the bindings — which no source assertion can evaluate. There is no app, no backend, no module
# host and no window: a Loader, a fabricated backend object, and the view itself.
#
# Qt comes from $QT_QML_DIR / $QML_BIN, else from a qtdeclarative in the nix store. The design
# system comes from $LOGOS_DESIGN_SYSTEM_QML, else a workspace checkout, else the store.
# Anything missing SKIPS with 0: this is an extra level of evidence, not a build dependency.
set -uo pipefail
cd "$(dirname "$0")"

QML_BIN="${QML_BIN:-$(ls -d /nix/store/*-qtdeclarative-*/bin/qml 2>/dev/null | head -1)}"
QT_QML_DIR="${QT_QML_DIR:-$(ls -d /nix/store/*-qtdeclarative-*/lib/qt-6/qml 2>/dev/null | head -1)}"
DS="${LOGOS_DESIGN_SYSTEM_QML:-}"
for c in ../../logos-design-system/src/qml \
         $(ls -d /nix/store/*-logos-design-system-src/src/qml 2>/dev/null | head -1); do
    [ -n "$DS" ] && break
    [ -d "$c" ] && DS="$c"
done

if [ -z "$QML_BIN" ] || [ ! -x "$QML_BIN" ] || [ -z "$QT_QML_DIR" ] || [ -z "$DS" ]; then
    echo "SKIP: no Qt Quick runtime or design system found (set QML_BIN, QT_QML_DIR,"
    echo "      LOGOS_DESIGN_SYSTEM_QML to run the view probe)"
    exit 0
fi

# The style, the SVG plugin and the module host are all absent here, and each is loud about it.
# None of them is what this measures, so their noise is dropped and the probe's own lines are not.
rc=0
for probe in probe_*.qml; do
    echo "--- $probe"
    QT_QPA_PLATFORM=offscreen "$QML_BIN" -I "$QT_QML_DIR" -I "$DS" "$probe" 2>&1 \
        | grep -vE "does not support customization|Unsupported image format|Populating font|createPlatformOpenGLContext|Unable to assign QJSValue|Detected function" \
        | sed 's/^qml: //'
    [ "${PIPESTATUS[0]}" -eq 0 ] || rc=1
done
exit "$rc"
