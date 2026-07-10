#!/usr/bin/env bash
set -euo pipefail

# Produces clean, distributable release artifacts for GitHub Releases:
#   dist/EC25-Manager-<version>-<arch>.dmg   (drag-to-Applications installer)
#   dist/EC25-Manager-<version>-<arch>.zip   (ditto archive, preserves signature)
#   dist/SHA256SUMS.txt
#
# Pass --no-build to reuse an already-built dist/EC25 Manager.app.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="EC25 Manager"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
VERSION="${EC25_VERSION:-0.4.0}"
ARCH="$(uname -m)"
BASE="EC25-Manager-$VERSION-$ARCH"
DMG="$DIST_DIR/$BASE.dmg"
ZIP="$DIST_DIR/$BASE.zip"

if [[ "${1:-}" != "--no-build" ]]; then
    echo "==> Building app bundle"
    EC25_VERSION="$VERSION" "$ROOT_DIR/Tools/package_app.sh"
fi
[[ -d "$APP_DIR" ]] || { echo "app bundle missing: $APP_DIR"; exit 1; }

echo "==> Verifying signature"
codesign --verify --strict "$APP_DIR"

echo "==> Building DMG"
STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
cp -R "$APP_DIR" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# strip any Finder cruft
find "$STAGE" -name '.DS_Store' -delete 2>/dev/null || true
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$(dirname "$STAGE")"

echo "==> Building ZIP (ditto, keeps signature + symlinks)"
rm -f "$ZIP"
( cd "$DIST_DIR" && ditto -c -k --keepParent "$APP_NAME.app" "$ZIP" )

echo "==> Checksums"
( cd "$DIST_DIR" && shasum -a 256 "$BASE.dmg" "$BASE.zip" | tee SHA256SUMS.txt )

echo ""
echo "Artifacts:"
ls -lh "$DMG" "$ZIP" | awk '{print "  " $5 "  " $NF}'
