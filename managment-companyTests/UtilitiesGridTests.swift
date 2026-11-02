//
//  UtilitiesGridTests.swift
//  managment-companyTests
//
//  The grid of a property and the portfolio screen (task U9): twelve cells with the status labels of
//  the meta, «оплачено без квитанции» as its own chip, the year switch, the matrix filter, the inbox
//  rows and the year over year card.
//

import Foundation
import Testing
@testable import managment_company

private let firstProperty = "7c1e4a52-3b1f-4d1c-9a55-0a1f6c1d2b01"
/// 2026-11-02, noon UTC.
private let november2026 = Date(timeIntervalSince1970: 1_793_620_800)

@MainActor
@Suite(.serialized)
struct UtilitiesGridTests {
    private func gridModel(mock: MockUtilityBillsService? = nil) throws -> (UtilitiesGridViewModel, MockUtilityBillsService) {
        let service = try mock ?? MockUtilityBillsService()
        return (UtilitiesGridViewModel(propertyId: firstProperty, service: service, now: { november2026 }), service)
    }

    @Test func gridShowsTwelveMonthsOfTheCurrentYear() async throws {
        let (model, _) = try gridModel()
        #expect(model.year == 2026)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.cells.count == 12)
        #expect(model.cells.map(\.period).first == "2026-01" && model.cells.map(\.period).last == "2026-12")
        #expect(model.accountText == "АлСеКо · л/с 1100000")
        #expect(model.payer == .tenant)
    }

    @Test func chipsUseTheLabelsOfTheMeta() async throws {
        let (model, _) = try gridModel()
        await model.load()
        let byPeriod = Dictionary(uniqueKeysWithValues: model.cells.map { ($0.period, $0) })
        #expect(byPeriod["2026-03"]?.statusText == "Нужна проверка")
        #expect(byPeriod["2026-03"]?.tone == .warning)
        #expect(byPeriod["2026-04"]?.statusText == "Нет квитанции")
        #expect(byPeriod["2026-04"]?.tone == .danger)
        #expect(byPeriod["2026-05"]?.statusText == "Ожидается")
        #expect(byPeriod["2026-01"]?.statusText == "Оплачено" && byPeriod["2026-01"]?.tone == .success)
        // No bill and no expectation: an invitation, not a status.
        #expect(byPeriod["2026-07"]?.status == nil && byPeriod["2026-07"]?.billId == nil)
    }

    @Test func paidWithoutAReceiptIsItsOwnChip() async throws {
        let (model, _) = try gridModel()
        await model.load()
        let february = try #require(model.cells.first { $0.period == "2026-02" })
        #expect(february.isPaidWithoutReceipt)
        #expect(february.note == "без квитанции")
        #expect(february.statusText == "Оплачено")
        #expect(february.accessibilityText.contains("без квитанции"))
        let january = try #require(model.cells.first { $0.period == "2026-01" })
        #expect(!january.isPaidWithoutReceipt && january.note == nil)
    }

    @Test func amountsAreFormattedWithKopecksOnlyWhenTheyExist() async throws {
        #expect(UtilityFormat.money(Decimal(41210), currency: "KZT") == "41\u{00A0}210\u{00A0}₸")
        #expect(UtilityFormat.money(Decimal(string: "38990.12"), currency: "KZT") == "38\u{00A0}990,12\u{00A0}₸")
        #expect(UtilityFormat.money(nil, currency: "KZT") == "—")
        #expect(UtilityFormat.money(Decimal(1000), currency: "KZT", alwaysFraction: true) == "1\u{00A0}000,00\u{00A0}₸")
        #expect(UtilityFormat.periodTitle("2026-03") == "Март 2026")
        #expect(UtilityFormat.day("2025-11-22") == "22.11.2025")
        #expect(UtilityFormat.percent(0.93) == "93\u{00A0}%")
    }

    @Test func aYearIsPrintedWithoutAGroupingSpace() {
        #expect(UtilityFormat.year(2024) == "2024")
        #expect(!UtilityFormat.year(2026).contains(" ") && !UtilityFormat.year(2026).contains("\u{00A0}"))
        #expect(UtilityFormat.periodTitle("2024-03") == "Март 2024")
        // The card of the portfolio screen builds its strings from the same helper.
        let sentence = "В \(UtilityFormat.year(2024)) году"
        #expect(sentence == "В 2024 году")
    }

