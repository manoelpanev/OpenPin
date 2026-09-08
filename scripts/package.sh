#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app=build/OpenPin.app
codesign --verify --strict "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
archs="$(xcrun lipo -archs "$app/Contents/MacOS/OpenPin")"
architecture="${archs// /-}"
if [[ "$archs" == *arm64* && "$archs" == *x86_64* ]]; then architecture=universal; fi
mkdir -p build dist
stage="$(mktemp -d "$PWD/build/dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/OpenPin.app"
ln -s /Applications "$stage/Applications"
cp README.md "$stage/READ-ME.md"
image="dist/OpenPin-$version-experimental-$architecture.dmg"
hdiutil create -volname 'OpenPin Experimental' -srcfolder "$stage" -ov -format UDZO "$image"
hdiutil verify "$image"
(cd dist && shasum -a 256 "$(basename "$image")" > "$(basename "$image").sha256")
echo "Packaged $image"
