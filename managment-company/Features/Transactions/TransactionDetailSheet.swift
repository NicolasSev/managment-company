import SwiftUI

struct TransactionDetailSheet: View {
    let transactionId: String
    var propertyName: String?
    var baseCurrency: String

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var transaction: Transaction?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()

                content
            }
            .navigationTitle("Операция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task(id: transactionId) {
                await loadTransaction()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            EmptyStateView(
                title: "Операция недоступна",
                message: errorMessage,
                actionName: "Повторить",
                action: { Task { await loadTransaction() } },
                icon: "wifi.exclamationmark"
            )
            .padding(AppTheme.Spacing.md)
        } else if let transaction {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(AppFormatting.dateString(from: transaction.transactionDate) ?? transaction.transactionDate)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)

                                    Text("\(transaction.type == "income" ? "+" : "-")\(AppFormatting.currency(transaction.amount, currency: transaction.currency))")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(transaction.type == "income" ? AppTheme.Colors.success : AppTheme.Colors.danger)
                                }

                                Spacer()

                                StatusBadge(status: transaction.type)
                            }

                            detailRow("Базовая валюта", value: AppFormatting.currency(transaction.amountBase, currency: baseCurrency))

                            if let propertyName {
                                detailRow("Объект", value: propertyName)
                            }

                            detailRow("Период", value: "\(transaction.periodMonth)/\(transaction.periodYear)")

                            if let description = transaction.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                detailRow("Описание", value: description)
                            } else {
                                detailRow("Описание", value: "Описание не добавлено.")
                            }
                        }
                    }

                    EntityFilesSection(
                        entityType: "transaction",
                        entityId: transaction.id,
                        title: "Файлы операции"
                    )
                    .environmentObject(authManager)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
    }

    private func loadTransaction() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            transaction = try await APIClient.shared.request(
                "/v1/transactions/\(transactionId)",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
        } catch {
            transaction = nil
            errorMessage = "Не удалось загрузить связанную операцию."
        }
    }
}
