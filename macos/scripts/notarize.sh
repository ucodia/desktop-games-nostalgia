#!/bin/bash
# Notarize and staple a signed app or disk image, using a notarytool keychain profile.
set -euo pipefail

TARGET="$1"
PROFILE="${NOTARY_PROFILE:-desktop-games-nostalgia}"

if [ -d "$TARGET" ]; then
    ZIP="$(mktemp -d)/$(basename "$TARGET").zip"
    ditto -c -k --keepParent "$TARGET" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
    rm -f "$ZIP"
else
    xcrun notarytool submit "$TARGET" --keychain-profile "$PROFILE" --wait
fi
xcrun stapler staple "$TARGET"
