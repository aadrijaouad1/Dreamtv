#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 5 AADRIPro/Core.swift Tests/CoreTests.swift -o build/core-tests
./build/core-tests
