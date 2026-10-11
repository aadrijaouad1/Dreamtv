#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 5 AADRIPro/Core.swift AADRIPro/Network.swift \
  Tests/NetworkIdentity.swift Tests/NetworkTests.swift \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Tests/NetworkInfo.plist \
  -o build/network-tests
port_file=$(mktemp)
python3 Tests/fixture-server.py "$port_file" &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true; rm -f "$port_file"' EXIT
for attempt in {1..50}; do
  if [[ -s "$port_file" ]]; then break; fi
  sleep 0.1
done
fixture_url="http://127.0.0.1:$(cat "$port_file")"
curl --fail --silent "$fixture_url/list.m3u" >/dev/null
./build/network-tests "$fixture_url"
