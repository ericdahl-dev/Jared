#!/bin/bash
# Submit a zip of Jared.app for notarization and staple the app bundle.
set -euo pipefail

APP="${1:?Usage: notarize-macos-zip.sh path/to/Jared.app}"
PROFILE="${NOTARY_KEYCHAIN_PROFILE:-notarytool}"

if [ ! -d "$APP" ]; then
  echo "Not a bundle: $APP" >&2
  exit 1
fi

for var in APPLE_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_TEAM_ID; do
  if [ -z "${!var:-}" ]; then
    echo "Missing $var — skipping notarization." >&2
    exit 0
  fi
done

if ! xcrun notarytool history --keychain-profile "$PROFILE" &>/dev/null; then
  echo "Storing notary credentials in keychain profile: $PROFILE"
  xcrun notarytool store-credentials "$PROFILE" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD"
fi

submit_zip="$(mktemp -t jared-notarize).zip"
trap 'rm -f "$submit_zip"' EXIT

ditto -c -k --keepParent "$APP" "$submit_zip"

echo "Submitting $submit_zip for notarization..."
submit_output="$(mktemp)"
if ! xcrun notarytool submit "$submit_zip" --keychain-profile "$PROFILE" --wait 2>&1 | tee "$submit_output"; then
  echo "notarytool submit failed." >&2
  exit 1
fi

if grep -q 'status: Invalid' "$submit_output"; then
  submission_id="$(sed -n 's/^[[:space:]]*id:[[:space:]]*//p' "$submit_output" | head -1)"
  echo "Notarization rejected (Invalid)." >&2
  if [ -n "$submission_id" ]; then
    xcrun notarytool log "$submission_id" --keychain-profile "$PROFILE" || true
  fi
  exit 1
fi
rm -f "$submit_output"

echo "Stapling notarization ticket to $APP..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "Notarization complete: $APP"
