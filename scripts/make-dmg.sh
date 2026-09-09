#!/bin/bash
# Crea un DMG di installazione drag-and-drop per Paola Gestionale.
# La finestra mostra: app, cartella Applicazioni e una freccia di invito.
#
# Uso:
#   bash scripts/make-dmg.sh <percorso .app> <percorso output .dmg>
#
# Richiede: hdiutil, sips, osascript, rsvg-convert (o fallback QuickLook) per lo sfondo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

APP_SRC="${1:?Serve il percorso della app (.app) come primo argomento.}"
DMG_OUT="${2:?Serve il percorso di output (.dmg) come secondo argomento.}"

if [[ ! -d "$APP_SRC" ]]; then
    printf 'App non trovata: %s\n' "$APP_SRC" >&2
    exit 1
fi

VOL_NAME="Paola Gestionale"
APP_NAME="$(basename "$APP_SRC")"
WORK="$(mktemp -d)"
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"

# Copia app e crea alias verso Applicazioni.
cp -R "$APP_SRC" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"

# Genera lo sfondo PNG (640x400) dall'SVG.
BG_SVG="$ROOT/App/DMGBackground.svg"
BG_PNG="$STAGE/.background/background.png"
if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 640 -h 400 "$BG_SVG" -o "$BG_PNG"
else
    tmp="$(mktemp -d)"
    qlmanage -t -s 640 -o "$tmp" "$BG_SVG" >/dev/null 2>&1
    sips -z 400 640 "$tmp"/*.png --out "$BG_PNG" >/dev/null
    rm -rf "$tmp"
fi

# DMG scrivibile temporaneo per impostare il layout.
RW_DMG="$WORK/rw.dmg"
hdiutil create -srcfolder "$STAGE" -volname "$VOL_NAME" -fs HFS+ \
    -format UDRW -ov "$RW_DMG" >/dev/null

# Monta senza mountpoint custom cosi' il Finder registra il volume con il suo nome.
ATTACH_OUT="$(hdiutil attach "$RW_DMG" -noautoopen)"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUT" | grep -Eo '/Volumes/.*$' | tail -1)"
if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
    printf 'Mount del DMG non riuscito.\n' >&2
    exit 1
fi

# Layout della finestra (posizioni icone, sfondo, dimensione): best-effort.
# Richiede una sessione GUI con permessi di automazione del Finder; in ambienti
# headless (es. CI) puo' fallire senza compromettere il DMG risultante.
osascript - "$VOL_NAME" "$APP_NAME" <<'OSA' || printf 'Layout DMG non applicato (ambiente senza Finder). DMG creato comunque.\n' >&2
on run argv
    set volName to item 1 of argv
    set appName to item 2 of argv
    tell application "Finder"
        tell disk volName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {200, 120, 840, 520}
            set theViewOptions to the icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 128
            set background picture of theViewOptions to file ".background:background.png"
            set position of item appName of container window to {160, 210}
            set position of item "Applications" of container window to {480, 210}
            update without registering applications
            delay 1
            close
        end tell
    end tell
end run
OSA

sync
hdiutil detach "$MOUNT_DIR" >/dev/null || hdiutil detach "$MOUNT_DIR" -force >/dev/null

# Converte in DMG compresso di sola lettura.
rm -f "$DMG_OUT"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUT" >/dev/null

rm -rf "$WORK"
printf 'DMG creato: %s\n' "$DMG_OUT"
