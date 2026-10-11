#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 5 AADRIPro/Core.swift AADRIPro/Network.swift \
  Tests/NetworkIdentity.swift Tests/NetworkTests.swift -o build/network-tests
port_file=$(mktemp)
python3 Tests/fixture-server.py "$port_file" &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true; rm -f "$port_file"' EXIT
for attempt in {1..50}; do
  if [[ -s "$port_file" ]]; then break; fi
  sleep 0.1
done
./build/network-tests "http://127.0.0.1:$(cat "$port_file")"
