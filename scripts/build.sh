#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
adhoc=false
architectures="$(uname -m)"
for argument in "$@"; do
  case "$argument" in
    --adhoc) adhoc=true ;;
    --universal) architectures="arm64 x86_64" ;;
    *) echo "Unknown option: $argument" >&2; exit 2 ;;
  esac
done
identity="${SIGNING_IDENTITY:-}"
if ! "$adhoc"; then
  if [ -z "$identity" ] && [ -f .signing-identity.local ]; then
    identity="$(cat .signing-identity.local)"
  fi
  if [ -z "$identity" ]; then
    identities="$(security find-identity -v -p codesigning | sed -nE 's/^[[:space:]]*[0-9]+\) ([0-9A-F]{40}) .*/\1/p')"
    count="$(printf '%s\n' "$identities" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [ "$count" != 1 ]; then
      echo "Set SIGNING_IDENTITY to one valid certificate fingerprint. No automatic ad-hoc fallback." >&2
      exit 1
    fi
    identity="$identities"
  fi
  if [ "$identity" = '-' ]; then echo 'Use --adhoc explicitly for ad-hoc signing.' >&2; exit 2; fi
fi
mkdir -p build/cache build/objects build/PinFenster.app/Contents/MacOS
cp Resources/Info.plist build/PinFenster.app/Contents/Info.plist
objects=()
for architecture in $architectures; do
  object="build/objects/PinFenster-$architecture"
  xcrun swiftc -O -parse-as-library Sources/PinFenster.swift \
    -module-cache-path build/cache -target "$architecture-apple-macos14.0" \
    -framework AppKit -framework SwiftUI -framework ApplicationServices -o "$object"
  objects+=("$object")
done
xcrun lipo -create "${objects[@]}" -output build/PinFenster.app/Contents/MacOS/PinFenster
if "$adhoc"; then
  codesign --force --sign - build/PinFenster.app
  echo 'EXPERIMENTAL: ad-hoc signed, not notarized; permission identity changes on rebuild.'
else
  codesign --force --options runtime --timestamp=none --sign "$identity" build/PinFenster.app
fi
codesign --verify --strict build/PinFenster.app
echo 'Built build/PinFenster.app'
