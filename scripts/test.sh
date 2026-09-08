#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/cache
xcrun swiftc -D PIN_TESTS -parse-as-library Sources/PinFenster.swift Tests/PinEngineTests.swift \
  -module-cache-path build/cache -framework AppKit -framework SwiftUI \
  -framework ApplicationServices -o build/PinEngineTests
build/PinEngineTests
