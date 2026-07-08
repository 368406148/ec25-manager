#!/usr/bin/env bash
set -euo pipefail

# Builds the EC25 Manager macOS menu-bar app by manual assembly:
#   1. compiles the Swift USB helper (release)
#   2. clones the Electron.app runtime template and injects our front-end
#   3. writes a menu-bar (LSUIElement) Info.plist and app icon
#   4. embeds the helper + libusb and rewires the dylib path
#   5. ad-hoc code-signs the bundle
#
# Manual assembly avoids electron-packager's extract-zip step (unreliable here)
# and is safe because the app has no runtime npm dependencies.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SRC="$ROOT_DIR/app"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="EC25 Manager"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
TEMPLATE="$APP_SRC/node_modules/electron/dist/Electron.app"

cd "$ROOT_DIR"

APP_VERSION="$(node -p "require('$APP_SRC/package.json').version")"

echo "==> [1/5] Building Swift helper (release)"
CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache" swift build -c release --scratch-path "$ROOT_DIR/.build"
HELPER_BIN="$ROOT_DIR/.build/release/EC25Helper"
[[ -x "$HELPER_BIN" ]] || { echo "helper build missing"; exit 1; }

echo "==> [2/5] Preparing icons + Electron runtime"
swift "$ROOT_DIR/Tools/make_tray_icon.swift" "$APP_SRC/assets" >/dev/null
if [[ ! -f "$APP_SRC/assets/icon.icns" ]]; then
    ICONSET="$(mktemp -d)/EC25.iconset"; mkdir -p "$ICONSET"
    swift "$ROOT_DIR/Tools/make_icon.swift" "$ICONSET" >/dev/null
    iconutil -c icns "$ICONSET" -o "$APP_SRC/assets/icon.icns"
fi
[[ -d "$TEMPLATE" ]] || { echo "Electron runtime missing at $TEMPLATE — run 'npm install' in app/"; exit 1; }

rm -rf "$APP_DIR"
mkdir -p "$DIST_DIR"
cp -R "$TEMPLATE" "$APP_DIR"

echo "==> [3/5] Injecting front-end"
mv "$CONTENTS/MacOS/Electron" "$CONTENTS/MacOS/EC25Manager"
rm -f "$CONTENTS/Resources/default_app.asar"
APP_RES="$CONTENTS/Resources/app"
mkdir -p "$APP_RES"
cp "$APP_SRC/main.js" "$APP_SRC/preload.js" "$APP_SRC/package.json" "$APP_RES/"
cp -R "$APP_SRC/src" "$APP_SRC/renderer" "$APP_SRC/assets" "$APP_RES/"
cp "$APP_SRC/assets/icon.icns" "$CONTENTS/Resources/EC25Manager.icns"
# Drop electron's default locale icon so ours is unambiguous.
rm -f "$CONTENTS/Resources/electron.icns"

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
    <key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
    <key>CFBundleVersion</key><string>${APP_VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> [4/5] Embedding helper + libusb"
BIN_DIR="$CONTENTS/Resources/bin"
mkdir -p "$BIN_DIR"
cp "$HELPER_BIN" "$BIN_DIR/EC25Helper"
chmod 755 "$BIN_DIR/EC25Helper"

LIBUSB_SRC="$(brew --prefix libusb)/lib/libusb-1.0.0.dylib"
cp "$LIBUSB_SRC" "$BIN_DIR/libusb-1.0.0.dylib"
chmod 755 "$BIN_DIR/libusb-1.0.0.dylib"
install_name_tool -id "@rpath/libusb-1.0.0.dylib" "$BIN_DIR/libusb-1.0.0.dylib"

OLD_REF="$(otool -L "$BIN_DIR/EC25Helper" | awk '/libusb-1.0/{print $1; exit}')"
if [[ -n "$OLD_REF" ]]; then
    install_name_tool -change "$OLD_REF" "@rpath/libusb-1.0.0.dylib" "$BIN_DIR/EC25Helper"
fi
install_name_tool -add_rpath "@loader_path" "$BIN_DIR/EC25Helper" 2>/dev/null || true

echo "==> [5/5] Code signing (ad-hoc)"
codesign --force --sign - "$BIN_DIR/libusb-1.0.0.dylib"
codesign --force --sign - "$BIN_DIR/EC25Helper"
# Sign the Electron frameworks/helpers, then the outer bundle.
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || codesign --force --sign - "$APP_DIR"

echo ""
echo "Done: $APP_DIR"
