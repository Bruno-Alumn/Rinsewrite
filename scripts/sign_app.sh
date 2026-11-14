#!/bin/sh
# Sign Rinsewrite.app for release, or ad-hoc for a local build.
#
#   scripts/sign_app.sh <app> <identity>
#
# Developer ID builds carry the designated requirement in
# packaging/designated_requirement.txt: the bundle ID plus the maintainer's
# Developer ID team. macOS keeps the Accessibility grant for any build that
# meets it, so rebuilds and updates don't ask again. Other identities (a
# contributor's own certificate, or ad-hoc) sign without it.
#
# Developer ID builds also get a secure timestamp, which notarization needs.
# All builds use the hardened runtime with packaging/Rinsewrite.entitlements.
set -eu

APP=$1
IDENTITY=$2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ENTITLEMENTS="$ROOT/packaging/Rinsewrite.entitlements"
REQUIREMENT=$(cat "$ROOT/packaging/designated_requirement.txt")

case "$IDENTITY" in
    "Developer ID Application:"*) ;;
    *)
        codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
        exit 0
        ;;
esac

# The app has no nested code (frameworks, helpers or plug-ins); if it ever
# does, sign those first, from the inside out.
codesign --force --options runtime --entitlements "$ENTITLEMENTS" --timestamp \
    -r="designated => $REQUIREMENT" --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
if ! codesign --verify -R="$REQUIREMENT" "$APP"; then
    echo "error: $APP doesn't meet packaging/designated_requirement.txt" >&2
    exit 1
fi
