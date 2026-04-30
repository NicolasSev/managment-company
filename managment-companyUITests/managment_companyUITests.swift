//
//  managment_companyUITests.swift
//  managment-companyUITests
//
//  Created by Nikolas on 15.03.2026.
//

import XCTest

final class managment_companyUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testLoginScreenVisibleOnColdLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["PropManager"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Войти"].exists)
    }

    @MainActor
    func testCreateAccountButtonExists() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Создать аккаунт"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
