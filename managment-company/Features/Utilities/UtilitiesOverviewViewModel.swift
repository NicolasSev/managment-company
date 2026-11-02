import Combine
import Foundation

/// One row of the portfolio matrix: a property and its twelve months.
struct UtilityMatrixRow: Equatable, Identifiable {
    let propertyId: String
    let propertyName: String
    let payer: UtilityPayer
    let accountText: String?
    let cells: [UtilityMonthCell]
    let yearTotalText: String

    var id: String { propertyId }

    /// Months that still wait for a receipt.
    var missingCount: Int { cells.filter { $0.status == .missing }.count }
}

/// One line of the inbox, ready to show.
struct UtilityInboxRow: Equatable, Identifiable {
    enum Kind: Equatable {
        case bill(billId: String, propertyId: String?)
        case upload(extractionId: String, actions: [UtilityUploadAction])
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let detail: String?
    let tone: StatusTone
    let statusText: String
}

/// The numbers of the year-over-year card.
struct UtilityYearOverYear: Equatable {
    struct Line: Equatable, Identifiable {
        let key: String
        let title: String
        let currentText: String
        let previousText: String
        let deltaText: String?
        /// Share of the biggest amount, 0...1: bar lengths.
        let currentShare: Double
        let previousShare: Double
        var id: String { key }
    }

    let year: Int
    let compareYear: Int
    let currentText: String
    let previousText: String
    let deltaText: String?
    /// The costs grew: the card marks it as a warning.
    let isIncrease: Bool?
    let lines: [Line]
    let missingMonthsText: String?
    let unconvertedText: String?
}

enum UtilitiesOverviewState: Equatable {
    case loading
    case loaded
    case error(String)
}

/// The portfolio screen of the «Ещё» menu: the matrix of the properties, the review inbox, the
/// year over year card.
@MainActor
final class UtilitiesOverviewViewModel: ObservableObject {
    @Published private(set) var state: UtilitiesOverviewState = .loading
    @Published private(set) var grid: UtilityGrid?
    @Published private(set) var inbox: [UtilityInboxEntry] = []
    @Published private(set) var comparison: UtilityComparison?
    @Published private(set) var meta: UtilityMeta?
    @Published private(set) var year: Int
    /// «Только без квитанции»: the matrix keeps the properties with a missing month.
    @Published var onlyMissing = false
    @Published private(set) var message: String?
    @Published private(set) var isRejecting = false

    private let service: UtilityBillsService
    private let currentYear: Int

    init(service: UtilityBillsService, now: () -> Date = { Date() }) {
        self.service = service
        let year = Calendar(identifier: .gregorian).component(.year, from: now())
        self.year = year
        self.currentYear = year
    }

    var labels: UtilityLabelBook { UtilityLabelBook(meta) }
    var canGoForward: Bool { year < currentYear }
    var counters: UtilityCounters? { grid?.counters }

    var matrixRows: [UtilityMatrixRow] {
        guard let grid else { return [] }
        let rows = grid.properties.map { property in
            UtilityMatrixRow(
                propertyId: property.propertyId,
                propertyName: property.propertyName,
                payer: property.utilityPayer,
                accountText: property.account.map { [$0.providerName, "л/с \($0.accountNumber)"].compactMap { $0 }.joined(separator: " · ") },
                cells: property.months.map { UtilityMonthCell.make($0, labels: labels) },
                yearTotalText: UtilityFormat.money(property.yearTotalBase, currency: grid.baseCurrency)
            )
        }
        return onlyMissing ? rows.filter { $0.missingCount > 0 } : rows
    }

    var inboxRows: [UtilityInboxRow] {
        inbox.compactMap { entry in
            switch entry.kind {
            case .bill:
                guard let bill = entry.bill else { return nil }
                return UtilityInboxRow(
                    id: entry.id,
                    kind: .bill(billId: bill.id, propertyId: bill.propertyId),
                    title: bill.propertyName ?? "Объект не определён",
                    subtitle: UtilityFormat.periodTitle(bill.period),
                    detail: bill.total.map { UtilityFormat.money($0, currency: bill.currency, alwaysFraction: true) },
                    tone: bill.status.tone,
                    statusText: labels.statusLabel(bill.status)
                )
            case .upload:
                guard let upload = entry.upload else { return nil }
                var facts: [String] = []
                if let amount = upload.totalPaid { facts.append(UtilityFormat.money(amount, currency: upload.currency, alwaysFraction: true)) }
                if let date = UtilityFormat.day(upload.paymentDate) { facts.append(date) }
                return UtilityInboxRow(
                    id: entry.id,
                    kind: .upload(extractionId: upload.extractionId, actions: upload.actions),
                    title: "Файл не похож на счёт",
                    subtitle: "Не коммунальная квитанция",
                    detail: facts.isEmpty ? nil : facts.joined(separator: " · "),
                    tone: .warning,
                    statusText: "Нужно решение"
                )
            case .unknown:
                return nil
            }
        }
    }

