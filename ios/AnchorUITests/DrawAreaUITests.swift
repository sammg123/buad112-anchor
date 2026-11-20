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
    func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["ANCHOR_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
}

extension DrawAreaUITests {
    /// Hold an area to pick it, move a corner and save, then delete it through the glass "are you sure".
    @MainActor
    func testHoldEditAndDeleteArea() {
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 34.03000, longitude: -118.29000))
        let app = XCUIApplication()
        app.launchArguments = ["-onboarded", "-resetAreas", "-freshStart"]
        app.launch()

        let handle = app.buttons["Hide options and show the map"]
        XCTAssertTrue(handle.waitForExistence(timeout: 15))
        handle.tap()
        app.buttons["Draw"].tap()
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        for (dx, dy) in [(0.30, 0.38), (0.70, 0.38), (0.70, 0.58), (0.30, 0.58)] {
            map.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
        }
        app.buttons["Save area"].tap()
        let alert = app.alerts["Name this area"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Save"].tap()

        // Saving brings the sheet back up; drag it down again to see the map.
        let hide = app.buttons["Hide options and show the map"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        hide.tap()
        // You're standing in it, so the slim bar offers Start.
        XCTAssertTrue(app.buttons["Show options"].waitForExistence(timeout: 5))
        sleep(1)
        // Hold inside it (you're standing in it, at the middle of the map): it lights up and the glass bar offers
        // edit and delete.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.47)).press(forDuration: 0.9)
        let edit = app.buttons["Edit My area 1"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        shot("8-selected")

        // Edit: drag corner 3 further out, then save.
        edit.tap()
        let corner = app.otherElements["Corner 3"].exists ? app.otherElements["Corner 3"] : app.images["Corner 3"]
        if corner.waitForExistence(timeout: 5) {
            corner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.2, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.66)))
        }
        shot("9-editing")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Delete My area 1"].waitForExistence(timeout: 5))

        // Delete, with the confirmation.
        app.buttons["Delete My area 1"].tap()
        XCTAssertTrue(app.staticTexts["Delete \u{201C}My area 1\u{201D}?"].waitForExistence(timeout: 5))
        shot("10-confirm")
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.buttons["Edit My area 1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
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
