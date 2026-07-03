import XCTest
@testable import managment_company

/// Зеркальные тесты GAP-050: quick-add личных финансов — тонкий клиент portfolio-dashboard.
@MainActor
final class PersonalFinanceTests: XCTestCase {
    // MARK: - Нормализация суммы (RU-локаль → decimal-строка API)

    func testAmountNormalizationHandlesRuLocale() {
        XCTAssertEqual(PFAmount.validated("4590"), "4590")
        XCTAssertEqual(PFAmount.validated("4590,5"), "4590.5")
        XCTAssertEqual(PFAmount.validated("4 590,50"), "4590.50")
        XCTAssertEqual(PFAmount.validated("4\u{00A0}590.5"), "4590.5")
        XCTAssertEqual(PFAmount.validated(" 12500.50 "), "12500.50")
    }

    func testAmountValidationRejectsInvalidValues() {
        XCTAssertNil(PFAmount.validated(""))
        XCTAssertNil(PFAmount.validated("0"))
        XCTAssertNil(PFAmount.validated("-100"))
        XCTAssertNil(PFAmount.validated("abc"))
        XCTAssertNil(PFAmount.validated("12,5,0"))
    }

    // MARK: - Контракт запроса POST /api/transactions

    func testTransactionRequestEncodesApiContract() throws {
        let request = PFTransactionRequest(
            accountId: "acc-1",
            transactionType: "expense",
            amount: "4590.5",
            categoryId: "cat-1",
            merchant: nil,
            note: "обед"
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["accountId"] as? String, "acc-1")
        XCTAssertEqual(json["transactionType"] as? String, "expense")
        XCTAssertEqual(json["amount"] as? String, "4590.5")
        XCTAssertEqual(json["categoryId"] as? String, "cat-1")
        XCTAssertEqual(json["note"] as? String, "обед")
        XCTAssertEqual(json["source"] as? String, "manual")
        // currencyCode/occurredAt не отправляем: сервер берёт валюту счёта и now().
        XCTAssertNil(json["currencyCode"])
        XCTAssertNil(json["occurredAt"])
    }

    // MARK: - Декодирование ответов (camelCase без {"data": …})

    func testCategoryAndDefaultsDecoding() throws {
        let categoryJSON = """
        [{"id":"c1","slug":"produkty","name":"Продукты","parentId":null,
          "sortOrder":10,"isActive":true,
          "createdAt":"2026-07-03T00:00:00","updatedAt":"2026-07-03T00:00:00"}]
        """
        let categories = try JSONDecoder().decode([PFCategory].self, from: Data(categoryJSON.utf8))
        XCTAssertEqual(categories.first?.slug, "produkty")
        XCTAssertEqual(categories.first?.name, "Продукты")

        let defaultsJSON = """
        {"lastAccountId":"a1","lastCurrencyCode":"KZT","topCategoryIds":["c1","c2"]}
        """
        let defaults = try JSONDecoder().decode(PFDefaults.self, from: Data(defaultsJSON.utf8))
        XCTAssertEqual(defaults.lastAccountId, "a1")
        XCTAssertEqual(defaults.topCategoryIds, ["c1", "c2"])
    }

    // MARK: - Порядок плиток категорий: топ из defaults, дальше sortOrder

    func testCategoryOrderingPutsDefaultsTopFirst() {
        let categories = [
            PFCategory(id: "c1", slug: "avto", name: "Авто", parentId: nil, sortOrder: 10, isActive: true),
            PFCategory(id: "c2", slug: "kafe", name: "Кафе", parentId: nil, sortOrder: 260, isActive: true),
            PFCategory(id: "c3", slug: "produkty", name: "Продукты", parentId: nil, sortOrder: 250, isActive: true),
        ]
        let ordered = PersonalFinanceViewModel.ordered(categories, topIds: ["c2", "missing"])
        XCTAssertEqual(ordered.map(\.id), ["c2", "c1", "c3"])
    }

    // MARK: - URL установки шорткатов (shortcuts://import-shortcut)

    func testShortcutInstallURLEncodesDownloadURLAndName() throws {
        PersonalFinanceSettings.baseURL = "http://185.146.3.87:18082"
        defer { PersonalFinanceSettings.baseURL = "" }
        guard PersonalFinanceSettings.storeToken("tok-123") else {
            throw XCTSkip("Keychain недоступен в тестовом окружении")
        }
        defer { _ = PersonalFinanceSettings.storeToken("") }

        let url = try XCTUnwrap(PersonalFinanceSettings.shortcutInstallURL(kind: .auto))
        XCTAssertEqual(url.scheme, "shortcuts")
        XCTAssertEqual(url.host, "import-shortcut")
        let query = try XCTUnwrap(url.query)
        // Вложенный URL полностью экранирован: ? и & не ломают внешний query.
        XCTAssertTrue(query.contains("url=http%3A%2F%2F185.146.3.87%3A18082%2Fapi%2Fshortcuts%2Fauto%3Fkey%3Dtok-123"))
        XCTAssertFalse(PersonalFinanceSettings.ShortcutKind.auto.title.isEmpty)
    }

    // MARK: - Подтверждение после записи

    func testConfirmationTrimsDecimalNoiseAndNamesCategory() {
        XCTAssertEqual(
            PersonalFinanceViewModel.confirmation(
                amount: "12500.500000000000",
                currencyCode: "KZT",
                categoryName: "Продукты",
                entryType: .expense
            ),
            "Трата записана: 12500.5 KZT, Продукты"
        )
        XCTAssertEqual(
            PersonalFinanceViewModel.confirmation(
                amount: "9600",
                currencyCode: "KZT",
                categoryName: nil,
                entryType: .income
            ),
            "Доход записан: 9600 KZT"
        )
    }
}
