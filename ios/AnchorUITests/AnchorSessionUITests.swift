import CoreLocation
import XCTest

/// Drop an anchor, then shrink the session's timer card to just the timer and back.
final class AnchorSessionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDropAnchorAndShrinkTimer() {
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 34.03000, longitude: -118.29000))
        let app = XCUIApplication()
        app.launchArguments = ["-onboarded", "-resetAreas", "-freshStart"]
        app.launch()

        let drop = app.buttons["Drop anchor here"]
        XCTAssertTrue(drop.waitForExistence(timeout: 15))
        shot("5-start")
        // A fresh reading so the anchor can lock on.
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 34.030001, longitude: -118.29000))
        drop.tap()

        let shrink = app.buttons["Shrink to just the timer"]
        XCTAssertTrue(shrink.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["AT YOUR SPOT"].exists)
        shot("6-session")
        shrink.tap()
        let expand = app.buttons["Show the full timer"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Pickups"].exists)
        shot("7-compact")
        expand.tap()
        XCTAssertTrue(app.staticTexts["Pickups"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["ANCHOR_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
}
