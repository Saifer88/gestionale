#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! xcodebuild -version >/dev/null 2>&1; then
    printf '%s\n' "Serve Xcode completo: i Command Line Tools non includono SwiftDataMacros." >&2
    printf '%s\n' "Dopo l'installazione: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi

xcrun swift build --product PaolaGestionale
BIN_DIR="$(xcrun swift build --show-bin-path)"
APP="${PAOLA_APP_OUTPUT:-$ROOT/build/Paola Gestionale.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 755 "$BIN_DIR/PaolaGestionale" "$APP/Contents/MacOS/PaolaGestionale"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string PaolaGestionale "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string local.paola.gestionale.preview "$APP/Contents/Info.plist"
plutil -replace PaolaCloudEnabled -string NO "$APP/Contents/Info.plist"
plutil -replace PaolaCloudContainerIdentifier -string "" "$APP/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string 14.0 "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf '\nApp locale di sviluppo: %s\n' "$APP"
printf 'Avvio: open "%s"\n' "$APP"
