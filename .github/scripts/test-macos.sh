#!/bin/bash

set -euxo pipefail

xcodebuild -project Jared.xcodeproj -scheme JaredFramework build \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO

xcodebuild -project Jared.xcodeproj -scheme JaredTests test \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO
