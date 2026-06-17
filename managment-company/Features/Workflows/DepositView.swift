import SwiftUI

/// Security-deposit lifecycle for a lease (GAP-041): canonical balance plus
/// received/deduction/refunded events with reversal.
struct DepositView: View {
    @StateObject private var viewModel: DepositViewModel
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var showAddEvent = false
    @State private var reverseCandidate: LeaseDepositEvent?

    private let timeZoneIdentifier: String

    init(authManager: AuthManager, leaseId: String) {
        _viewModel = StateObject(wrappedValue: DepositViewModel(
            client: LiveDepositClient(authManager: authManager),
            leaseId: leaseId,
            baseCurrency: authManager.user?.baseCurrency ?? "KZT"
        ))
        self.timeZoneIdentifier = authManager.user?.timezone ?? "Asia/Almaty"
    }

    var body: some View {
        NavigationStack {
            List {
                if let summary = viewModel.summary {
                    Section("Баланс") {
                        row("Ожидается", summary.expected, summary.currency)
                        row("Получено", summary.received, summary.currency)
                        row("Удержания", summary.deductions, summary.currency)
                        row("Возвращено", summary.refunded, summary.currency)
                        row("На руках (held)", summary.held, summary.currency, bold: true)
                        row("Остаток (liability)", summary.outstanding, summary.currency, bold: true)
                        HStack {
                            Text("Статус").foregroundStyle(AppTheme.Colors.textSecondary)
                            Spacer()
                            Text(statusLabel(summary.status)).font(.subheadline.weight(.semibold))
                        }
                    }
                    Section("История") {
                        if viewModel.activeEvents.isEmpty {
                            Text("Событий пока нет").foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        ForEach(viewModel.activeEvents) { event in
                            eventRow(event)
                        }
                    }
                }
                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(AppTheme.Colors.danger) }
                }
            }
            .navigationTitle("Депозит")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddEvent = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $showAddEvent) {
                DepositEventSheet(
                    currency: viewModel.summary?.currency ?? viewModel.baseCurrency,
                    held: viewModel.summary?.held ?? 0
                ) { type, amount, reason in
                    await viewModel.addEvent(type: type, amount: amount, reason: reason, now: Date(), timeZoneIdentifier: timeZoneIdentifier)
                }
            }
            .confirmationDialog(
                "Отменить событие?",
                isPresented: Binding(get: { reverseCandidate != nil }, set: { if !$0 { reverseCandidate = nil } }),
                titleVisibility: .visible,
                presenting: reverseCandidate
            ) { event in
                Button("Отменить событие", role: .destructive) {
                    Task { _ = await viewModel.reverse(event); reverseCandidate = nil }
                }
                Button("Оставить", role: .cancel) {}
            }
        }
    }

    private func row(_ label: String, _ amount: Double, _ currency: String, bold: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer()
            Text(AppFormatting.currency(amount, currency: currency))
                .font(bold ? .subheadline.weight(.bold) : .subheadline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
    }

    private func eventRow(_ event: LeaseDepositEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(DepositViewModel.eventTypeLabel(event.eventType))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(AppFormatting.currency(event.amount, currency: event.currency))
                    .font(.subheadline.weight(.semibold))
            }
            Text(AppFormatting.dateString(from: event.eventDate) ?? event.eventDate)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            if let reason = event.reason, !reason.isEmpty {
                Text(reason).font(.caption).foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { reverseCandidate = event } label: {
                Label("Отменить", systemImage: "arrow.uturn.backward")
            }
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "held": return "Удерживается"
        case "refunded": return "Возвращён"
        case "partially_refunded": return "Частично возвращён"
        case "expected": return "Ожидается"
        default: return status
        }
    }
}

/// Add a deposit event (received / deduction / refunded).
private struct DepositEventSheet: View {
    let currency: String
    let held: Double
    let onSave: (String, Double, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var type = "received"
    @State private var amountText = ""
    @State private var reason = ""
    @State private var errorMessage: String?

    private let types = ["received", "deduction", "refunded"]

    private var amount: Double? { Double(amountText.replacingOccurrences(of: ",", with: ".")) }

    private var canSave: Bool {
        guard let amount, amount > 0 else { return false }
        return DepositViewModel.canApply(eventType: type, amount: amount, held: held)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Тип", selection: $type) {
                    ForEach(types, id: \.self) { Text(DepositViewModel.eventTypeLabel($0)).tag($0) }
                }
                HStack {
                    TextField("0", text: $amountText).keyboardType(.decimalPad)
                    Text(currency).foregroundStyle(AppTheme.Colors.textSecondary)
                }
                if type == "deduction" || type == "refunded" {
                    Text("Доступно к удержанию/возврату: \(AppFormatting.currency(held, currency: currency))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                AppTextField(title: "Причина", text: $reason, placeholder: "Необязательно")
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppTheme.Colors.danger)
                }
            }
            .navigationTitle("Событие депозита")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        Task {
                            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                            if await onSave(type, amount ?? 0, trimmed.isEmpty ? nil : trimmed) {
                                dismiss()
                            } else {
                                errorMessage = "Не удалось сохранить событие."
                            }
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
