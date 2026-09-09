#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

plutil -lint "$ROOT/App/Info.plist"
BASE_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$ROOT/App/Info.plist")"
if [[ ! "$BASE_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf 'CFBundleShortVersionString deve avere formato major.minor (es. 0.6). La patch è automatica.\n' >&2
    exit 1
fi
BUILD_NUMBER="${PAOLA_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-$(plutil -extract CFBundleVersion raw -o - "$ROOT/App/Info.plist")}}"
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    printf 'Il numero di build deve essere un intero positivo.\n' >&2
    exit 1
fi
# Patch incrementale: in release deriva dal numero di build (github.run_number),
# così ogni release ha una versione major.minor.patch crescente senza modifiche manuali.
VERSION_PATCH="${PAOLA_VERSION_PATCH:-$BUILD_NUMBER}"
if [[ ! "$VERSION_PATCH" =~ ^[0-9]+$ ]]; then
    printf 'PAOLA_VERSION_PATCH deve essere un intero non negativo.\n' >&2
    exit 1
fi
VERSION="${BASE_VERSION}.${VERSION_PATCH}"

OUTPUT_DIR="${PAOLA_RELEASE_OUTPUT:-$ROOT/build/macos-release/dist}"
case "$OUTPUT_DIR" in
    *$'\n'*|*$'\r'*) printf 'Il percorso di output non può contenere ritorni a capo.\n' >&2; exit 1 ;;
esac
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
APP="$OUTPUT_DIR/Paola Gestionale.app"
TAG="v${VERSION}-build.${BUILD_NUMBER}"
ARCHIVE_NAME="PaolaGestionale-macOS-universal-${TAG}.zip"
ARCHIVE_PATH="$OUTPUT_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$OUTPUT_DIR/SHA256SUMS.txt"
NOTES_PATH="$OUTPUT_DIR/RELEASE_NOTES.txt"

PAOLA_BUILD_CONFIGURATION=release \
PAOLA_UNIVERSAL=1 \
PAOLA_BUILD_NUMBER="$BUILD_NUMBER" \
PAOLA_VERSION_PATCH="$VERSION_PATCH" \
PAOLA_LOCAL_BUILD=NO \
PAOLA_BUILD_PATH="${PAOLA_BUILD_PATH:-$ROOT/build/macos-release/swiftpm}" \
PAOLA_APP_OUTPUT="$APP" \
    bash "$ROOT/scripts/build-macos.sh"

xcrun lipo "$APP/Contents/MacOS/PaolaGestionale" -verify_arch arm64 x86_64
codesign --verify --strict "$APP"
if [[ "$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")" != "$VERSION" \
   || "$(plutil -extract CFBundleVersion raw -o - "$APP/Contents/Info.plist")" != "$BUILD_NUMBER" \
   || "$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")" != local.paola.gestionale.preview \
   || "$(plutil -extract PaolaCloudEnabled raw -o - "$APP/Contents/Info.plist")" != NO \
   || "$(plutil -extract PaolaLocalBuild raw -o - "$APP/Contents/Info.plist")" != NO ]]; then
    printf 'Metadati del bundle release inattesi.\n' >&2
    exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE_PATH"
unzip -t "$ARCHIVE_PATH"
(
    cd "$OUTPUT_DIR"
    shasum -a 256 "$ARCHIVE_NAME" > "$CHECKSUM_PATH"
    shasum -a 256 --check "$CHECKSUM_PATH"
)

cat > "$NOTES_PATH" <<EOF
Paola Gestionale ${VERSION} — build ${BUILD_NUMBER}

App universale per Mac Intel e Apple Silicon, macOS 14 o successivo.
Scaricare lo ZIP ed estrarre “Paola Gestionale.app”.
Verificare lo ZIP con: shasum -a 256 --check SHA256SUMS.txt

Firma solo ad hoc: non firmata con Apple Developer ID e non notarizzata.
Gatekeeper può bloccare l'apertura; questa release non offre le garanzie di una distribuzione notarizzata.
CloudKit disabilitato: archivio e backup locali, nessun account o provisioning Apple richiesto.
L'identificativo local.paola.gestionale.preview rimane quello della build locale.
EOF

printf '\nTag: %s\nZIP: %s\nSHA-256: %s\nNote: %s\n' "$TAG" "$ARCHIVE_PATH" "$CHECKSUM_PATH" "$NOTES_PATH"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        printf 'version=%s\n' "$VERSION"
        printf 'tag=%s\n' "$TAG"
        printf 'archive_name=%s\n' "$ARCHIVE_NAME"
        printf 'archive_path=%s\n' "$ARCHIVE_PATH"
        printf 'checksum_path=%s\n' "$CHECKSUM_PATH"
        printf 'notes_path=%s\n' "$NOTES_PATH"
    } >> "$GITHUB_OUTPUT"
fi
