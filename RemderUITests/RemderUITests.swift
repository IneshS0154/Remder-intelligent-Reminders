import XCTest

/// End-to-end tests of Remder's main flows, run in the simulator with ⌘U.
///
/// The app is launched with `-uiTesting` (see `UITestMode` in the app): signed in as a local
/// test user, with an empty in-memory database and no cloud sync, so every test starts clean
/// and nothing touches real reminders or Supabase.
final class RemderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @discardableResult
    private func launch(signedOut: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        // `-useAppleIntelligence NO` sets that preference for this run only, so quick add
        // uses the predictable offline parser.
        app.launchArguments = ["-uiTesting", "-useAppleIntelligence", "NO"] + (signedOut ? ["-signedOut"] : [])
        app.launch()
        self.app = app
        return app
    }

    /// Adds reminders with quick add, one line each, then closes the sheet.
    private func quickAdd(_ lines: String...) {
        app.buttons["New Reminder"].tap()
        let field = app.textFields["quickAdd.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Quick add sheet didn't open")
        for line in lines {
            field.typeText(line + "\n")
        }
        closeSheet()
    }

    /// Drags the quick add sheet down until it's gone (the first drag may only hide the keyboard).
    private func closeSheet() {
        let field = app.textFields["quickAdd.field"]
        for _ in 0..<3 where field.exists {
            let top = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -1.5))
            top.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0)))
            _ = field.waitForNonExistence(timeout: 1)
        }
        XCTAssertFalse(field.exists, "Quick add sheet didn't close")
    }

    private func openSidebar() {
        app.buttons["Menu"].firstMatch.tap()
    }

    private func open(section: String) {
        openSidebar()
        let row = app.buttons[section].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 2), "No “\(section)” in the sidebar")
        row.tap()
    }

    /// Scrolls down gently until the element is on screen (lists only create rows near the screen).
    @discardableResult
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 10) -> XCUIElement {
        for _ in 0..<maxSwipes where !(element.exists && element.isHittable) {
            app.swipeUp(velocity: .slow)
        }
        return element
    }

    /// A button whose label starts with `prefix` (pickers read "Repeat, Never").
    private func button(startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Any element (text, button, cell) whose own label matches.
    private func element(matching format: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: format)).firstMatch
    }

    private func text(_ label: String) -> XCUIElement {
        app.staticTexts[label].firstMatch
    }

    // MARK: - Welcome and sign-in

    func testSignedOutShowsWelcomeScreen() {
        launch(signedOut: true)
        XCTAssertTrue(app.buttons["Continue with Apple"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Continue with Google"].exists)
        XCTAssertTrue(app.buttons["Continue with Email"].exists)
    }

    func testEmailSignInShowsErrorForWrongPassword() {
        launch(signedOut: true)
        app.buttons["Continue with Email"].tap()

        let email = app.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 2))
        email.tap()
        email.typeText("test@remder.app")
        let password = app.secureTextFields.firstMatch
        password.tap()
        password.typeText("wrong")
        app.buttons["auth.submit"].tap()

        XCTAssertTrue(text("That email and password don't match.").waitForExistence(timeout: 3))
    }

    func testEmailSignInOpensTheApp() {
        launch(signedOut: true)
        app.buttons["Continue with Email"].tap()

        let email = app.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 2))
        email.tap()
        email.typeText("test@remder.app")
        let password = app.secureTextFields.firstMatch
        password.tap()
        password.typeText("correct-horse")
        app.buttons["auth.submit"].tap()

        XCTAssertTrue(text("No Reminders").waitForExistence(timeout: 3))
    }

    func testCreateAccountNeedsEightCharacterPassword() {
        launch(signedOut: true)
        app.buttons["Continue with Email"].tap()
        app.buttons["Create Account"].firstMatch.tap()

        let fields = app.textFields
        XCTAssertTrue(fields.element(boundBy: 1).waitForExistence(timeout: 2))
        fields.element(boundBy: 0).tap()
        fields.element(boundBy: 0).typeText("Test User")
        fields.element(boundBy: 1).tap()
        fields.element(boundBy: 1).typeText("new@remder.app")
        // Also checks the show-password button, which turns the field into plain text.
        app.buttons["Show password"].tap()
        let password = fields.element(boundBy: 2)
        XCTAssertTrue(password.waitForExistence(timeout: 2))
        password.tap()
        password.typeText("short")

        XCTAssertFalse(app.buttons["auth.submit"].isEnabled, "Should need 8+ characters")
        XCTAssertTrue(text("At least 8 characters").exists)
        password.typeText("-but-long-enough")
        XCTAssertTrue(app.buttons["auth.submit"].isEnabled)
    }

    // MARK: - Reminders

    func testStartsEmpty() {
        launch()
        XCTAssertTrue(text("No Reminders").waitForExistence(timeout: 3))
    }

    func testQuickAddCreatesReminderWithCategory() {
        launch()
        quickAdd("Call mom tomorrow 5pm #Family !high")

        XCTAssertTrue(text("Call mom").waitForExistence(timeout: 3))
        // The new #Family category shows up as a filter chip.
        XCTAssertTrue(app.buttons["Family"].waitForExistence(timeout: 2))
    }

    func testQuickAddKeepsSheetOpenForSeveralReminders() {
        launch()
        quickAdd("Buy milk tomorrow 9am", "Pay rent friday 10am", "Water plants every day 8pm")

        XCTAssertTrue(text("Buy milk").waitForExistence(timeout: 3))
        XCTAssertTrue(text("Pay rent").exists)
        XCTAssertTrue(text("Water plants").exists)
    }

    func testCategoryChipFiltersList() {
        launch()
        quickAdd("Standup tomorrow 9am #Work", "Gym tomorrow 7am #Health")
        XCTAssertTrue(app.buttons["Work"].waitForExistence(timeout: 3))

        app.buttons["Work"].tap()
        XCTAssertTrue(text("Standup").waitForExistence(timeout: 2))
        XCTAssertFalse(text("Gym").exists)

        app.buttons["All"].tap()
        XCTAssertTrue(text("Gym").waitForExistence(timeout: 2))
    }

    func testCompletingMovesReminderToCompletedTab() {
        launch()
        quickAdd("Take vitamins tomorrow 9am")

        // Both tabs stay in the view hierarchy, so check the row's circle button, which says
        // whether the reminder is done.
        let complete = app.buttons["Complete Take vitamins"]
        let undo = app.buttons["Mark Take vitamins as not done"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()
        XCTAssertTrue(complete.waitForNonExistence(timeout: 3))

        app.buttons["Completed"].tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        XCTAssertTrue(undo.isHittable, "Should be listed on the Completed tab")

        // And back again.
        undo.tap()
        app.buttons["Active"].tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
    }

    func testSwipeToDeleteRemovesReminder() {
        launch()
        quickAdd("Temporary reminder tomorrow 3pm")

        let row = app.cells.containing(.staticText, identifier: "Temporary reminder").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.tap()

        XCTAssertTrue(app.buttons["Complete Temporary reminder"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(text("No Reminders").waitForExistence(timeout: 2))
    }

    func testTappingReminderOpensEditor() {
        launch()
        quickAdd("Dentist appointment tomorrow 11am")

        text("Dentist appointment").tap()
        XCTAssertTrue(app.navigationBars["Edit Reminder"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["Title"].value as? String, "Dentist appointment")

        // Rename and save.
        let title = app.textFields["Title"]
        title.tap()
        title.typeText(" (moved)")
        app.buttons["Save"].tap()
        XCTAssertTrue(text("Dentist appointment (moved)").waitForExistence(timeout: 3))
    }

    // MARK: - Repeats and places

    /// Opens the full form: long-press "+" and pick "New Reminder…".
    private func openFullForm(title: String) {
        app.buttons["New Reminder"].press(forDuration: 1.2)
        app.buttons["New Reminder…"].tap()
        let field = app.textFields["Title"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(title)
    }

    func testCustomRepeatEditor() {
        launch()
        openFullForm(title: "Swim")

        app.navigationBars.firstMatch.tap()  // Hide the keyboard first.
        scrollTo(button(startingWith: "Repeat")).tap()
        app.buttons["Custom…"].tap()
        XCTAssertTrue(app.navigationBars["Custom Repeat"].waitForExistence(timeout: 3))

        // Add Friday to the day it already repeats on, and check the summary follows.
        app.buttons["Friday"].tap()
        XCTAssertTrue(element(matching: "label BEGINSWITH 'Weekly on' AND label CONTAINS 'Fri'").waitForExistence(timeout: 2))
        app.buttons["Done"].tap()

        XCTAssertTrue(scrollTo(element(matching: "label CONTAINS 'Weekly on'"), maxSwipes: 4).exists)
        app.buttons["Save"].tap()
        XCTAssertTrue(text("Swim").waitForExistence(timeout: 3))
    }

    func testPlaceReminderNeedsAPlace() {
        launch()
        openFullForm(title: "Buy stamps")

        app.buttons["At a Place"].tap()
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Can't save a place reminder without a place")
        XCTAssertFalse(app.switches["Alarm"].exists, "Alarms need a time")

        app.buttons["Choose a Place"].tap()
        XCTAssertTrue(app.navigationBars["Place"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Current Location"].exists)
        app.buttons["Cancel"].firstMatch.tap()
    }

    func testDailyBriefAndPlacesSettings() {
        launch()
        open(section: "Settings")
        let morning = scrollTo(app.switches["Morning Summary"])
        XCTAssertTrue(morning.exists)
        XCTAssertEqual(morning.value as? String, "1", "On by default")
        XCTAssertTrue(app.switches["Evening Check-in"].exists)
        XCTAssertTrue(scrollTo(button(startingWith: "Home")).exists)
        XCTAssertTrue(button(startingWith: "Work").exists)
    }

    // MARK: - Navigation

    func testMenuButtonOpensSidebarSections() {
        launch()
        open(section: "Settings")
        XCTAssertTrue(text("Test User").waitForExistence(timeout: 2))
        XCTAssertTrue(text("test@remder.app").exists)

        open(section: "About")
        XCTAssertTrue(text("About").waitForExistence(timeout: 2))
        XCTAssertTrue(text("Quick add").exists)
        XCTAssertTrue(text("Synced to your account").exists)

        open(section: "Insights")
        XCTAssertTrue(text("Insights").waitForExistence(timeout: 2))
    }

    func testSwipeFromLeftEdgeOpensSidebar() {
        launch()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Add Category"].exists)
    }

    func testAddCategoryFromSidebar() {
        launch()
        openSidebar()
        app.buttons["Add Category"].tap()

        let name = app.textFields["Category name"]
        XCTAssertTrue(name.waitForExistence(timeout: 2))
        name.tap()
        name.typeText("Errands")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.buttons["Errands"].waitForExistence(timeout: 2))
    }

    // MARK: - Account

    func testSignOutReturnsToWelcomeScreen() {
        launch()
        quickAdd("Something to forget tomorrow 1pm")
        open(section: "Settings")

        let signOut = app.buttons["Sign Out"].firstMatch
        for _ in 0..<5 where !signOut.isHittable { app.swipeUp() }
        signOut.tap()
        // Confirm in the dialog.
        let confirm = app.buttons.matching(identifier: "Sign Out").element(boundBy: 1)
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.tap()

        XCTAssertTrue(app.buttons["Continue with Email"].waitForExistence(timeout: 3))
    }
}
