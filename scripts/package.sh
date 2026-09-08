#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app=build/PinFenster.app
codesign --verify --strict "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
archs="$(xcrun lipo -archs "$app/Contents/MacOS/PinFenster")"
architecture="${archs// /-}"
if [[ "$archs" == *arm64* && "$archs" == *x86_64* ]]; then architecture=universal; fi
mkdir -p build dist
stage="$(mktemp -d "$PWD/build/dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/PinFenster.app"
ln -s /Applications "$stage/Applications"
cp README.md "$stage/READ-ME.md"
image="dist/PinFenster-$version-experimental-$architecture.dmg"
hdiutil create -volname 'PinFenster Experimental' -srcfolder "$stage" -ov -format UDZO "$image"
hdiutil verify "$image"
shasum -a 256 "$image" > "$image.sha256"
echo "Packaged $image"
