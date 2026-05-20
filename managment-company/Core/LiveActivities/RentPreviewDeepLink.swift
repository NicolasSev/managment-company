#if os(iOS)
import Combine
import Foundation
import SwiftUI

/// Minimal deep link router for `propmanager://schedule/<id>/preview` URLs sent
/// from the Live Activity "Просмотреть" button. The Activity opens the app and
/// we surface a sheet with the prefilled mark-paid form so the user can verify
/// the operation before confirming.
/// Tiny Identifiable wrapper so SwiftUI sheet(item:) can present the preview
/// without rebuilding when the underlying optional changes.
struct RentPreviewItem: Identifiable, Hashable {
    let id: String
}

@MainActor
final class RentPreviewRouter: ObservableObject {
    @Published var pendingScheduleId: String?

    func handle(url: URL) -> Bool {
        guard url.scheme == "propmanager" else { return false }
        // Expecting: propmanager://schedule/<id>/preview
        let parts = url.pathComponents.filter { $0 != "/" }
        guard url.host == "schedule", parts.count >= 2, parts[1] == "preview" else { return false }
        pendingScheduleId = parts[0]
        return true
    }

    func clear() {
        pendingScheduleId = nil
    }
}

/// Preview sheet shown when the user taps "Просмотреть" on the Live Activity.
/// Shows the reminder details + a button that calls the same mark-paid endpoint
/// the green button on the Activity would call — letting us test the end-to-end
/// flow from the UI.
struct RentPreviewSheet: View {
    let scheduleId: String
    let onClose: () -> Void

    @State private var reminder: LiveActivityAPI.ActiveReminder?
    @State private var loading = true
    @State private var statusMessage: String?
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().controlSize(.large)
                } else if let reminder {
                    Form {
                        Section("Объект") {
                            LabeledContent("Адрес", value: reminder.property_name)
                            LabeledContent("Арендатор", value: reminder.tenant_name)
                            LabeledContent("Период", value: reminder.period_start)
                            LabeledContent("Дедлайн", value: reminder.due_date)
                        }
                        Section("Сумма") {
                            LabeledContent("К оплате", value: "\(Int(reminder.expected_amount)) \(reminder.currency)")
                        }
                        if let statusMessage {
                            Section { Text(statusMessage).foregroundStyle(.secondary) }
                        }
                        Section {
                            Button {
                                Task { await markPaid(reminder) }
                            } label: {
                                Label("Записать оплату", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                    }
                } else {
                    ContentUnavailableView("Напоминание не найдено",
                                          systemImage: "questionmark.circle",
                                          description: Text("Schedule \(scheduleId) больше не активен."))
                }
            }
            .navigationTitle("Предпросмотр оплаты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", action: onClose)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        let reminders = await LiveActivityAPI.fetchActiveReminders(auth: authManager)
        reminder = reminders.first(where: { $0.schedule_id == scheduleId })
        loading = false
    }

    private func markPaid(_ reminder: LiveActivityAPI.ActiveReminder) async {
        do {
            try await LiveActivityAPI.markPaid(
                scheduleId: reminder.schedule_id,
                amount: reminder.expected_amount,
                currency: reminder.currency,
                auth: authManager
            )
            statusMessage = "✅ Транзакция записана"
            try? await Task.sleep(nanoseconds: 800_000_000)
            onClose()
        } catch {
            statusMessage = "❌ Ошибка: \(error.localizedDescription)"
        }
    }
}
#endif