    @Test func yearSwitchLoadsTheOtherYearAndStopsAtTheCurrentOne() async throws {
        let (model, _) = try gridModel()
        await model.load()
        #expect(!model.canGoForward)
        await model.nextYear()
        #expect(model.year == 2026)
        await model.previousYear()
        #expect(model.year == 2025 && model.canGoForward)
        #expect(model.isEmptyYear)
        #expect(model.cells.allSatisfy { $0.status == nil })
        await model.nextYear()
        #expect(model.year == 2026 && !model.isEmptyYear)
    }

    @Test func aFailedLoadShowsTheMessageAndRetryRecovers() async throws {
        let mock = try MockUtilityBillsService()
        mock.failure = .transport
        let (model, _) = try gridModel(mock: mock)
        await model.load()
        #expect(model.state == .error(UtilityBillsError.transport.userMessage))
        await model.load()
        #expect(model.state == .loaded)
    }

    @Test func theYearTotalIsTheServersAndNotASumOfTheClient() async throws {
        let (model, _) = try gridModel()
        await model.load()
        // Confirmed and paid bills of the sample: 12 057,50 + 38 990,12 (the bills of the mock carry their own totals).
        #expect(model.yearTotalText == "51\u{00A0}047,62\u{00A0}₸")
    }

    // MARK: Portfolio

    private func overview(mock: MockUtilityBillsService? = nil) throws -> (UtilitiesOverviewViewModel, MockUtilityBillsService) {
        let service = try mock ?? MockUtilityBillsService()
        return (UtilitiesOverviewViewModel(service: service, now: { november2026 }), service)
    }

    @Test func overviewBuildsTheMatrixInboxAndCounters() async throws {
        let (model, _) = try overview()
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.matrixRows.count == 2)
        #expect(model.matrixRows[0].missingCount == 1)
        #expect(model.counters?.missing == 1 && model.counters?.needsReview == 1 && model.counters?.otherUploads == 1)
        let rows = model.inboxRows
        #expect(rows.count == 2)
        if case .bill(let billId, _) = rows.first(where: { if case .bill = $0.kind { return true } else { return false } })?.kind {
            #expect(billId == "b0000000-0000-4000-8000-000000000013")
        } else { Issue.record("no bill row") }
        #expect(rows.contains { $0.statusText == "Нужно решение" })
    }

    @Test func theMissingFilterKeepsThePropertiesWithAGap() async throws {
        let (model, _) = try overview()
        await model.load()
        model.onlyMissing = true
        #expect(model.matrixRows.map(\.propertyName) == ["Примерная 1, кв. 1"])
        model.onlyMissing = false
        #expect(model.matrixRows.count == 2)
    }

    @Test func rejectingAnOtherDocumentClearsItFromTheInbox() async throws {
        let (model, _) = try overview()
        await model.load()
        let upload = try #require(model.inboxRows.first { if case .upload = $0.kind { return true } else { return false } })
        guard case .upload(let extractionId, let actions) = upload.kind else { return }
        #expect(actions == [.attachToRent, .reject])
        await model.reject(extractionId: extractionId)
        #expect(model.inboxRows.count == 1)
        #expect(model.counters?.otherUploads == 0)
    }

    @Test func yearOverYearCardComesFromTheComparison() async throws {
        let (model, _) = try overview()
        await model.load()
        let card = try #require(model.yearOverYear)
        #expect(card.year == 2025 && card.compareYear == 2024)
        #expect(card.currentText == "3\u{00A0}000\u{00A0}₸" && card.previousText == "1\u{00A0}650\u{00A0}₸")
        #expect(card.deltaText == "+81,8\u{00A0}%" && card.isIncrease == true)
        #expect(card.lines.first?.title == "Электроэнергия")
        #expect(card.lines.first?.currentShare == 1)
        #expect(card.lines.contains { $0.key == "waste" && $0.deltaText == nil })
        #expect(card.missingMonthsText?.contains("2024") == true)
    }

    @Test func overviewSurvivesAMissingComparison() async throws {
        let service = try MockUtilityBillsService()
        let model = UtilitiesOverviewViewModel(service: service, now: { november2026 })
        await model.load()
        #expect(model.state == .loaded)
        // A year the fixture does not describe still renders without the card breaking the screen.
        await model.previousYear()
        #expect(model.state == .loaded)
        #expect(model.matrixRows.allSatisfy { $0.cells.allSatisfy { $0.status == nil } })
    }
}
