#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift test -c release
if [ "$#" -gt 0 ]; then
  xcodebuild -project Spelunkr.xcodeproj -scheme Spelunkr -configuration Release \
    -destination "$1" -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO test
fi
