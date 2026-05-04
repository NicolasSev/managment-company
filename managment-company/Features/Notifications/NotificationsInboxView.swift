import SwiftUI

/// Список уведомлений (`GET /v1/notifications`) и отметка прочитанным.
struct NotificationsInboxView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    /// Вызвать после изменения списка (обновить бейдж на главной).
    var onDataChanged: () async -> Void

    @State private var items: [AppNotification] = []
    @State private var unreadOnPage = 0
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()
                if isLoading && items.isEmpty {
                    ProgressView()
                } else if let errorMessage, items.isEmpty {
                    EmptyStateView(
                        title: "Уведомления недоступны",
                        message: errorMessage,
                        actionName: "Повторить",
                        action: { Task { await load() } },
                        icon: "bell.slash"
                    )
                } else {
                    List {
                        ForEach(items) { row in
                            notificationRow(row)
                                .listRowBackground(AppTheme.Colors.backgroundSecondary.opacity(0.5))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Уведомления")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if unreadOnPage > 0 {
                        Button("Все прочитаны") {
                            Task { await markAllRead() }
                        }
                    }
                }
            }
            .refreshable { await load() }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func notificationRow(_ n: AppNotification) -> some View {
        Button {
            Task { await markReadIfNeeded(n) }
        } label: {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                Image(systemName: n.readAt == nil ? "circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(n.readAt == nil ? AppTheme.Colors.accent : AppTheme.Colors.textTertiary)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(n.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let body = n.body, !body.isEmpty {
                        Text(body)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Text(dateLabel(n.createdAt))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, AppTheme.Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    private func dateLabel(_ iso: String) -> String {
        if let d = AppFormatting.parsedDate(from: iso) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateStyle = .medium
            f.timeStyle = .short
            return f.string(from: d)
        }
        return iso
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page: NotificationsListResponse = try await APIClient.shared.requestRoot(
                "/v1/notifications?page=1&per_page=30",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            await MainActor.run {
                items = page.data
                unreadOnPage = page.unreadCount
            }
        } catch {
            await MainActor.run {
                errorMessage = "Не удалось загрузить уведомления."
            }
        }
    }

    private func markReadIfNeeded(_ n: AppNotification) async {
        guard n.readAt == nil else { return }
        do {
            _ = try await APIClient.shared.request(
                "/v1/notifications/\(n.id)/read",
                method: "PUT",
                body: EmptyJSONBody(),
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            ) as APIJsonOk
            await MainActor.run {
                let nowIso = ISO8601DateFormatter().string(from: Date())
                items = items.map { row in
                    guard row.id == n.id else { return row }
                    return AppNotification(
                        id: row.id,
                        type: row.type,
                        title: row.title,
                        body: row.body,
                        readAt: nowIso,
                        createdAt: row.createdAt
                    )
                }
                unreadOnPage = max(0, unreadOnPage - 1)
            }
            await onDataChanged()
        } catch {
            await MainActor.run {
                errorMessage = "Не удалось отметить прочитанным."
            }
        }
    }

    private func markAllRead() async {
        do {
            _ = try await APIClient.shared.request(
                "/v1/notifications/read-all",
                method: "PUT",
                body: EmptyJSONBody(),
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            ) as APIJsonOk
            await load()
            await onDataChanged()
        } catch {
            await MainActor.run {
                errorMessage = "Не удалось отметить все прочитанными."
            }
        }
    }
}
