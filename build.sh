#!/bin/bash
# Compila y empaqueta WindowMenu.app (requiere Xcode o Command Line Tools)
set -euo pipefail
cd "$(dirname "$0")"

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
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "✅ Listo: $(pwd)/$APP"
echo "   Muévela a /Applications y ábrela:  mv $APP /Applications/ && open /Applications/$APP"
