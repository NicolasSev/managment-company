import SwiftUI

/// Per-allocation payment history for one schedule row (GAP-048).
///
/// Shows the individual payments applied to a schedule (oldest first). Each row
/// can be reversed independently (`DELETE /v1/payments/:id`), which soft-deletes
/// the linked income transaction and recalculates the schedule status without
/// unwinding the whole installment. For fully-paid rows a visually distinct
/// full-restore action is available via the `onFullRestore` callback (same
/// `PATCH action:"restore"` path used by the existing un-pay flow; kept as a
/// callback so the parent list refreshes after dismissal).
struct AllocationHistorySheet: View {
    let item: PaymentQueueItem
    /// Called after any per-allocation reverse so the parent queue can reload.
    var onAllocationReversed: (() -> Void)?
    /// Called to trigger the full-schedule restore action (PATCH action:"restore").
    /// The section is only rendered for paid schedules — caller should pass nil
    /// for partial/pending/skipped rows, or always pass and let the sheet guard.
    var onFullRestore: (() async -> Bool)?

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var allocations: [PaymentScheduleAllocation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isMutating = false
    @State private var reverseCandidate: PaymentScheduleAllocation?

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()
                scrollContent
            }
            .navigationTitle("Платежи по начислению")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .task { await load() }
        .confirmationDialog(
            "Отменить этот платёж?",
            isPresented: Binding(
                get: { reverseCandidate != nil },
                set: { if !$0 { reverseCandidate = nil } }
            ),
            titleVisibility: .visible,
            presenting: reverseCandidate
        ) { allocation in
            Button("Отменить платёж", role: .destructive) {
                Task { await reverseAllocation(allocation) }
            }
            Button("Оставить", role: .cancel) {}
        } message: { allocation in
            Text(
                "\(AppFormatting.currency(allocation.amount, currency: allocation.currency))" +
                " · \(AppFormatting.dateString(from: allocation.paymentDate) ?? allocation.paymentDate)." +
                " Связанная транзакция дохода будет удалена, статус начисления пересчитан."
            )
        }
    }

    @ViewBuilder
    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                scheduleSummaryCard

                if let err = errorMessage {
                    statusBanner(err)
                }

                allocationsList

                infoBox

                if item.status == "paid" && onFullRestore != nil {
                    fullRestoreSection
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.lg)
        }
    }

    // MARK: - Schedule summary

    private var scheduleSummaryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(item.propertyName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(item.tenantName.isEmpty ? "—" : item.tenantName)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                HStack(spacing: 4) {
                    Text("Период: \(PaymentsQueueViewModel.periodLabel(of: item))")
                    Text("·")
                    Text(AppFormatting.currency(item.paidToDate ?? item.actualAmount ?? 0, currency: item.currency))
                        .fontWeight(.semibold)
                    Text("из \(AppFormatting.currency(item.expectedAmount, currency: item.currency))")
                }
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(2)

                if let remaining = item.remainingAmount, remaining > 0 {
                    Text("Остаток: \(AppFormatting.currency(remaining, currency: item.currency))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.danger)
                }
            }
        }
    }

    // MARK: - Allocations list

    @ViewBuilder
    private var allocationsList: some View {
        if isLoading {
            SurfaceCard {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        } else if allocations.isEmpty {
            SurfaceCard {
                Text("Платежей по этому начислению нет.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            }
        } else {
            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(allocations.enumerated()), id: \.element.id) { idx, allocation in
                        allocationRow(allocation, isLast: idx == allocations.count - 1)
                    }
                }
            }
        }
    }

    private func allocationRow(_ allocation: PaymentScheduleAllocation, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppFormatting.currency(allocation.amount, currency: allocation.currency))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    HStack(spacing: 6) {
                        Text(AppFormatting.dateString(from: allocation.paymentDate) ?? allocation.paymentDate)
                        if allocation.transactionId != nil {
                            Label("транзакция", systemImage: "doc.text")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                    if let notes = allocation.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Button {
                    reverseCandidate = allocation
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundStyle(AppTheme.Colors.danger)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .disabled(isMutating)
                .accessibilityLabel("Отменить этот платёж")
            }
            .padding(AppTheme.Spacing.md)

            if !isLast {
                Divider()
                    .padding(.horizontal, AppTheme.Spacing.md)
            }
        }
    }

    // MARK: - Info + full restore

    private var infoBox: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text("Отмена одного платежа удаляет связанную транзакцию дохода и пересчитывает статус начисления. Остальные платежи сохраняются.")
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var fullRestoreSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Нужно вернуть всё начисление в очередь целиком?")
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Button {
                guard let onFullRestore else { return }
                Task {
                    isMutating = true
                    defer { isMutating = false }
                    if await onFullRestore() {
                        AppHaptics.success()
                        dismiss()
                    } else {
                        errorMessage = "Не удалось отменить оплату."
                    }
                }
            } label: {
                Label("Отменить оплату полностью", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.danger)
            }
            .buttonStyle(.plain)
            .disabled(isMutating)
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.danger.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.Colors.danger.opacity(0.25))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Network

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let envelope: APIListEnvelope<PaymentScheduleAllocation> = try await APIClient.shared.requestRoot(
                "/v1/payment-schedules/\(item.id)/allocations",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            allocations = envelope.data
        } catch {
            errorMessage = "Не удалось загрузить историю платежей."
        }
    }

    private func reverseAllocation(_ allocation: PaymentScheduleAllocation) async {
        isMutating = true
        defer { isMutating = false }
        do {
            _ = try await APIClient.shared.requestData(
                "/v1/payments/\(allocation.id)",
                method: "DELETE",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            AppHaptics.success()
            onAllocationReversed?()
            await load()
        } catch {
            errorMessage = "Не удалось отменить платёж."
            AppHaptics.warning()
        }
    }

    // MARK: - Status banner

    private func statusBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(AppTheme.Colors.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppTheme.Colors.danger.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
