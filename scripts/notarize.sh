#!/bin/bash
# Signs (with a real Developer ID), notarizes, and staples Porty.dmg.
#
# Requires a paid Apple Developer Program membership and:
#   SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#                    (see `security find-identity -v -p codesigning`)
#   APPLE_ID         Apple ID email used for notarization
#   APPLE_TEAM_ID    Your Developer Team ID
#   APPLE_APP_SPECIFIC_PASSWORD
#                    App-specific password generated at appleid.apple.com,
#                    stored in Keychain via:
#                    xcrun notarytool store-credentials "porty-notary" \
#                      --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
#                      --password "$APPLE_APP_SPECIFIC_PASSWORD"
#
# None of these credentials are available in this environment, so this
# script is provided as ready-to-run tooling for whoever holds them.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"
: "${APPLE_ID:?Set APPLE_ID to your Apple ID email}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your Developer Team ID}"

DMG_PATH=".build/Porty.dmg"

echo "==> Building signed (hardened runtime) release DMG"
SIGN_IDENTITY="${SIGN_IDENTITY}" ./scripts/build-dmg.sh

echo "==> Submitting for notarization (this can take a few minutes)"
xcrun notarytool submit "${DMG_PATH}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD or use a stored notarytool profile}" \
    --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "${DMG_PATH}"

echo "==> Done: ${DMG_PATH} is signed, notarized, and stapled."
