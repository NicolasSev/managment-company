import SwiftUI

struct LeaseFormSheet: View {
    let propertyId: String
    let tenants: [Tenant]
    let lease: Lease?
    let onSave: () async -> Void

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var tenantId: String
    @State private var startDate: Date
    @State private var moveInDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var rentAmount: String
    @State private var rentCurrency: String
    @State private var paymentWindowStartDay: String
    @State private var paymentWindowEndDay: String
    @State private var paymentDueDay: String
    @State private var notes: String
    @State private var isHistorical: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(propertyId: String, tenants: [Tenant], lease: Lease? = nil, onSave: @escaping () async -> Void) {
        self.propertyId = propertyId
        self.tenants = tenants
        self.lease = lease
        self.onSave = onSave

        let start = Self.date(from: lease?.startDate) ?? Date()
        let moveIn = Self.date(from: lease?.moveInDate) ?? start
        let parsedEnd = Self.date(from: lease?.endDate)

        _tenantId = State(initialValue: lease?.tenantId ?? "")
        _startDate = State(initialValue: start)
        _moveInDate = State(initialValue: moveIn)
        _hasEndDate = State(initialValue: parsedEnd != nil)
        _endDate = State(initialValue: parsedEnd ?? start)
        _rentAmount = State(initialValue: lease.map { Self.amountLabel($0.rentAmount) } ?? "")
        _rentCurrency = State(initialValue: lease?.rentCurrency ?? "KZT")
        _paymentWindowStartDay = State(initialValue: String(lease?.paymentWindowStartDay ?? lease?.paymentDay ?? 1))
        _paymentWindowEndDay = State(initialValue: String(lease?.paymentWindowEndDay ?? lease?.paymentDueDay ?? lease?.paymentDay ?? 5))
        _paymentDueDay = State(initialValue: String(lease?.paymentDueDay ?? lease?.paymentDay ?? 5))
        _notes = State(initialValue: lease?.notes ?? "")
        _isHistorical = State(initialValue: false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Арендатор") {
                    Picker("Арендатор", selection: $tenantId) {
                        Text("Выберите арендатора").tag("")
                        if let lease, !tenants.contains(where: { $0.id == lease.tenantId }) {
                            Text("Текущий арендатор").tag(lease.tenantId)
                        }
                        ForEach(tenants) { tenant in
                            Text(tenant.displayName.isEmpty ? "Без имени" : tenant.displayName)
                                .tag(tenant.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .disabled(lease != nil)

                    if lease == nil && tenants.isEmpty {
                        Text("Сначала создайте арендатора в web или в следующем iOS-срезе tenant parity.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }

                if lease == nil {
                    Section {
                        Toggle("Прошлое заселение", isOn: $isHistorical)
                            .onChange(of: isHistorical) { _, value in
                                if value {
                                    hasEndDate = true
                                }
                            }
                        Text("Для прошлого заселения нужна дата окончания договора; график оплат не создаётся.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }

                Section("Период") {
                    DatePicker("Дата заезда", selection: $moveInDate, displayedComponents: .date)
                    DatePicker("Начало договора", selection: $startDate, displayedComponents: .date)

                    Toggle("Есть дата окончания", isOn: $hasEndDate)
                        .disabled(isHistorical)

                    if hasEndDate {
                        DatePicker("Окончание договора", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section("Оплата") {
                    AppTextField(
                        title: "Аренда в месяц",
                        text: $rentAmount,
                        placeholder: "0",
                        keyboardType: .decimalPad,
                        autocapitalization: .never
                    )
                    AppTextField(
                        title: "Валюта",
                        text: $rentCurrency,
                        placeholder: "KZT",
                        autocapitalization: .characters
                    )

                    HStack {
                        AppTextField(
                            title: "С дня",
                            text: $paymentWindowStartDay,
                            placeholder: "1",
                            keyboardType: .numberPad,
                            autocapitalization: .never
                        )
                        AppTextField(
                            title: "До дня",
                            text: $paymentWindowEndDay,
                            placeholder: "5",
                            keyboardType: .numberPad,
                            autocapitalization: .never
                        )
                    }

                    AppTextField(
                        title: "День напоминания",
                        text: $paymentDueDay,
                        placeholder: "5",
                        keyboardType: .numberPad,
                        autocapitalization: .never
                    )
                }

                Section("Заметки") {
                    AppTextField(title: "Заметки", text: $notes, placeholder: "Необязательно")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
            }
            .navigationTitle(lease == nil ? "Заселить арендатора" : "Редактировать аренду")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lease == nil ? (isHistorical ? "В историю" : "Заселить") : "Сохранить") {
                        Task { await save() }
                    }
                    .disabled(!canSubmit || isSaving)
                }
            }
        }
    }

    private var canSubmit: Bool {
        guard lease != nil || !tenantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let amount = parsedAmount, amount > 0 else { return false }
        guard validDay(paymentWindowStartDay) != nil,
              validDay(paymentWindowEndDay) != nil,
              validDay(paymentDueDay) != nil else { return false }
        guard !hasEndDate || endDate >= startDate else { return false }
        guard !isHistorical || hasEndDate else { return false }
        return !rentCurrency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var parsedAmount: Double? {
        Double(
            rentAmount
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ",", with: ".")
        )
    }

    private func validDay(_ raw: String) -> Int? {
        guard let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...31).contains(value) else { return nil }
        return value
    }

    private func save() async {
        guard canSubmit, let amount = parsedAmount else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let noteTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = LeaseUpsertBody(
            tenantId: lease == nil ? tenantId : nil,
            startDate: Self.apiDayFormatter.string(from: startDate),
            endDate: hasEndDate ? Self.apiDayFormatter.string(from: endDate) : nil,
            moveInDate: Self.apiDayFormatter.string(from: moveInDate),
            rentAmount: amount,
            rentCurrency: rentCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            paymentDay: validDay(paymentDueDay),
            paymentWindowStartDay: validDay(paymentWindowStartDay),
            paymentWindowEndDay: validDay(paymentWindowEndDay),
            paymentDueDay: validDay(paymentDueDay),
            notes: noteTrimmed.isEmpty ? nil : noteTrimmed,
            isHistorical: lease == nil ? isHistorical : nil
        )

        do {
            if let lease {
                _ = try await APIClient.shared.request(
                    "/v1/leases/\(lease.id)",
                    method: "PUT",
                    body: payload,
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                ) as Lease
            } else {
                _ = try await APIClient.shared.request(
                    "/v1/properties/\(propertyId)/leases",
                    method: "POST",
                    body: payload,
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                ) as Lease
            }

            await onSave()
            await MainActor.run { dismiss() }
        } catch APIError.httpStatus(let code) {
            await MainActor.run {
                switch code {
                case 409:
                    errorMessage = "Период аренды пересекается с другой записью по объекту."
                case 400:
                    errorMessage = "Проверьте даты, сумму, валюту и дни оплаты."
                default:
                    errorMessage = lease == nil ? "Не удалось заселить арендатора." : "Не удалось сохранить аренду."
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = lease == nil ? "Не удалось заселить арендатора." : "Не удалось сохранить аренду."
            }
        }
    }

    private static let apiDayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    private static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return apiDayFormatter.date(from: value)
    }

    private static func amountLabel(_ value: Double) -> String {
        let n = NSNumber(value: value)
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: n) ?? String(value)
    }
}

private struct LeaseUpsertBody: Encodable {
    let tenantId: String?
    let startDate: String
    let endDate: String?
    let moveInDate: String?
    let rentAmount: Double
    let rentCurrency: String
    let paymentDay: Int?
    let paymentWindowStartDay: Int?
    let paymentWindowEndDay: Int?
    let paymentDueDay: Int?
    let notes: String?
    let isHistorical: Bool?

    enum CodingKeys: String, CodingKey {
        case tenantId = "tenant_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case moveInDate = "move_in_date"
        case rentAmount = "rent_amount"
        case rentCurrency = "rent_currency"
        case paymentDay = "payment_day"
        case paymentWindowStartDay = "payment_window_start_day"
        case paymentWindowEndDay = "payment_window_end_day"
        case paymentDueDay = "payment_due_day"
        case notes
        case isHistorical = "is_historical"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(tenantId, forKey: .tenantId)
        try c.encode(startDate, forKey: .startDate)
        if let endDate {
            try c.encode(endDate, forKey: .endDate)
        } else {
            try c.encodeNil(forKey: .endDate)
        }
        try c.encodeIfPresent(moveInDate, forKey: .moveInDate)
        try c.encode(rentAmount, forKey: .rentAmount)
        try c.encode(rentCurrency, forKey: .rentCurrency)
        try c.encodeIfPresent(paymentDay, forKey: .paymentDay)
        try c.encodeIfPresent(paymentWindowStartDay, forKey: .paymentWindowStartDay)
        try c.encodeIfPresent(paymentWindowEndDay, forKey: .paymentWindowEndDay)
        try c.encodeIfPresent(paymentDueDay, forKey: .paymentDueDay)
        if let notes {
            try c.encode(notes, forKey: .notes)
        } else {
            try c.encodeNil(forKey: .notes)
        }
        try c.encodeIfPresent(isHistorical, forKey: .isHistorical)
    }
}
