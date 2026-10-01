#!/bin/bash
# Compila y empaqueta WindowMenu.app (requiere Xcode o Command Line Tools)
set -euo pipefail
cd "$(dirname "$0")"

# Versión: VERSION=1.2.3 ./build.sh, o el último tag vX.Y.Z del repo.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
# Firma: SIGN_IDENTITY="WindowMenu Signing" ./build.sh usa el certificado de las releases (ver README).
# Por defecto, ad-hoc.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release

APP="WindowMenu.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/WindowMenu "$APP/Contents/MacOS/WindowMenu"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>WindowMenu</string>
  <key>CFBundleIdentifier</key><string>com.local.windowmenu</string>
  <key>CFBundleExecutable</key><string>WindowMenu</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign "$SIGN_IDENTITY" ${KEYCHAIN:+--keychain "$KEYCHAIN"} "$APP"
echo "✅ Listo: $(pwd)/$APP (v$VERSION)"
echo "   Muévela a /Applications y ábrela:  mv $APP /Applications/ && open /Applications/$APP"
