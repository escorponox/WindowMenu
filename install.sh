#!/bin/bash
# Instala (o actualiza) WindowMenu en /Applications desde la última release de GitHub.
set -euo pipefail

URL="https://github.com/escorponox/WindowMenu/releases/latest/download/WindowMenu.zip"
APP="/Applications/WindowMenu.app"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Descargando WindowMenu…"
curl -fsSL "$URL" -o "$TMP/WindowMenu.zip"
ditto -x -k "$TMP/WindowMenu.zip" "$TMP"

pkill -x WindowMenu 2>/dev/null || true
rm -rf "$APP"
mv "$TMP/WindowMenu.app" "$APP"
# La app no está notarizada: sin esto Gatekeeper la bloquearía si llegara marcada como descargada.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

open "$APP"
echo "✅ WindowMenu instalada en $APP"
echo "   La primera vez, concédele el permiso de Accesibilidad (Ajustes del Sistema → Privacidad y seguridad)."
