# Verification — iOS 0.1.0 — 2026-10-11

## Executed successfully in the preparation environment (Linux)

- Compiled `Core.swift` and `Tests/CoreTests.swift` with the official Swift 6.0.3 Linux toolchain, Swift 5 language mode.
- Ran **19 core checks**: UTF-8/BOM/CRLF/Arabic M3U parsing, quoted commas, relative stream URLs, media classification, deduplication, rejection of HTML/non-network schemes/userinfo, custom-header detection, provider URL credential escaping, trial/paid/offline/revocation boundaries, and a 35,000-channel catalogue.
- Compiled the actual `Core.swift` + `Network.swift` with a test-only identity value type (the native Keychain implementation is not replaced in the app).
- Ran **10 network fixture checks** against a local loopback HTTP server: Xtream categories and media, HLS endpoint choice, series navigation, episode ordering, EPG decoding, playlist redirects, streamed response size cap, rejection of authenticated redirects, rejection of HTML error pages and website license mapping.
- Parsed all app Swift sources with the Swift compiler frontend. This validates Swift syntax but **does not type-check SwiftUI/UIKit/AVFoundation** without an Apple SDK.
- Independently parsed all Swift files (including tests) with a Swift grammar parser.
- Parsed the OpenStep Xcode project; every object reference resolves. Confirmed the source/resource paths, XML scheme, plist and asset catalogs.
- Validated shell scripts with `bash -n`.
- Inspected bundled sample media: H.264 video at 1280×720 and AAC audio, approximately 8 seconds.
- No website registration, live account access, or production modification was performed.

## Native Apple validation

- Xcode 16.4 on macOS 15: Release iOS Simulator build succeeded for arm64 and x86_64, including native SwiftUI, UIKit, AVFoundation, Security and CryptoKit compilation/linking.
- All 19 core and 10 loopback network checks passed on macOS.
- Fullscreen UI test passed: expanded the sample through the real button, verified native AVPlayerLayer-backed view fills the window in landscape (874 × 402 points, origin 0,0) and portrait, confirmed default fill mode, captured both screenshots, and returned to the preview. SwiftUI accessibility frames alone clip to safe areas, so the test reads actual UIView bounds converted to window coordinates.
- Successful run: https://github.com/aadrijaouad1/Dreamtv/actions/runs/38144194910
- Tested source commit: `4aef970742c5e0ac686aaebc820f12533563df78`.
- Simulator ZIP SHA-256: `3ef12be39ce10caa8645c49af52f3a3ed9a654ec0b3f3b6b87ba15fed14f51ad`.
- Downloaded artifact checked for ZIP integrity, matching CI checksum, iPhoneSimulator platform and universal arm64/x86_64 executable.

## Not verified

- Native Keychain/AES-GCM persistence on iOS, actual provider playback, Appetize upload and interactive iPhone test.
- iPhone hardware, AirPlay, audio/subtitle track switching, background transitions, account recovery and actual website activation.

The GitHub workflow runs core and network checks, builds the simulator ZIP, then runs the native full-screen test. Review its result before describing this project as a tested iOS binary. An artifact may exist even if the UI test failed; the complete run status and xcresult remain authoritative.

## Known scope

This is a first native iOS port, not complete feature parity with the Windows edition. See README-AR.md for codec limitations and features not ported yet. The simulator artifact contains a compiled `.app`. It does not contain a signed device `.ipa`, Apple distribution identity, or live provider credential.
