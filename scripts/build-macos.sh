#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${PAOLA_BUILD_CONFIGURATION:-debug}"
UNIVERSAL="${PAOLA_UNIVERSAL:-0}"
case "$CONFIGURATION" in
    debug|release) ;;
    *) printf 'PAOLA_BUILD_CONFIGURATION deve essere debug oppure release.\n' >&2; exit 1 ;;
esac
case "$UNIVERSAL" in
    0|1) ;;
    *) printf 'PAOLA_UNIVERSAL deve essere 0 oppure 1.\n' >&2; exit 1 ;;
esac
if [[ -n "${PAOLA_BUILD_NUMBER:-}" && ! "$PAOLA_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    printf 'PAOLA_BUILD_NUMBER deve essere un intero positivo.\n' >&2
    exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
    printf '%s\n' "Serve Xcode completo: i Command Line Tools non includono SwiftDataMacros." >&2
    printf '%s\n' "Dopo l'installazione: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi

BUILD_ARGS=(--configuration "$CONFIGURATION" --product PaolaGestionale)
if [[ -n "${PAOLA_BUILD_PATH:-}" ]]; then
    BUILD_ARGS+=(--scratch-path "$PAOLA_BUILD_PATH")
fi
if [[ "$UNIVERSAL" == 1 ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
xcrun swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(xcrun swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP="${PAOLA_APP_OUTPUT:-$ROOT/build/Paola Gestionale.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 755 "$BIN_DIR/PaolaGestionale" "$APP/Contents/MacOS/PaolaGestionale"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string PaolaGestionale "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string local.paola.gestionale.preview "$APP/Contents/Info.plist"
plutil -replace PaolaCloudEnabled -string NO "$APP/Contents/Info.plist"
plutil -replace PaolaCloudContainerIdentifier -string "" "$APP/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string 14.0 "$APP/Contents/Info.plist"
plutil -replace CFBundleSupportedPlatforms -json '["MacOSX"]' "$APP/Contents/Info.plist"
if [[ -n "${PAOLA_BUILD_NUMBER:-}" ]]; then
    plutil -replace CFBundleVersion -string "$PAOLA_BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
plutil -lint "$APP/Contents/Info.plist"
if plutil -convert xml1 -o - "$APP/Contents/Info.plist" | grep -Eq '\$\(|\$\{'; then
    printf 'Info.plist contiene variabili di build non risolte.\n' >&2
    exit 1
fi
if [[ "$UNIVERSAL" == 1 ]]; then
    xcrun lipo "$APP/Contents/MacOS/PaolaGestionale" -verify_arch arm64 x86_64
fi
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf '\nApp macOS (%s, firma ad hoc): %s\n' "$CONFIGURATION" "$APP"
printf 'Avvio: open "%s"\n' "$APP"
