import Combine
import SwiftUI

/// The global quick-action set (GAP-032), mirroring web's persistent `+` launcher.
/// Order is fixed: payment → expense → receipt → task → document → tenant.
enum QuickActionKind: String, CaseIterable, Identifiable {
    case payment
    case expense
    case receipt
    case task
    case document
    case tenant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .payment: return "Оплата получена"
        case .expense: return "Добавить расход"
        case .receipt: return "Загрузить квитанцию"
        case .task: return "Добавить задачу"
        case .document: return "Загрузить документ"
        case .tenant: return "Арендатор / заселение"
        }
    }

    var systemImage: String {
        switch self {
        case .payment: return "wallet.bullet"
        case .expense: return "banknote"
        case .receipt: return "doc.text.viewfinder"
        case .task: return "checklist"
        case .document: return "doc.badge.plus"
        case .tenant: return "person.crop.circle.badge.plus"
        }
    }
}

/// Shell-level controller for the persistent quick-action launcher. Screens may
/// set `contextPropertyId` / `contextTenantId` so launched flows preselect the
/// entity in view (GAP-032), and call `open(_:)` to trigger an action.
@MainActor
final class QuickActionsController: ObservableObject {
    @Published var isMenuPresented = false
    @Published var activeAction: QuickActionKind?
    @Published var contextPropertyId: String?
    @Published var contextTenantId: String?

    static let orderedActions: [QuickActionKind] = [
        .payment, .expense, .receipt, .task, .document, .tenant,
    ]

    /// Prerequisite explanation when an action cannot run yet, else `nil` when it
    /// is available. Expense/receipt must attach to a property, so they require at
    /// least one object; the others always work.
    nonisolated static func prerequisite(for kind: QuickActionKind, hasProperties: Bool) -> String? {
        switch kind {
        case .expense, .receipt:
            return hasProperties ? nil : "Сначала добавьте объект, чтобы привязать запись."
        default:
            return nil
        }
    }

    nonisolated static func isAvailable(_ kind: QuickActionKind, hasProperties: Bool) -> Bool {
        prerequisite(for: kind, hasProperties: hasProperties) == nil
    }

    func presentMenu() { isMenuPresented = true }

    func open(_ kind: QuickActionKind) {
        isMenuPresented = false
        activeAction = kind
    }

    func close() { activeAction = nil }

    func setContext(propertyId: String? = nil, tenantId: String? = nil) {
        if let propertyId { contextPropertyId = propertyId }
        if let tenantId { contextTenantId = tenantId }
    }

    func clearContext() {
        contextPropertyId = nil
        contextTenantId = nil
    }
}

/// Floating `+` launcher available from every authenticated screen. Hosts the
/// action menu and presents the matching existing flow, preserving the active
/// property/tenant context where the flow supports it.
struct QuickActionLauncher: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var controller: QuickActionsController
    @EnvironmentObject private var notificationRouter: NotificationDeepLinkRouter

    @State private var properties: [Property] = []

    var body: some View {
        Button {
            controller.presentMenu()
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(AppTheme.Colors.accent)
                .clipShape(Circle())
                .shadow(color: AppTheme.Colors.accent.opacity(0.4), radius: 12, y: 6)
        }
        .accessibilityLabel("Быстрое действие")
        .accessibilityHint("Открывает меню быстрых действий")
        .task { await loadProperties() }
        .sheet(isPresented: $controller.isMenuPresented) {
            menu
        }
        .sheet(item: $controller.activeAction) { action in
            actionSheet(for: action)
        }
    }

    private var hasProperties: Bool { !properties.isEmpty }

    private var menu: some View {
        NavigationStack {
            List {
                ForEach(QuickActionsController.orderedActions) { action in
                    let prerequisite = QuickActionsController.prerequisite(for: action, hasProperties: hasProperties)
                    Button {
                        controller.open(action)
                    } label: {
                        HStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: action.systemImage)
                                .frame(width: 28)
                                .foregroundStyle(AppTheme.Colors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                if let prerequisite {
                                    Text(prerequisite)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                    .disabled(prerequisite != nil)
                    .accessibilityLabel(action.title)
                }
            }
            .navigationTitle("Быстрые действия")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { controller.isMenuPresented = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func actionSheet(for action: QuickActionKind) -> some View {
        switch action {
        case .payment:
            Color.clear.onAppear {
                controller.close()
                notificationRouter.selectTab = .payments
            }
        case .expense:
            CompactExpenseSheet(
                authManager: authManager,
                contextPropertyId: controller.contextPropertyId
            )
            .environmentObject(authManager)
        case .receipt:
            UtilityReceiptUploadSheet { Task { await reload() } }
                .environmentObject(authManager)
        case .task:
            TaskFormView(properties: properties) {
                await reload()
            }
            .environmentObject(authManager)
        case .document:
            QuickDocumentSheet(
                authManager: authManager,
                contextPropertyId: controller.contextPropertyId
            )
            .environmentObject(authManager)
        case .tenant:
            TenantFormSheet {
                await reload()
            }
            .environmentObject(authManager)
        }
    }

    private func reload() async {
        await loadProperties()
        NotificationCenter.default.post(name: .quickActionCompleted, object: nil)
    }

    private func loadProperties() async {
        if let loaded: [Property] = try? await APIClient.shared.request(
            "/v1/properties",
            tokenProvider: { await MainActor.run { authManager.accessToken } },
            refreshAndRetry: { await authManager.refreshToken() }
        ) {
            properties = loaded
        }
    }
}

extension Notification.Name {
    /// Broadcast after a global quick action completes so visible screens can
    /// refresh affected data.
    static let quickActionCompleted = Notification.Name("quickActionCompleted")

    /// Broadcast when the daily expense reminder (GAP-038) is tapped, so the
    /// shell opens the compact expense flow.
    static let openCompactExpense = Notification.Name("openCompactExpense")
}
