#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build artifacts
# Pick an actually installed iPhone simulator, never a hard-coded model/version.
sim_id=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); candidates=[x for k,v in d["devices"].items() if "iOS" in k for x in v if x.get("isAvailable") and "iPhone" in x["name"]]; assert candidates,"Install an iOS Simulator runtime in Xcode Settings > Platforms"; print(candidates[0]["udid"])')
xcrun simctl boot "$sim_id" 2>/dev/null || true
xcrun simctl bootstatus "$sim_id" -b
# UI test app receives --ui-testing: no production requests, no credentials.
result="artifacts/Fullscreen-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project AADRIPro.xcodeproj -scheme AADRIPro -configuration Debug \
  -destination "platform=iOS Simulator,id=$sim_id" -derivedDataPath build/tests \
  -resultBundlePath "$result" CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO test | tee build/simulator-tests.log
echo "Test results and screenshots: $result"
