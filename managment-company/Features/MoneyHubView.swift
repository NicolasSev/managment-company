import SwiftUI

/// «Деньги» hub (GAP-037): a single primary navigation position that presents
/// the two separate money routes — the rent collection queue (`Платежи`) and
/// the operations ledger (`Операции`) — under one entry without merging their
/// backend concepts. Each child is embedded (no own `NavigationStack`).
/// «Личные» (GAP-050) — тонкий клиент внешнего portfolio-dashboard API для личных
/// трат/доходов; он не смешивается с арендным доменом и не пишет в базу PropManager.
struct MoneyHubView: View {
    let authManager: AuthManager
    @EnvironmentObject private var notificationRouter: NotificationDeepLinkRouter

    enum MoneySegment: String, CaseIterable, Identifiable {
        case payments
        case operations
        case personal
        var id: String { rawValue }
        var title: String {
            switch self {
            case .payments: return "Платежи"
            case .operations: return "Операции"
            case .personal: return "Личные"
            }
        }
    }

    @State private var segment: MoneySegment = .payments

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Раздел денег", selection: $segment) {
                    ForEach(MoneySegment.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)

                switch segment {
                case .payments:
                    PaymentsQueueView(authManager: authManager, embedded: true)
                case .operations:
                    TransactionsListView(embedded: true)
                case .personal:
                    PersonalFinanceView(embedded: true)
                }
            }
        }
        .onChange(of: notificationRouter.pendingRoute) { _, route in
            // A transaction deep link should land on the operations ledger.
            if case .transaction = route?.kind { segment = .operations }
            if case .transactions = route?.kind { segment = .operations }
        }
    }
}
