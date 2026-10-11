import XCTest

final class FullscreenTests: XCTestCase {
    @MainActor func testVideoCoversScreenAndReturns() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] // Only bundled media; no website registration.
        app.launch()
        let live = app.buttons["home-live"]
        XCTAssertTrue(live.waitForExistence(timeout: 15))
        live.tap()
        let channel = app.buttons["media-demo-live"]
        XCTAssertTrue(channel.waitForExistence(timeout: 10)); channel.tap()
        let expand = app.buttons["expandChannel"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10)); expand.tap()
        let surface = app.descendants(matching: .any).matching(identifier: "videoSurface").firstMatch
        let visible = surface.waitForExistence(timeout: 10)
        if !visible { print("FULLSCREEN HIERARCHY: \(app.debugDescription)") }
        XCTAssertTrue(visible)
        func metrics() -> [String: Any] {
            guard let value = surface.value as? String, let data = value.data(using: .utf8),
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return result
        }
        // SwiftUI clips accessibility frames to safe areas even when the AVPlayerLayer
        // draws underneath them. Measure the actual native UIView bounds and window.
        let geometry = NSPredicate { _, _ in
            let m = metrics()
            guard let w = m["width"] as? Double, let h = m["height"] as? Double,
                  let sw = m["windowWidth"] as? Double, let sh = m["windowHeight"] as? Double,
                  let x = m["x"] as? Double, let y = m["y"] as? Double else { return false }
            return abs(w - sw) < 3 && abs(h - sh) < 3 && abs(x) < 3 && abs(y) < 3
        }
        let landscape = NSPredicate { _, _ in
            let m = metrics()
            return geometry.evaluate(with: surface) && (m["width"] as? Double ?? 0) > (m["height"] as? Double ?? 0)
        }
        expectation(for: landscape, evaluatedWith: surface)
        print("Fullscreen native geometry: \(metrics())")
        waitForExpectations(timeout: 15)
        XCTAssertEqual(metrics()["fit"] as? String, "fill")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Fullscreen-landscape"; shot.lifetime = .keepAlways; add(shot)
        XCUIDevice.shared.orientation = .landscapeRight
        XCUIDevice.shared.orientation = .portrait
        let portraitGeometry = NSPredicate { _, _ in geometry.evaluate(with: surface) && (metrics()["height"] as? Double ?? 0) > (metrics()["width"] as? Double ?? 0) }
        expectation(for: portraitGeometry, evaluatedWith: surface); waitForExpectations(timeout: 10)
        let portrait = XCTAttachment(screenshot: app.screenshot()); portrait.name = "Fullscreen-portrait"; portrait.lifetime = .keepAlways; add(portrait)
        var close = app.buttons["exitFullscreen"]
        if !close.exists { surface.tap(); close = app.buttons["exitFullscreen"] }
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["exitFullscreen"].exists)
    }
}
