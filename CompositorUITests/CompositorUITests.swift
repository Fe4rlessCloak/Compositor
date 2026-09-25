import XCTest

final class CompositorUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func waitForCanvasCreationUI(_ app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        if app.buttons["createCanvas"].exists { return true }
        let welcome = app.buttons["newCanvasWelcome"]
        if welcome.waitForExistence(timeout: timeout) { return true }
        return app.buttons["createCanvas"].exists
    }

    @MainActor
    private func openCanvasCreationSheet(_ app: XCUIApplication) {
        if !app.buttons["createCanvas"].exists {
            app.buttons["newCanvasWelcome"].click()
        }
    }

    @MainActor
    func testCreateCanvasAndNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(waitForCanvasCreationUI(app))
        openCanvasCreationSheet(app)
        let width = app.textFields["widthInput"]
        width.click()
        width.typeKey("a", modifierFlags: .command)
        width.typeText("0")
        XCTAssertFalse(app.buttons["createCanvas"].isEnabled)
        width.typeKey("a", modifierFlags: .command)
        width.typeText("1200")
        let height = app.textFields["heightInput"]
        height.click()
        height.typeKey("a", modifierFlags: .command)
        height.typeText("800")
        app.buttons["createCanvas"].click()
        XCTAssertTrue(app.staticTexts["canvasDimensions"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["canvasDimensions"].value as? String, "1,200 × 800 px")
        app.buttons["actualPixels"].click()
        XCTAssertEqual(app.staticTexts["zoomStatus"].value as? String, "100%")
        app.typeKey("=", modifierFlags: .command)
        XCTAssertEqual(app.staticTexts["zoomStatus"].value as? String, "125%")
        app.buttons["fitCanvas"].click()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Editor foundation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testQuitDuringTextDraftCommitsBeforeCancelingQuit() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(waitForCanvasCreationUI(app))
        openCanvasCreationSheet(app)
        let width = app.textFields["widthInput"]
        XCTAssertTrue(width.waitForExistence(timeout: 5))
        width.click()
        width.typeKey("a", modifierFlags: .command)
        width.typeText("1200")
        let height = app.textFields["heightInput"]
        height.click()
        height.typeKey("a", modifierFlags: .command)
        height.typeText("800")
        app.buttons["createCanvas"].click()

        XCTAssertTrue(app.staticTexts["canvasDimensions"].waitForExistence(timeout: 5))
        app.typeKey("t", modifierFlags: [])
        // Anchor the click to the accessible status text because the AppKit canvas itself is not exposed
        // as an accessibility element. Moving up from the status bar lands inside the canvas.
        app.staticTexts["canvasDimensions"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: -220)).click()
        app.typeText("Quit boundary draft")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "Typing should leave a live text draft")

        app.typeKey("q", modifierFlags: .command)
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5), "Quit should ask how to handle the modified canvas")
        XCTAssertTrue(confirmation.buttons["Save"].exists)
        XCTAssertTrue(confirmation.buttons["Cancel"].exists)
        XCTAssertTrue(confirmation.buttons["Don’t Save"].exists)
        confirmation.buttons["Cancel"].click()

        XCTAssertTrue(app.staticTexts["canvasDimensions"].waitForExistence(timeout: 5), "Cancel should leave the editor open")
        let editText = app.buttons["Edit Text"]
        XCTAssertTrue(editText.waitForExistence(timeout: 5), "The draft should be committed as editable live text")
        XCTAssertTrue(editText.isEnabled)
        XCTAssertFalse(app.buttons["Done"].exists, "The committed text should no longer be an open draft")

        editText.click()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "The committed text should reopen for editing")
        app.typeKey("w", modifierFlags: .command)
        let closeConfirmation = app.sheets.firstMatch
        XCTAssertTrue(closeConfirmation.waitForExistence(timeout: 5), "Closing the project should use the same save confirmation")
        XCTAssertTrue(closeConfirmation.buttons["Save"].exists)
        XCTAssertTrue(closeConfirmation.buttons["Cancel"].exists)
        XCTAssertTrue(closeConfirmation.buttons["Don’t Save"].exists)
        closeConfirmation.buttons["Cancel"].click()

        XCTAssertTrue(app.staticTexts["canvasDimensions"].waitForExistence(timeout: 5), "Cancel should keep the project open")
        XCTAssertTrue(app.buttons["Edit Text"].waitForExistence(timeout: 5), "Closing should finish the reopened text edit")
        XCTAssertFalse(app.buttons["Done"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // Explicit macOS baseline: includes XCTest launch/idle/accessibility overhead.
        let app = XCUIApplication()
        var samples: [Double] = []
        for _ in 0..<5 {
            app.terminate()
            let start = ProcessInfo.processInfo.systemUptime
            app.launch()
            XCTAssertTrue(waitForCanvasCreationUI(app))
            samples.append(ProcessInfo.processInfo.systemUptime - start)
        }
        print("LAUNCH_TO_READY_SECONDS: \(samples)")
        print("LAUNCH_TO_READY_MEDIAN: \(samples.sorted()[2])")
    }
}
