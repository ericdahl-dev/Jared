#!/bin/bash

set -euxo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/Jared.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS="$ROOT/.github/ExportOptions.plist"

if [[ -n "${GITHUB_REF_NAME:-}" && "$GITHUB_REF_NAME" == v* ]]; then
  VERSION="${GITHUB_REF_NAME#v}"
else
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' JaredUI/Info.plist)"
fi

ARTIFACT_FILENAME="Jared-${VERSION}.zip"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

archive_args=(
  -project Jared.xcodeproj
  -scheme JaredUI
  -configuration Release
  -archivePath "$ARCHIVE_PATH"
  archive
  DEVELOPMENT_TEAM=5HR8E5CWR7
)

if [ -n "${MACOS_CODESIGN_IDENTITY:-}" ]; then
  archive_args+=(
    CODE_SIGN_IDENTITY="$MACOS_CODESIGN_IDENTITY"
    CODE_SIGN_STYLE=Manual
  )
else
  archive_args+=(CODE_SIGN_STYLE=Automatic)
fi

xcodebuild "${archive_args[@]}"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

APP_PATH="$EXPORT_PATH/Jared.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Expected exported app at $APP_PATH" >&2
  exit 1
fi

bash "$ROOT/.github/scripts/notarize-macos-zip.sh" "$APP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARTIFACT_FILENAME"

ls -la "$ARTIFACT_FILENAME"
du -hs "$APP_PATH" "$ARTIFACT_FILENAME"
