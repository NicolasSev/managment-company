import SwiftUI

struct TerminateLeaseSheet: View {
    private static let earlyMoveOutReason = "Выехал раньше срока"

    let lease: Lease
    let tenant: Tenant?
    let onSave: () async -> Void

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var terminationDate: Date
    @State private var earlyMoveOut: Bool
    @State private var reason: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(lease: Lease, tenant: Tenant?, onSave: @escaping () async -> Void) {
        self.lease = lease
        self.tenant = tenant
        self.onSave = onSave

        let initialDate = Self.date(from: lease.terminatedAt) ?? Date()
        let initialEarly = Self.isEarlyMoveOut(lease: lease, terminationDate: initialDate)
        _terminationDate = State(initialValue: initialDate)
        _earlyMoveOut = State(initialValue: initialEarly)
        _reason = State(initialValue: lease.terminationReason ?? (initialEarly ? Self.earlyMoveOutReason : ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(tenant?.displayName.isEmpty == false ? tenant!.displayName : "Арендатор")
                        .font(.headline)
                    Text("Договор \(AppFormatting.dateString(from: lease.startDate) ?? lease.startDate) - \(lease.endDate.flatMap { AppFormatting.dateString(from: $0) } ?? "без даты окончания")")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Section("Прекращение") {
                    DatePicker("Дата прекращения", selection: $terminationDate, displayedComponents: .date)
                        .onChange(of: terminationDate) { _, value in
                            let nextEarly = Self.isEarlyMoveOut(lease: lease, terminationDate: value)
                            earlyMoveOut = nextEarly
                            if nextEarly && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                reason = Self.earlyMoveOutReason
                            } else if !nextEarly && reason.trimmingCharacters(in: .whitespacesAndNewlines) == Self.earlyMoveOutReason {
                                reason = ""
                            }
                        }

                    Toggle("Арендатор выехал раньше срока", isOn: $earlyMoveOut)
                        .onChange(of: earlyMoveOut) { _, value in
                            if value && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                reason = Self.earlyMoveOutReason
                            } else if !value && reason.trimmingCharacters(in: .whitespacesAndNewlines) == Self.earlyMoveOutReason {
                                reason = ""
                            }
                        }
                }

                Section("Причина") {
                    AppTextField(title: "Причина", text: $reason, placeholder: "Необязательно")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
            }
            .navigationTitle("Прекратить аренду")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Прекратить", role: .destructive) {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = TerminateLeaseBody(
            terminatedAt: Self.apiDayFormatter.string(from: terminationDate),
            terminationReason: trimmedReason.isEmpty ? (earlyMoveOut ? Self.earlyMoveOutReason : nil) : trimmedReason
        )

        do {
            _ = try await APIClient.shared.request(
                "/v1/leases/\(lease.id)/terminate",
                method: "POST",
                body: payload,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            ) as Lease
            await onSave()
            await MainActor.run { dismiss() }
        } catch APIError.httpStatus(let code) {
            await MainActor.run {
                errorMessage = code == 400
                    ? "Проверьте дату прекращения."
                    : "Не удалось прекратить аренду."
            }
        } catch {
            await MainActor.run {
                errorMessage = "Не удалось прекратить аренду."
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

    private static func isEarlyMoveOut(lease: Lease, terminationDate: Date) -> Bool {
        if lease.terminationReason?.trimmingCharacters(in: .whitespacesAndNewlines) == earlyMoveOutReason {
            return true
        }
        guard let end = date(from: lease.endDate) else { return false }
        return terminationDate < end
    }
}

private struct TerminateLeaseBody: Encodable {
    let terminatedAt: String
    let terminationReason: String?

    enum CodingKeys: String, CodingKey {
        case terminatedAt = "terminated_at"
        case terminationReason = "termination_reason"
    }
}
