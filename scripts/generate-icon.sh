#!/bin/bash
# Genera l'icona dell'app da App/AppIcon.svg.
# Produce:
#   - App/AppIcon.icns                      (usato dal bundle da terminale, build-macos.sh)
#   - App/Assets.xcassets/AppIcon.appiconset (usato dal progetto Xcode)
#
# Richiede rsvg-convert (brew install librsvg) e iconutil (di sistema).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SVG="$ROOT/App/AppIcon.svg"
if [[ ! -f "$SVG" ]]; then
    printf 'Sorgente non trovato: %s\n' "$SVG" >&2
    exit 1
fi

# Converte l'SVG in PNG quadrato alla dimensione richiesta.
render() {
    local size="$1" out="$2"
    if command -v rsvg-convert >/dev/null 2>&1; then
        rsvg-convert -w "$size" -h "$size" "$SVG" -o "$out"
    elif command -v qlmanage >/dev/null 2>&1; then
        # Fallback: anteprima QuickLook poi ridimensiona.
        local tmp; tmp="$(mktemp -d)"
        qlmanage -t -s "$size" -o "$tmp" "$SVG" >/dev/null 2>&1
        sips -z "$size" "$size" "$tmp"/*.png --out "$out" >/dev/null
        rm -rf "$tmp"
    else
        printf 'Serve rsvg-convert (brew install librsvg).\n' >&2
        exit 1
    fi
}

# --- .icns per il bundle da terminale ---
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
render 16   "$ICONSET/icon_16x16.png"
render 32   "$ICONSET/icon_16x16@2x.png"
render 32   "$ICONSET/icon_32x32.png"
render 64   "$ICONSET/icon_32x32@2x.png"
render 128  "$ICONSET/icon_128x128.png"
render 256  "$ICONSET/icon_128x128@2x.png"
render 256  "$ICONSET/icon_256x256.png"
render 512  "$ICONSET/icon_256x256@2x.png"
render 512  "$ICONSET/icon_512x512.png"
render 1024 "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$ROOT/App/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

# --- Asset catalog per Xcode ---
APPICONSET="$ROOT/App/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$APPICONSET"
render 16   "$APPICONSET/icon_16.png"
render 32   "$APPICONSET/icon_32.png"
render 64   "$APPICONSET/icon_64.png"
render 128  "$APPICONSET/icon_128.png"
render 256  "$APPICONSET/icon_256.png"
render 512  "$APPICONSET/icon_512.png"
render 1024 "$APPICONSET/icon_1024.png"

cat > "$ROOT/App/Assets.xcassets/Contents.json" <<'EOF'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF

cat > "$APPICONSET/Contents.json" <<'EOF'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF

printf 'Icona generata:\n  %s\n  %s\n' "$ROOT/App/AppIcon.icns" "$APPICONSET"
