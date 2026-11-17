#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
destination="${1:-generic/platform=tvOS Simulator}"
xcodebuild -project Spelunkr.xcodeproj -scheme Spelunkr -configuration Debug \
  -destination "$destination" -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
