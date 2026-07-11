#!/usr/bin/env bash
set -euo pipefail

# Builds the native EC25 Manager.app (SwiftUI-free AppKit menu-bar app):
#   1. release-builds the Swift executable
#   2. renders the app icon (.icns)
#   3. assembles the .app bundle, bundling libusb and rewiring @rpath
#   4. writes a menu-bar (LSUIElement) Info.plist and ad-hoc code-signs
#
# No Electron, no helper process — the app links libusb directly.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="EC25 Manager"
VERSION="${EC25_VERSION:-0.4.2}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

cd "$ROOT_DIR"

echo "==> [1/5] Release build"
CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache" swift build -c release --scratch-path "$ROOT_DIR/.build"
BIN="$ROOT_DIR/.build/release/EC25Manager"
[[ -x "$BIN" ]] || { echo "build missing"; exit 1; }

echo "==> [2/5] App icon"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"
ICONSET="$(mktemp -d)/EC25.iconset"; mkdir -p "$ICONSET"
swift "$ROOT_DIR/Tools/make_icon.swift" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/EC25Manager.icns"

echo "==> [3/5] Assemble bundle"
cp "$BIN" "$CONTENTS/MacOS/EC25Manager"
chmod 755 "$CONTENTS/MacOS/EC25Manager"

LIBUSB_SRC="$(brew --prefix libusb)/lib/libusb-1.0.0.dylib"
cp "$LIBUSB_SRC" "$CONTENTS/Frameworks/libusb-1.0.0.dylib"
chmod 755 "$CONTENTS/Frameworks/libusb-1.0.0.dylib"
install_name_tool -id "@rpath/libusb-1.0.0.dylib" "$CONTENTS/Frameworks/libusb-1.0.0.dylib"
OLD_REF="$(otool -L "$CONTENTS/MacOS/EC25Manager" | awk '/libusb-1.0/{print $1; exit}')"
[[ -n "$OLD_REF" ]] && install_name_tool -change "$OLD_REF" "@rpath/libusb-1.0.0.dylib" "$CONTENTS/MacOS/EC25Manager"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/EC25Manager"

echo "==> [4/5] Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleDisplayName</key><string>EC25 Manager</string>
    <key>CFBundleExecutable</key><string>EC25Manager</string>
    <key>CFBundleIconFile</key><string>EC25Manager</string>
    <key>CFBundleIdentifier</key><string>one.nickspace.ec25-manager</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>EC25 Manager</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> [5/5] Code sign (ad-hoc)"
codesign --force --sign - "$CONTENTS/Frameworks/libusb-1.0.0.dylib"
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "Done: $APP_DIR"
du -sh "$APP_DIR" | awk '{print "Size: "$1}'
