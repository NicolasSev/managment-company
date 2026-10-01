//
//  managment_companyUITests.swift
//  managment-companyUITests
//
//  Created by Nikolas on 15.03.2026.
//

import XCTest

final class managment_companyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Приложение с чистой auth-сессией: удачный логин соседнего теста иначе
    /// оседает в keychain симулятора, и cold launch показывает дашборд
    /// вместо экрана входа.
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-reset-auth"]
        return app
    }

    /// typeText теряет клавиши с неактивной раскладки клавиатуры симулятора,
    /// поэтому печатаем с проверкой фактического значения и ретраем.
    /// Email-клавиатура держит все нужные символы на основной раскладке.
    private func type(_ text: String, into field: XCUIElement) {
        for _ in 0..<3 {
            field.tap()
            if let value = field.value as? String, value == text { return }
            if let value = field.value as? String, !value.isEmpty, value != text {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
            }
            field.typeText(text)
            if let value = field.value as? String, value == text { return }
        }
        XCTFail("Failed to type '\(text)' — field value: \(String(describing: field.value))")
    }

    @MainActor
    func testLoginScreenVisibleOnColdLaunch() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.staticTexts["PropManager"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Войти"].exists)
    }

    @MainActor
    func testCreateAccountButtonExists() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.buttons["Создать аккаунт"].waitForExistence(timeout: 20))
    }

    @MainActor
    func testDemoDashboardRenders() throws {
        let app = makeApp()
        app.launchEnvironment["API_BASE_URL"] = "http://185.146.3.87/propmanager-api"
        // Пароль подставляется DEBUG-хуком LoginView: клавиатурный ввод в
        // SecureField молча теряет символы с неактивной раскладки симулятора.
        app.launchEnvironment["UITEST_PASSWORD"] = "demo1234"
        app.launch()

        let email = app.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 20))
        type("demo@propmanager.local", into: email)

        let loginButton = app.buttons["Войти"]
        XCTAssertTrue(loginButton.isEnabled, "Login disabled — password not prefilled")
        loginButton.tap()

        // После логина приложение приземляется на таб «Сегодня»
        // (5-позиционная навигация GAP-037; экрана «Дашборд» на корне больше нет).
        let todayTab = app.tabBars.buttons["Сегодня"]
        let appeared = todayTab.waitForExistence(timeout: 60)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        shot.name = appeared ? "main-screen" : "no-main-screen-state-\(app.state.rawValue)"
        add(shot)
        XCTAssertTrue(appeared, "Main tab bar missing after login; app.state=\(app.state.rawValue)")

        // Первый логин поднимает системный запрос уведомлений — закрываем,
        // кнопкой слева («Не разрешать»/«Don't Allow», надпись зависит от локали).
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 10) {
            alert.buttons.element(boundBy: 0).tap()
        }

        sleep(12)
        XCTAssertEqual(app.state, .runningForeground, "App left foreground (crash)")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