    var yearOverYear: UtilityYearOverYear? {
        guard let comparison else { return nil }
        let currency = comparison.baseCurrency
        let rows = comparison.typeRows.sorted { $0.current > $1.current }
        let biggest = rows.map { max(NSDecimalNumber(decimal: $0.current).doubleValue, NSDecimalNumber(decimal: $0.previous).doubleValue) }.max() ?? 0
        func share(_ value: Decimal) -> Double {
            biggest > 0 ? NSDecimalNumber(decimal: value).doubleValue / biggest : 0
        }
        let lines = rows.map { row in
            UtilityYearOverYear.Line(
                key: row.key,
                title: labels.serviceLabel(row.key),
                currentText: UtilityFormat.money(row.current, currency: currency),
                previousText: UtilityFormat.money(row.previous, currency: currency),
                deltaText: UtilityFormat.deltaPercent(row.deltaPct),
                currentShare: share(row.current),
                previousShare: share(row.previous)
            )
        }
        let missing = comparison.coverage.missingMonths
        return UtilityYearOverYear(
            year: comparison.year,
            compareYear: comparison.compareYear,
            currentText: UtilityFormat.money(comparison.totals.current, currency: currency),
            previousText: UtilityFormat.money(comparison.totals.previous, currency: currency),
            deltaText: UtilityFormat.deltaPercent(comparison.totals.deltaPct),
            isIncrease: comparison.totals.deltaPct.map { $0 > 0 },
            lines: lines,
            missingMonthsText: missing.isEmpty ? nil : "Нет данных за месяцы: " + missing.map { UtilityFormat.monthShort($0).lowercased() + " " + $0.prefix(4) }.joined(separator: ", "),
            unconvertedText: comparison.unconvertedLines > 0 ? "Строк без курса валют: \(comparison.unconvertedLines), они не вошли в итог." : nil
        )
    }

    func load() async {
        if grid == nil { state = .loading }
        do {
            async let metaTask = loadMeta()
            async let inboxTask = service.inbox(page: 1, perPage: 50)
            async let comparisonTask = loadComparison()
            let loadedGrid = try await service.grid(year: year, propertyId: nil)
            let page = try await inboxTask
            meta = await metaTask
            comparison = await comparisonTask
            grid = loadedGrid
            inbox = page.entries
            state = .loaded
        } catch let error as UtilityBillsError {
            if grid == nil { state = .error(error.userMessage) } else { message = error.userMessage }
        } catch {
            if grid == nil { state = .error(UtilityBillsError.unknown.userMessage) } else { message = UtilityBillsError.unknown.userMessage }
        }
    }

    func previousYear() async {
        year -= 1
        grid = nil
        comparison = nil
        await load()
    }

    func nextYear() async {
        guard canGoForward else { return }
        year += 1
        grid = nil
        comparison = nil
        await load()
    }

    /// «Отклонить» on an `other` document of the inbox.
    func reject(extractionId: String) async {
        guard !isRejecting else { return }
        isRejecting = true
        message = nil
        defer { isRejecting = false }
        do {
            _ = try await service.rejectUpload(id: extractionId)
            inbox.removeAll { $0.upload?.extractionId == extractionId }
            await load()
        } catch let error as UtilityBillsError {
            message = error.userMessage
        } catch {
            message = UtilityBillsError.unknown.userMessage
        }
    }

    private func loadMeta() async -> UtilityMeta? {
        if let meta { return meta }
        return try? await service.meta()
    }

    /// The comparison is a nice-to-have: without it the card is simply absent.
    private func loadComparison() async -> UtilityComparison? {
        try? await service.comparison(year: year, propertyId: nil)
    }
}
