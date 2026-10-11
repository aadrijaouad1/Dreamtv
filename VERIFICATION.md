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

## Supplied but NOT executed here

- Xcode iOS Simulator build, including native SwiftUI/UIKit/AVFoundation type-checking, linking and asset compilation.
- XCTest UI test `FullscreenTests.testVideoCoversScreenAndReturns`. It opens the local sample, taps the actual expand button, checks the native video surface against the entire window in landscape and portrait, checks default `fill`, captures screenshots and returns to the preview. It launches the app in Debug with `--ui-testing`, without registering a production device.
- Native Keychain/AES-GCM persistence on iOS, actual provider playback, Appetize upload and interactive iPhone test.
- iPhone hardware, AirPlay, audio/subtitle track switching, background transitions, account recovery and actual website activation.

The GitHub workflow runs core and network checks, builds the simulator ZIP, then runs the native full-screen test. Review its result before describing this project as a tested iOS binary. An artifact may exist even if the UI test failed; the complete run status and xcresult remain authoritative.

## Known scope

This is a first native iOS port, not complete feature parity with the Windows edition. See README-AR.md for codec limitations and features not ported yet. There is no built `.app`, signed `.ipa`, Apple signing identity, or live credential in this source archive.
