import SwiftUI

private enum TaskScope: String, CaseIterable, Identifiable {
    case open = "Открыто"
    case all = "All"
    case completed = "Завершено"

    var id: String { rawValue }
}

struct TasksListView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var tasks: [AppTask] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showTaskForm = false
    @State private var searchText = ""
    @State private var selectedScope: TaskScope = .open
    @State private var actionMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()

                content
            }
            .navigationTitle("Задачи")
            .searchable(text: $searchText, prompt: "Поиск задач")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showTaskForm = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .task { await loadTasks() }
            .refreshable { await loadTasks() }
            .navigationDestination(for: AppTask.self) { task in
                TaskFormView(task: task) { await loadTasks() }
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showTaskForm) {
                TaskFormView(task: nil) { await loadTasks() }
                    .environmentObject(authManager)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, tasks.isEmpty {
            EmptyStateView(
                title: "Не удалось загрузить задачи",
                message: errorMessage,
                actionName: "Повторить",
                action: { Task { await loadTasks() } },
                icon: "wifi.exclamationmark"
            )
        } else if scopedTasks.isEmpty {
            EmptyStateView(
                title: tasks.isEmpty ? "Задач пока нет" : "Нет подходящих задач",
                message: tasks.isEmpty
                    ? "Создайте первую задачу, чтобы держать операции в движении."
                    : "Попробуйте другой фильтр или поисковую фразу.",
                actionName: tasks.isEmpty ? "Добавить задачу" : "Сбросить фильтры",
                action: {
                    if tasks.isEmpty {
                        showTaskForm = true
                    } else {
                        selectedScope = .all
                        searchText = ""
                    }
                },
                icon: "checklist"
            )
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.Spacing.lg) {
                    taskSummary
                    filterSummaryCard
                    if let bannerMessage = activeBannerMessage {
                        statusBanner(
                            bannerMessage,
                            color: errorMessage == nil ? AppTheme.Colors.success : AppTheme.Colors.danger
                        )
                    }

                    if selectedScope == .completed {
                        taskSection(
                            title: "Завершено",
                            icon: "checkmark.circle.fill",
                            items: completedTasksList
                        )
                    } else {
                        if !overdueTasks.isEmpty {
                            taskSection(
                                title: "Просрочено",
                                icon: "exclamationmark.triangle.fill",
                                items: overdueTasks
                            )
                        }
                        if !todayTasks.isEmpty {
                            taskSection(
                                title: "Сегодня",
                                icon: "sun.max.fill",
                                items: todayTasks
                            )
                        }
                        if !upcomingTasks.isEmpty {
                            taskSection(
                                title: "Предстоящие",
                                icon: "calendar",
                                items: upcomingTasks
                            )
                        }
                        if !unscheduledTasks.isEmpty {
                            taskSection(
                                title: "Без срока",
                                icon: "tray.fill",
                                items: unscheduledTasks
                            )
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
    }

    private var searchedTasks: [AppTask] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return tasks }

        return tasks.filter { task in
            let haystack = [
                task.title,
                task.description ?? "",
                task.priority,
                task.status,
            ]
                .joined(separator: " ")
                .lowercased()

            return haystack.contains(query)
        }
    }

    private var scopedTasks: [AppTask] {
        switch selectedScope {
        case .open:
            return searchedTasks.filter(isOpenTask)
        case .all:
            return searchedTasks
        case .completed:
            return searchedTasks.filter(isCompletedTask)
        }
    }
    
    private var overdueTasks: [AppTask] {
        scopedTasks.filter { task in
            guard let due = dueDateValue(for: task) else { return false }
            return due < startOfToday && !calendar.isDate(due, inSameDayAs: Date()) && isOpenTask(task)
        }
        .sorted { (dueDateValue(for: $0) ?? .distantFuture) < (dueDateValue(for: $1) ?? .distantFuture) }
    }
    
    private var todayTasks: [AppTask] {
        scopedTasks.filter { task in
            guard let due = dueDateValue(for: task) else { return false }
            return calendar.isDate(due, inSameDayAs: Date()) && isOpenTask(task)
        }
    }
    
    private var upcomingTasks: [AppTask] {
        scopedTasks.filter { task in
            guard let due = dueDateValue(for: task) else { return false }
            return due >= startOfTomorrow && isOpenTask(task)
        }
        .sorted { (dueDateValue(for: $0) ?? .distantFuture) < (dueDateValue(for: $1) ?? .distantFuture) }
    }

    private var unscheduledTasks: [AppTask] {
        scopedTasks.filter { dueDateValue(for: $0) == nil && isOpenTask($0) }
    }

    private var completedTasksList: [AppTask] {
        scopedTasks.filter(isCompletedTask)
    }

    private var tasksDueTodayCount: Int {
        tasks.filter { task in
            guard let due = dueDateValue(for: task) else { return false }
            return calendar.isDate(due, inSameDayAs: Date()) && isOpenTask(task)
        }.count
    }
    
    private var calendar: Calendar {
        .current
    }

    private var startOfToday: Date {
        calendar.startOfDay(for: Date())
    }

    private var startOfTomorrow: Date {
        calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
    }

    private var taskSummary: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Исполнение")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text("Спокойный способ понять, что требует внимания дальше.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Picker("Фильтр", selection: $selectedScope) {
                    ForEach(TaskScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: AppTheme.Spacing.sm) {
                    taskMetric(title: "Открыто", value: "\(tasks.filter(isOpenTask).count)")
                    taskMetric(title: "Сегодня", value: "\(tasksDueTodayCount)")
                    taskMetric(title: "Готово", value: "\(tasks.filter(isCompletedTask).count)")
                }
            }
        }
    }

    private var filterSummaryCard: some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Текущий фокус")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(filterSummaryText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Поиск идет по названию, описанию, приоритету и статусу.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    private func taskMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func taskSection(title: String, icon: String, items: [AppTask]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer()

                Text("\(items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            LazyVStack(spacing: AppTheme.Spacing.md) {
                ForEach(items) { task in
                    NavigationLink(value: task) {
                        TaskRow(task: task)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: isOpenTask(task)) {
                        if isOpenTask(task) {
                            Button {
                                Task { await completeTask(task) }
                            } label: {
                                Label("Завершить", systemImage: "checkmark.circle.fill")
                            }
                            .tint(AppTheme.Colors.success)
                        }
                    }
                    .contextMenu {
                        if isOpenTask(task) {
                            Button {
                                Task { await completeTask(task) }
                            } label: {
                                Label("Отметить завершенной", systemImage: "checkmark.circle")
                            }
                        }

                        if let due = AppFormatting.dateString(from: task.dueDate) {
                            Label(due, systemImage: "calendar")
                        }
                    }
                }
            }
        }
    }
    
    private func loadTasks() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tasks = try await APIClient.shared.request(
                "/v1/tasks",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
        } catch {
            errorMessage = "Доска задач временно недоступна."
            tasks = []
        }
    }

    private func normalizeStatus(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    private func isCompletedTask(_ task: AppTask) -> Bool {
        let normalized = normalizeStatus(task.status)
        return normalized == "completed" || normalized == "done"
    }

    private func isOpenTask(_ task: AppTask) -> Bool {
        let normalized = normalizeStatus(task.status)
        return normalized != "cancelled" && !isCompletedTask(task)
    }

    private func dueDateValue(for task: AppTask) -> Date? {
        guard let value = task.dueDate else { return nil }
        return AppFormatting.parsedDate(from: value)
    }

    private var filterSummaryText: String {
        let scopeLabel = selectedScope.rawValue.lowercased()
        let count = scopedTasks.count
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if query.isEmpty {
            return "Showing \(count) \(scopeLabel) task\(count == 1 ? "" : "s") across the mobile board."
        }

        return "Showing \(count) \(scopeLabel) task\(count == 1 ? "" : "s") matching “\(query)”."
    }

    private var activeBannerMessage: String? {
        errorMessage ?? actionMessage
    }

    private func statusBanner(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func completeTask(_ task: AppTask) async {
        errorMessage = nil

        do {
            _ = try await APIClient.shared.requestData(
                "/v1/tasks/\(task.id)",
                method: "PUT",
                body: TaskStatusInput(status: "done"),
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            AppHaptics.success()
            actionMessage = "Задача “\(task.title)” завершена."
            await loadTasks()
        } catch {
            AppHaptics.warning()
            errorMessage = "Не удалось обновить задачу."
        }
    }
}

struct TaskRow: View {
    let task: AppTask
    
    var body: some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        if let due = formattedDueDate {
                            Label(due, systemImage: "calendar")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        } else {
                            Text("Без срока")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }

                    Spacer()

                    StatusBadge(status: task.status)
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    StatusBadge(status: task.priority)

                    if let description = task.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var formattedDueDate: String? {
        AppFormatting.dateString(from: task.dueDate)
    }
}

private struct TaskStatusInput: Encodable {
    let status: String
}
