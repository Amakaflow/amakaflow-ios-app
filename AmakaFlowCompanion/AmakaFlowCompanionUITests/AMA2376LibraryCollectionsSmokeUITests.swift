//
//  AMA2376LibraryCollectionsSmokeUITests.swift
//  AmakaFlowCompanionUITests
//
//  AMA-2376 Task 5: smoke coverage for the Library Pinned + Collections grid.
//  Self-contained mock-Clerk launch (fixtures), no live backend required.
//

import XCTest

final class AMA2376LibraryCollectionsSmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "UITEST_CLERK_TEST_SESSION": "user_id=user_ama2376_smoke,email=ama2376@example.test,name=AMA2376 Smoke",
            "UITEST_SKIP_ONBOARDING": "true",
            "UITEST_SKIP_APPLE_WATCH": "true",
            "UITEST_USE_FIXTURES": "true"
        ]
        app.launch()
        dismissBlockingModalsIfPresent()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testLibraryShowsPinnedAndCollectionsSections() throws {
        XCTAssertTrue(
            TestAuthHelper.waitForMainContent(app, timeout: 20),
            "App should reach authenticated tab chrome with mock Clerk session"
        )

        let libraryTab = TestAuthHelper.tab(app, "library_tab", label: "Library")
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 10), "Library tab should exist")
        libraryTab.tap()

        let libraryScreen = element("library_screen")
        XCTAssertTrue(libraryScreen.waitForExistence(timeout: 15), "Library screen should open")

        // Collections header + "+ New" always render, even with an empty grid.
        let collectionsSection = element("af_collections_section")
        XCTAssertTrue(collectionsSection.waitForExistence(timeout: 10), "Collections section should render")

        let newCollectionButton = element("af_collection_new")
        XCTAssertTrue(newCollectionButton.exists, "'+ New' collection action should be present")
        XCTAssertTrue(newCollectionButton.isHittable, "'+ New' collection action should be tappable")

        // Browse mode: flat Results list must not appear (Approach A).
        let results = element("af_library_results")
        XCTAssertTrue(
            results.waitForNonExistence(timeout: 5),
            "Browse mode must not show Results / flat list when search empty and source All"
        )

        // Enter filter mode via Manual source pill (pills stay visible under search).
        let manualPill = element("af_library_kind_workout")
        XCTAssertTrue(manualPill.waitForExistence(timeout: 5), "Manual source pill should be visible in browse")
        manualPill.tap()

        XCTAssertTrue(
            results.waitForExistence(timeout: 5),
            "Selecting a non-All source must reveal Results"
        )

        // Return to browse
        let allPill = element("af_library_kind_all")
        XCTAssertTrue(allPill.waitForExistence(timeout: 5))
        allPill.tap()
        XCTAssertTrue(
            results.waitForNonExistence(timeout: 2),
            "Clearing source filter back to All must hide Results"
        )

        attachScreenshot(named: "library-pinned-collections")

        // Pinned section is optional (hidden when there are no pins); when present,
        // Edit must be available so unpin is reachable.
        let pinnedSection = element("af_pinned_section")
        if pinnedSection.exists {
            let editButton = element("af_pinned_edit")
            XCTAssertTrue(
                editButton.waitForExistence(timeout: 3),
                "Pinned section should expose Edit when pins exist"
            )
            XCTAssertTrue(editButton.isHittable, "Pinned Edit should be tappable")
        }
    }

    func testNewCollectionPromptCreatesAndNavigates() throws {
        XCTAssertTrue(
            TestAuthHelper.waitForMainContent(app, timeout: 20),
            "App should reach authenticated tab chrome with mock Clerk session"
        )

        let libraryTab = TestAuthHelper.tab(app, "library_tab", label: "Library")
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 10), "Library tab should exist")
        libraryTab.tap()

        let newCollectionButton = element("af_collection_new")
        XCTAssertTrue(newCollectionButton.waitForExistence(timeout: 15), "'+ New' collection action should render")
        newCollectionButton.tap()

        let nameField = app.textFields["Collection name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "New collection alert should show a name field")
        nameField.tap()
        nameField.typeText("AMA-2376 Smoke Collection")

        app.buttons["Create"].tap()

        // AMA-2376 Task 6: creating a collection navigates to its real detail screen.
        let detail = element("af_collection_detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "Creating a collection should navigate to its detail screen")

        attachScreenshot(named: "library-new-collection-navigated")
    }

    func testLibrarySearchRevealsResults() throws {
        XCTAssertTrue(TestAuthHelper.waitForMainContent(app, timeout: 20))
        TestAuthHelper.tab(app, "library_tab", label: "Library").tap()
        XCTAssertTrue(element("library_screen").waitForExistence(timeout: 15))

        let results = element("af_library_results")
        XCTAssertTrue(
            results.waitForNonExistence(timeout: 5),
            "Browse mode must not show Results before search"
        )

        let search = element("af_library_search")
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Library search field should be present")
        search.tap()
        search.typeText("HIIT")

        XCTAssertTrue(
            results.waitForExistence(timeout: 5),
            "Non-empty search must reveal Results"
        )

        // Clearing the query must return to browse (hide Results).
        search.tap()
        if let value = search.value as? String, !value.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)
            search.typeText(deleteString)
        }

        XCTAssertTrue(
            results.waitForNonExistence(timeout: 5),
            "Clearing search must hide Results"
        )
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dismissBlockingModalsIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 2) {
            allowButton.tap()
        }

        let dontAllowButton = springboard.buttons["Don\u{2019}t Allow"]
        if dontAllowButton.waitForExistence(timeout: 1) {
            dontAllowButton.tap()
        }

        let notNowButton = app.buttons["Not now"]
        if notNowButton.waitForExistence(timeout: 3) {
            notNowButton.tap()
        }
    }
}
