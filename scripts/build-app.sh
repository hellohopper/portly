#!/bin/bash
# Builds the Porty Swift package and packages it into Porty.app.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP_NAME="Porty"
BUILD_DIR=".build/${CONFIG}"
APP_BUNDLE=".build/${APP_NAME}.app"

echo "==> Building (${CONFIG})"
swift build -c "${CONFIG}"

echo "==> Packaging ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Set SIGN_IDENTITY to a "Developer ID Application: ..." identity (see
# `security find-identity -v -p codesigning`) to produce a build that can be
# notarized via scripts/notarize.sh. Falls back to ad-hoc signing otherwise,
# which is fine for local testing but will be blocked by Gatekeeper elsewhere.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "==> Signing with '${SIGN_IDENTITY}' (hardened runtime)"
    codesign --force --deep --options runtime \
        --entitlements "Resources/Porty.entitlements" \
        --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
else
    echo "==> Ad-hoc signing (set SIGN_IDENTITY for a notarizable build)"
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi

echo "==> Done: ${APP_BUNDLE}"
echo "    Run with: open ${APP_BUNDLE}"
