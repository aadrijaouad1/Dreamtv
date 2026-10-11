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
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        let geometry = NSPredicate { _, _ in
            let screen = app.windows.firstMatch.frame, frame = surface.frame
            return abs(frame.width - screen.width) < 3 && abs(frame.height - screen.height) < 3
        }
        let landscape = NSPredicate { _, _ in geometry.evaluate(with: surface) && surface.frame.width > surface.frame.height }
        expectation(for: landscape, evaluatedWith: surface)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(surface.value as? String, "fill")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Fullscreen-landscape"; shot.lifetime = .keepAlways; add(shot)
        XCUIDevice.shared.orientation = .portrait
        let portraitGeometry = NSPredicate { _, _ in geometry.evaluate(with: surface) && surface.frame.height > surface.frame.width }
        expectation(for: portraitGeometry, evaluatedWith: surface); waitForExpectations(timeout: 10)
        let portrait = XCTAttachment(screenshot: app.screenshot()); portrait.name = "Fullscreen-portrait"; portrait.lifetime = .keepAlways; add(portrait)
        var close = app.buttons["exitFullscreen"]
        if !close.exists { surface.tap(); close = app.buttons["exitFullscreen"] }
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["exitFullscreen"].exists)
    }
}
