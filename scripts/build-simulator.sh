#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]] || ! xcrun --find xcodebuild >/dev/null 2>&1; then
  echo 'This build requires macOS with full Xcode installed. Use the included GitHub Actions workflow from Windows.' >&2
  exit 2
fi
mkdir -p build artifacts
xcodebuild -project AADRIPro.xcodeproj -scheme AADRIPro -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/simulator ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO build | tee build/simulator-build.log
app='build/simulator/Build/Products/Release-iphonesimulator/AADRIPro.app'
test -d "$app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" artifacts/AADRI-PRO-iOS-Simulator.zip
shasum -a 256 artifacts/AADRI-PRO-iOS-Simulator.zip > artifacts/SHA256.txt
echo 'Built artifacts/AADRI-PRO-iOS-Simulator.zip — upload this inner ZIP to Appetize.'
