import CoreLocation
import XCTest

/// Drives the real app: shrink the sheet, draw an area by tapping the map, save it, and start in it.
final class DrawAreaUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testShrinkSheetDrawAreaSaveAndStart() {
        // Somewhere away from the library's zone, so the only area is the one drawn here.
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 34.03000, longitude: -118.29000))
        let app = XCUIApplication()
        app.launchArguments = ["-onboarded", "-resetAreas", "-freshStart"]
        app.launch()

        // Drag the sheet down: the slim bar shows instead.
        let handle = app.buttons["Hide options and show the map"]
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        handle.tap()
        XCTAssertTrue(app.buttons["Drop anchor"].waitForExistence(timeout: 5))
        shot("1-collapsed")

        // Draw: four taps around the middle of the map make four corners.
        app.buttons["Draw"].tap()
        XCTAssertTrue(app.staticTexts["Tap the map at each corner of your area"].waitForExistence(timeout: 5))
        let map = app.maps.firstMatch
        for (dx, dy) in [(0.30, 0.38), (0.70, 0.38), (0.70, 0.58), (0.30, 0.58)] {
            map.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
        }
        XCTAssertTrue(app.staticTexts["4 corners"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save area"].isEnabled)
        shot("2-drawing")

        // Undo takes one away.
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts["3 corners"].waitForExistence(timeout: 5))
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.58)).tap()
        XCTAssertTrue(app.staticTexts["4 corners"].waitForExistence(timeout: 5))

        // Save and name it.
        app.buttons["Save area"].tap()
        let alert = app.alerts["Name this area"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap()
        field.clearAndType("Desk area")
        alert.buttons["Save"].tap()
        // The simulator only sends a reading when the location changes; a phone sends one every second.
        for nudge in 1...3 {
            XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 34.03 + Double(nudge) * 0.000001,
                                                                           longitude: -118.29))
        }

        // You're standing inside it: it's on the map and you can start in it.
        let start = app.buttons["Start in Desk area"]
        XCTAssertTrue(start.waitForExistence(timeout: 45))
        shot("3-saved")
        // The bar is down: the start button is in it.
        start.tap()
        XCTAssertTrue(app.staticTexts["DESK AREA"].waitForExistence(timeout: 10))
        shot("4-session")
    }

    /// With ANCHOR_SHOTS set (TEST_RUNNER_ANCHOR_SHOTS for xcodebuild), saves a screenshot there.
    @MainActor
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["ANCHOR_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        if let current = value as? String, !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
