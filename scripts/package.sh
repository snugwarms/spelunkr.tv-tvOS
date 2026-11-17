#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcodebuild -project Spelunkr.xcodeproj -scheme Spelunkr -configuration Release \
  -destination 'generic/platform=tvOS' -derivedDataPath build/ReleaseData CODE_SIGNING_ALLOWED=NO build
python3 - <<'PY'
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
app = Path('build/ReleaseData/Build/Products/Release-appletvos/Spelunkr.app')
output = Path('build/Spelunkr-tvOS-unsigned.ipa')
with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
    for file in sorted(app.rglob('*')):
        if file.is_file():
            archive.write(file, Path('Payload/Spelunkr.app') / file.relative_to(app))
print(output.resolve())
PY
