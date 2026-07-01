#!/bin/bash
# Builds Porty.app (release) and packages it into a drag-to-Applications DMG.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Porty"
APP_BUNDLE=".build/${APP_NAME}.app"
DMG_STAGING=".build/dmg-staging"
DMG_PATH=".build/${APP_NAME}.dmg"

echo "==> Building app bundle (release)"
./scripts/build-app.sh release

echo "==> Staging DMG contents"
rm -rf "${DMG_STAGING}" "${DMG_PATH}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

echo "==> Creating ${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDZO \
    "${DMG_PATH}"

rm -rf "${DMG_STAGING}"

echo "==> Done: ${DMG_PATH}"
echo "    Note: this DMG is ad-hoc signed only (not notarized)."
echo "    See scripts/notarize.sh for notarizing with a Developer ID."
