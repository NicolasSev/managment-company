import SwiftUI

private struct ListedTransaction: Identifiable {
    var id: String { transaction.id }
    let transaction: Transaction
    let propertyName: String
}

struct TransactionsListView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var rows: [ListedTransaction] = []
    @State private var propertiesById: [String: Property] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showReceiptSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()

                content
            }
            .navigationTitle("Операции")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showReceiptSheet = true
                    } label: {
                        Label("Квитанция", systemImage: "doc.text.fill")
                    }
                }
            }
            .refreshable {
                await loadPortfolioTransactions()
            }
            .sheet(isPresented: $showReceiptSheet) {
                UtilityReceiptUploadSheet {
                    Task { await loadPortfolioTransactions() }
                }
                .environmentObject(authManager)
            }
            .task {
                await loadPortfolioTransactions()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && rows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, rows.isEmpty {
            EmptyStateView(
                title: "Операции недоступны",
                message: errorMessage,
                actionName: "Повторить",
                action: { Task { await loadPortfolioTransactions() } },
                icon: "wifi.exclamationmark"
            )
        } else if rows.isEmpty {
            EmptyStateView(
                title: "Операций пока нет",
                message: "Добавляйте движения из карточки объекта или загрузите квитанцию ЖКХ.",
                actionName: "Загрузить квитанцию",
                action: { showReceiptSheet = true },
                icon: "arrow.left.arrow.right"
            )
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.Spacing.md) {
                    if let errorMessage {
                        SurfaceCard(padding: AppTheme.Spacing.md) {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.warning)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    utilityReceiptBanner

                    LazyVStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(rows) { row in
                            if let destination = propertiesById[row.transaction.propertyId] {
                                NavigationLink(value: destination) {
                                    ListedTransactionCard(
                                        row: row,
                                        baseCurrency: authManager.user?.baseCurrency ?? "KZT"
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                ListedTransactionCard(
                                    row: row,
                                    baseCurrency: authManager.user?.baseCurrency ?? "KZT"
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
            .navigationDestination(for: Property.self) { prop in
                PropertyDetailView(property: prop)
                    .environmentObject(authManager)
            }
        }
    }

    private var utilityReceiptBanner: some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Квитанция по коммуналке")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("Загрузите PDF или фото — суммы попадут в коммунальные платежи выбранного объекта после подтверждения.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                PrimaryButton(
                    title: "Загрузить квитанцию о ком. услугах",
                    action: { showReceiptSheet = true },
                    systemImage: "arrow.up.doc"
                )
            }
        }
    }

    @MainActor
    private func loadPortfolioTransactions() async {
        errorMessage = nil
        if rows.isEmpty { isLoading = true }
        defer { isLoading = false }

        do {
            let properties: [Property] = try await APIClient.shared.request(
                "/v1/properties",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            propertiesById = Dictionary(uniqueKeysWithValues: properties.map { ($0.id, $0) })

            var merged: [ListedTransaction] = []
            for property in properties {
                let data = try await APIClient.shared.requestData(
                    "/v1/properties/\(property.id)/transactions?per_page=100",
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                )
                let decoded = try JSONDecoder().decode(APIResponse<[Transaction]>.self, from: data)
                merged.append(contentsOf: decoded.data.map {
                    ListedTransaction(transaction: $0, propertyName: property.name)
                })
            }

            merged.sort {
                ($0.transaction.transactionDate, $0.id) > ($1.transaction.transactionDate, $1.id)
            }
            rows = merged
        } catch {
            rows = []
            errorMessage = "Не удалось загрузить журнал операций."
        }
    }
}

private struct ListedTransactionCard: View {
    let row: ListedTransaction
    let baseCurrency: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.propertyName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(AppFormatting.dateString(from: row.transaction.transactionDate) ?? row.transaction.transactionDate)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textTertiary)

                HStack(spacing: 8) {
                    StatusBadge(status: row.transaction.type)

                    if let description = row.transaction.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(2)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(AppFormatting.compactAmount(row.transaction.amount, currency: row.transaction.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(row.transaction.type == "income" ? AppTheme.Colors.success : AppTheme.Colors.danger)

                Text("База \(AppFormatting.currency(row.transaction.amountBase, currency: baseCurrency))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textTertiary)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
