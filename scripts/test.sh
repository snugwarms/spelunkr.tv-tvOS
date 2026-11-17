#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift test
if [ "$#" -gt 0 ]; then
  xcodebuild -project Spelunkr.xcodeproj -scheme Spelunkr \
    -destination "$1" -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO test
fi
