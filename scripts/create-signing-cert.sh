#!/bin/bash
# Crea (una sola vez) el certificado autofirmado "WindowMenu Signing" con el que se firman las releases,
# lo sube como secrets del repo y lo importa en tu llavero para poder firmar builds locales.
#
# Las actualizaciones solo se instalan si están firmadas con este mismo certificado, y macOS conserva
# el permiso de Accesibilidad gracias a él: guarda el .p12 y su contraseña (p. ej. en 1Password).
# Si se pierde, quien tenga la app instalada tendrá que reinstalarla con install.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="WindowMenu Signing"
OUT="$HOME/WindowMenu-signing.p12"

if gh secret list | grep -q '^SIGNING_CERT_P12'; then
  echo "❌ El repo ya tiene SIGNING_CERT_P12. Cambiar el certificado rompe las actualizaciones de quien ya la tenga instalada."
  exit 1
fi
if [[ -e "$OUT" ]]; then
  echo "❌ Ya existe $OUT. Bórralo o muévelo antes."
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASSWORD="$(openssl rand -hex 24)"

openssl req -x509 -newkey rsa:2048 -nodes -days 36500 -subj "/CN=$NAME" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"

# El llavero de macOS no lee los .p12 con el cifrado por defecto de OpenSSL 3.
LEGACY=""
openssl version | grep -q '^OpenSSL 3' && LEGACY="-legacy"
openssl pkcs12 -export $LEGACY -name "$NAME" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$OUT" -passout "pass:$PASSWORD"

base64 -i "$OUT" | gh secret set SIGNING_CERT_P12
printf '%s' "$PASSWORD" | gh secret set SIGNING_CERT_PASSWORD

security import "$OUT" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASSWORD" -T /usr/bin/codesign

echo
echo "✅ Certificado creado, subido a los secrets del repo e importado en tu llavero."
echo "   Guarda en un sitio seguro el archivo y su contraseña:"
echo "   Archivo:    $OUT"
echo "   Contraseña: $PASSWORD"
