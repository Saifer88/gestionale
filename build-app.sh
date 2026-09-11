#!/bin/bash
# Crea "Paola Gestionale.app" in locale, da testare senza pubblicare nulla.
#
# Uso:
#   ./build-app.sh                 build Debug (veloce, solo architettura corrente)
#   PAOLA_BUILD_CONFIGURATION=release ./build-app.sh    build Release
#   PAOLA_UNIVERSAL=1 ./build-app.sh                    binario universale Intel + Apple Silicon
#   PAOLA_OPEN=1 ./build-app.sh                         apre l'app al termine
#   PAOLA_RUN_TESTS=1 ./build-app.sh                    esegue prima la suite di test
#
# I test NON vengono eseguiti per impostazione predefinita: si avviano solo con
# PAOLA_RUN_TESTS=1, quando si vuole un controllo completo prima di una release.
#
# L'app è firmata solo ad hoc, con CloudKit disattivato e archivio locale.
# Non è una release: per quella usare scripts/package-macos-release.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# Seleziona Xcode completo solo per questo script se DEVELOPER_DIR non è già impostato:
# i soli Command Line Tools non includono i macro plugin di SwiftData.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# Test opzionali del dominio (SwiftPM). Disattivi per impostazione predefinita:
# si eseguono solo con PAOLA_RUN_TESTS=1. La suite è lenta e va lanciata a mano
# quando serve (es. prima di una release), non a ogni build.
if [[ "${PAOLA_RUN_TESTS:-0}" == 1 ]]; then
    printf 'Eseguo la suite di test (PAOLA_RUN_TESTS=1)...\n'
    xcrun swift test
fi

APP_OUTPUT="${PAOLA_APP_OUTPUT:-$ROOT/Paola Gestionale.app}"

PAOLA_APP_OUTPUT="$APP_OUTPUT" bash "$ROOT/scripts/build-macos.sh"

if [[ "${PAOLA_OPEN:-0}" == 1 ]]; then
    open "$APP_OUTPUT"
fi
