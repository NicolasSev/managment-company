import Foundation

/// The edit state of a bill: text fields as the owner types them, turned into a `PATCH` against the
/// bill they started from. Only what changed is sent; `items` is a replace-set, so when any line
/// changed every line is sent, untouched ones exactly as recognised.
struct UtilityBillDraft: Equatable {
    struct Line: Equatable, Identifiable {
        let id: UUID
        var serviceType: String
        var labelRaw: String
        var amountText: String
        /// The recognised line this one started from; untouched lines go back unchanged.
        var original: UtilityBillItem?

        init(id: UUID = UUID(), serviceType: String, labelRaw: String = "", amountText: String = "", original: UtilityBillItem? = nil) {
            self.id = id
            self.serviceType = serviceType
            self.labelRaw = labelRaw
            self.amountText = amountText
            self.original = original
        }

        init(_ item: UtilityBillItem) {
            self.init(
                serviceType: item.serviceType,
                labelRaw: item.labelRaw ?? "",
                amountText: UtilityFormat.editableText(item.amount),
                original: item
            )
        }

        /// The line as the bill has it, to tell an edit from a no-op.
        fileprivate var isUnchanged: Bool {
            guard let original else { return false }
            return serviceType == original.serviceType
                && labelRaw == (original.labelRaw ?? "")
                && UtilityFormat.parseDecimal(amountText) == original.amount
        }
    }

    var providerName: String
    var accountNumber: String
    /// `YYYY-MM-DD` or empty.
    var issuedAt: String
    /// `YYYY-MM`.
    var period: String
    var currency: String
    var notes: String
    var lines: [Line]

    private let source: UtilityBill

    init(bill: UtilityBill) {
        source = bill
        providerName = bill.providerName ?? ""
        accountNumber = bill.accountNumber ?? ""
        issuedAt = bill.issuedAt ?? ""
        period = bill.period
        currency = bill.currency ?? ""
        notes = bill.notes ?? ""
        lines = bill.items.sorted { $0.position < $1.position }.map(Line.init)
    }

    /// What is wrong with the draft, by field; empty means it can be saved.
    var errors: [String: String] {
        var out: [String: String] = [:]
        for (index, line) in lines.enumerated() {
            if line.serviceType.isEmpty { out["lines.\(index).service"] = "Выберите услугу" }
            if Money.parse(line.amountText, currency: currency.isEmpty ? "KZT" : currency) == nil {
                out["lines.\(index).amount"] = "Введите сумму, например 1092,68"
            }
        }
        if UtilityFormat.components(ofPeriod: period) == nil { out["period"] = "Выберите месяц" }
        return out
    }

    var isValid: Bool { errors.isEmpty }

    /// `nil` when nothing changed.
    func patch() -> UtilityBillPatch? {
        var patch = UtilityBillPatch()
        patch.providerName = field(providerName, was: source.providerName)
        patch.accountNumber = field(accountNumber, was: source.accountNumber)
        patch.issuedAt = field(issuedAt, was: source.issuedAt)
        patch.notes = field(notes, was: source.notes)
        if period != source.period { patch.period = .set(period) }
        if !currency.isEmpty, currency != (source.currency ?? "") { patch.currency = .set(currency) }

        let original = source.items.sorted { $0.position < $1.position }
        let changed = lines.count != original.count || zip(lines, original).contains { line, item in
            line.original?.id != item.id || !line.isUnchanged
        }
        if changed {
            patch.items = lines.compactMap { line in
                if line.isUnchanged, let original = line.original { return UtilityBillItemInput(original) }
                guard let money = Money.parse(line.amountText, currency: currency.isEmpty ? "KZT" : currency) else { return nil }
                var input = line.original.map(UtilityBillItemInput.init) ?? UtilityBillItemInput(serviceType: line.serviceType, amount: money.major)
                input.serviceType = line.serviceType
                input.amount = money.major
                let label = line.labelRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                input.labelRaw = label.isEmpty ? nil : label
                return input
            }
        }
        return patch.isEmpty ? nil : patch
    }

    var isDirty: Bool { patch() != nil }

    mutating func addLine(serviceType: String) {
        lines.append(Line(serviceType: serviceType))
    }

    mutating func removeLine(at index: Int) {
        guard lines.indices.contains(index) else { return }
        lines.remove(at: index)
    }

    /// A text field against the stored value: empty text clears a value that existed.
    private func field(_ text: String, was stored: String?) -> UtilityPatchField<String> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = stored ?? ""
        if trimmed == before { return .unchanged }
        return trimmed.isEmpty ? .clear : .set(trimmed)
    }
}
