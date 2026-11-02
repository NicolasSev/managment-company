import Combine
import Foundation

/// One month cell of the grid, with the texts ready for the view: the status label comes from the
/// meta, never from a map of the app.
struct UtilityMonthCell: Equatable, Identifiable {
    let period: String
    let monthName: String
    /// `nil`: no bill and no expectation (the cell offers to add one).
    let status: UtilityBillStatus?
    let statusText: String
    let tone: StatusTone
    let amountText: String?
    /// «без квитанции» under «Оплачено».
    let note: String?
    let billId: String?
    let isPaidWithoutReceipt: Bool

    var id: String { period }

    /// Spoken form of the cell.
    var accessibilityText: String {
        [monthName, statusText, note, amountText].compactMap { $0 }.joined(separator: ", ")
    }

    static func make(_ month: UtilityGridMonth, labels: UtilityLabelBook) -> UtilityMonthCell {
        let name = UtilityFormat.monthName(month.period)
        guard let status = month.status else {
            return UtilityMonthCell(
                period: month.period, monthName: name, status: nil, statusText: "Нет счёта", tone: .neutral,
                amountText: nil, note: nil, billId: nil, isPaidWithoutReceipt: false
            )
        }
        var note: String?
        if month.isPaidWithoutReceipt {
            note = "без квитанции"
        } else if status == .needsReview, let confidence = month.confidence {
            note = "уверенность \(UtilityFormat.percent(confidence))"
        }
        return UtilityMonthCell(
            period: month.period,
            monthName: name,
            status: status,
            statusText: labels.statusLabel(status),
            tone: status.tone,
            amountText: month.total.map { UtilityFormat.money($0, currency: month.currency) },
            note: note,
            billId: month.billId,
            isPaidWithoutReceipt: month.isPaidWithoutReceipt
        )
    }
}

enum UtilitiesGridState: Equatable {
    case loading
    case loaded
    case error(String)
}

/// The 12-month grid of one property (`GET /v1/utility-bills/grid?year=&property_id=`).
@MainActor
final class UtilitiesGridViewModel: ObservableObject {
    @Published private(set) var state: UtilitiesGridState = .loading
    @Published private(set) var grid: UtilityGrid?
    @Published private(set) var meta: UtilityMeta?
    @Published private(set) var year: Int

    let propertyId: String
    private let service: UtilityBillsService
    private let currentYear: Int

    init(propertyId: String, service: UtilityBillsService, now: () -> Date = { Date() }) {
        self.propertyId = propertyId
        self.service = service
        let year = Calendar(identifier: .gregorian).component(.year, from: now())
        self.year = year
        self.currentYear = year
    }

    var labels: UtilityLabelBook { UtilityLabelBook(meta) }

    var property: UtilityGridProperty? {
        grid?.properties.first(where: { $0.propertyId == propertyId })
    }

    var cells: [UtilityMonthCell] {
        (property?.months ?? []).map { UtilityMonthCell.make($0, labels: labels) }
    }

    /// The year total in the base currency, `nil` before the first load.
    var yearTotalText: String? {
        guard let property, let grid else { return nil }
        return UtilityFormat.money(property.yearTotalBase, currency: grid.baseCurrency)
    }

    var accountText: String? {
        guard let account = property?.account else { return nil }
        return [account.providerName, "л/с \(account.accountNumber)"].compactMap { $0 }.joined(separator: " · ")
    }

    var payer: UtilityPayer? { property?.utilityPayer }

    /// No bills at all in this year: the grid is an invitation to upload the first one.
    var isEmptyYear: Bool {
        property?.months.allSatisfy { $0.status == nil } ?? false
    }

    var canGoForward: Bool { year < currentYear }

    func load() async {
        if grid == nil { state = .loading }
        do {
            async let metaTask = loadMeta()
            let loaded = try await service.grid(year: year, propertyId: propertyId)
            meta = await metaTask
            grid = loaded
            state = .loaded
        } catch let error as UtilityBillsError {
            if grid == nil { state = .error(error.userMessage) }
        } catch {
            if grid == nil { state = .error(UtilityBillsError.unknown.userMessage) }
        }
    }

    func previousYear() async {
        year -= 1
        grid = nil
        await load()
    }

    func nextYear() async {
        guard canGoForward else { return }
        year += 1
        grid = nil
        await load()
    }

    private func loadMeta() async -> UtilityMeta? {
        if let meta { return meta }
        return try? await service.meta()
    }
}
