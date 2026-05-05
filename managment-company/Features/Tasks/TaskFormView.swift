import SwiftUI

struct TaskFormView: View {
    var task: AppTask?
    var onSave: () async -> Void
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var details = ""
    @State private var dueDate = Date()
    @State private var hasDueDate = true
    @State private var reminderAt = Date()
    @State private var hasReminder = false
    @State private var priority = "medium"
    @State private var status = "pending"
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let priorities = ["low", "medium", "high"]
    private let statuses = ["pending", "in_progress", "done", "cancelled"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Задача") {
                    AppTextField(title: "Имя", text: $title, placeholder: "Название задачи")
                    AppTextField(
                        title: "Описание",
                        text: $details,
                        placeholder: "Что нужно сделать дальше?"
                    )
                }
                Section("Статус") {
                    Picker("Статус", selection: $status) {
                        ForEach(statuses, id: \.self) {
                            Text(displayStatus($0)).tag($0)
                        }
                    }
                }
                Section("Срок") {
                    Toggle("Указать срок оплаты", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Срок", selection: $dueDate, displayedComponents: .date)
                        HStack(spacing: AppTheme.Spacing.sm) {
                            quickDateButton("Сегодня") {
                                dueDate = Date()
                            }
                            quickDateButton("Завтра") {
                                dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                            }
                            quickDateButton("Через неделю") {
                                dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                            }
                        }
                    }
                }
                Section("Напоминание") {
                    Toggle("Поставить напоминание", isOn: $hasReminder)
                    if hasReminder {
                        DatePicker(
                            "Напоминание",
                            selection: $reminderAt,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
                Section("Приоритет") {
                    Picker("Приоритет", selection: $priority) {
                        ForEach(priorities, id: \.self) { Text($0.capitalized) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Сводка изменений")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(summaryText)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
            }
            .navigationTitle(task == nil ? "Новая задача" : "Редактировать задачу")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
            .onAppear { populateFromTask() }
        }
    }
    
    private func populateFromTask() {
        guard let t = task else { return }
        title = t.title
        details = t.description ?? ""
        priority = t.priority
        status = normalizeStatus(t.status)
        if let due = t.dueDate {
            dueDate = AppFormatting.parsedDate(from: due) ?? Date()
            hasDueDate = true
        } else {
            hasDueDate = false
        }
        if let reminder = t.reminderAt {
            reminderAt = AppFormatting.parsedDate(from: reminder) ?? Date()
            hasReminder = true
        } else {
            hasReminder = false
        }
    }
    
    private func save() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dueString = hasDueDate ? formatter.string(from: dueDate) : nil
        let reminderString = hasReminder ? ISO8601DateFormatter().string(from: reminderAt) : nil
        
        let body = TaskInput(
            title: title,
            description: details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : details,
            priority: priority,
            status: status,
            dueDate: dueString,
            reminderAt: reminderString
        )
        
        do {
            if let id = task?.id {
                _ = try await APIClient.shared.requestData(
                    "/v1/tasks/\(id)",
                    method: "PUT",
                    body: body,
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                )
            } else {
                _ = try await APIClient.shared.requestData(
                    "/v1/tasks",
                    method: "POST",
                    body: body,
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                )
            }
            AppHaptics.success()
            await onSave()
            dismiss()
        } catch {
            AppHaptics.warning()
            errorMessage = "Не удалось сохранить задачу."
        }
    }

    private var summaryText: String {
        var pieces = ["Статус: \(displayStatus(status))", "Приоритет: \(priorityLabel(priority))"]

        if let due = hasDueDate ? AppFormatting.dateString(from: dueDateStringValue) : nil {
            pieces.append("Срок: \(due)")
        }

        if let reminder = hasReminder ? AppFormatting.dateString(from: reminderStringValue) : nil {
            pieces.append("Напоминание: \(reminder)")
        }

        return pieces.joined(separator: " • ")
    }

    private var dueDateStringValue: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: dueDate)
    }

    private var reminderStringValue: String {
        ISO8601DateFormatter().string(from: reminderAt)
    }

    private func displayStatus(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func priorityLabel(_ value: String) -> String {
        switch value {
        case "low": return "Низкий"
        case "medium": return "Средний"
        case "high": return "Высокий"
        default: return value.capitalized
        }
    }

    private func normalizeStatus(_ value: String) -> String {
        let normalized = value.lowercased().replacingOccurrences(of: " ", with: "_")
        switch normalized {
        case "todo":
            return "pending"
        case "completed":
            return "done"
        default:
            return normalized
        }
    }

    private func quickDateButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            action()
            AppHaptics.selection()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TaskInput: Encodable {
    let title: String
    let description: String?
    let priority: String
    let status: String
    let dueDate: String?
    let reminderAt: String?
    
    enum CodingKeys: String, CodingKey {
        case title, description, priority, status
        case dueDate = "due_date"
        case reminderAt = "reminder_at"
    }
}
