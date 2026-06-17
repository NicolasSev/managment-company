import SwiftUI
import UniformTypeIdentifiers

/// Bank statement import + reconciliation (GAP-042).
struct ReconciliationView: View {
    @StateObject private var viewModel: ReconciliationViewModel
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var previewRows: [BankImportRow] = []
    @State private var previewFilename = ""
    @State private var showPreview = false
    @State private var decisionRow: BankStatementRow?

    init(authManager: AuthManager) {
        _viewModel = StateObject(wrappedValue: ReconciliationViewModel(client: LiveReconciliationClient(authManager: authManager)))
    }

    var body: some View {
        NavigationStack {
            List {
                if let result = viewModel.lastImport {
                    Section {
                        Text("Импортировано: \(result.insertedRows), дубликатов пропущено: \(result.duplicateRows)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                Section("Ожидают решения") {
                    if viewModel.pending.isEmpty, !viewModel.isLoading {
                        Text("Нет строк на сверку").foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    ForEach(viewModel.pending) { row in
                        Button { decisionRow = row } label: { rowView(row) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Task { _ = await viewModel.ignore(row) } } label: {
                                    Label("Игнорировать", systemImage: "xmark")
                                }
                            }
                    }
                }
                if !viewModel.confirmed.isEmpty {
                    Section("Сверенные") {
                        ForEach(viewModel.confirmed) { row in
                            rowView(row)
                                .swipeActions(edge: .trailing) {
                                    Button { Task { _ = await viewModel.rollback(row) } } label: {
                                        Label("Вернуть", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(AppTheme.Colors.warning)
                                }
                        }
                    }
                }
                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(AppTheme.Colors.danger) }
                }
            }
            .navigationTitle("Сверка выписки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showImporter = true } label: { Label("Импорт CSV", systemImage: "square.and.arrow.down") }
                }
            }
            .task { await viewModel.load() }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .data], allowsMultipleSelection: false) { result in
                if case let .success(urls) = result, let url = urls.first { handlePicked(url) }
            }
            .sheet(isPresented: $showPreview) {
                importPreview
            }
            .sheet(item: $decisionRow) { row in
                ReconciliationDecisionSheet(authManager: authManager, row: row) { parts in
                    await viewModel.confirm(row, parts: parts)
                }
            }
        }
    }

    private func rowView(_ row: BankStatementRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(AppFormatting.dateString(from: row.transactionDate) ?? row.transactionDate)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(AppFormatting.currency(row.amount, currency: row.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(row.amount >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger)
            }
            Text(row.description).font(.caption).foregroundStyle(AppTheme.Colors.textSecondary).lineLimit(2)
        }
    }

    private var importPreview: some View {
        NavigationStack {
            List {
                Section {
                    Text("Распознано строк: \(previewRows.count). Формат: дата,сумма,валюта,описание.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                ForEach(Array(previewRows.prefix(50).enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.transactionDate).font(.caption)
                        Spacer()
                        Text(AppFormatting.currency(row.amount, currency: row.currency)).font(.caption.weight(.semibold))
                    }
                }
            }
            .navigationTitle("Предпросмотр")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { showPreview = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Импортировать \(previewRows.count)") {
                        Task {
                            if await viewModel.importCSV(previewRows.map(csvLine).joined(separator: "\n"), filename: previewFilename) {
                                showPreview = false
                            }
                        }
                    }
                    .disabled(previewRows.isEmpty)
                }
            }
        }
    }

    private func csvLine(_ row: BankImportRow) -> String {
        "\(row.transactionDate),\(row.amount),\(row.currency),\(row.description)"
    }

    private func handlePicked(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            viewModel.errorMessage = "Не удалось прочитать файл."
            return
        }
        previewRows = ReconciliationViewModel.parseCSV(text)
        previewFilename = url.lastPathComponent
        showPreview = true
    }
}

/// Confirm a bank row into a transaction (single part) (GAP-042).
private struct ReconciliationDecisionSheet: View {
    let row: BankStatementRow
    let onConfirm: ([BankDecisionPart]) async -> Bool

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var properties: [Property] = []
    @State private var categories: [Category] = []
    @State private var rentSchedules: [PaymentQueueItem] = []
    @State private var target = "transaction"
    @State private var propertyId = ""
    @State private var categoryId = ""
    @State private var scheduleId = ""
    @State private var type = "expense"
    @State private var amountText = ""
    @State private var errorMessage: String?

    init(authManager: AuthManager, row: BankStatementRow, onConfirm: @escaping ([BankDecisionPart]) async -> Bool) {
        self.row = row
        self.onConfirm = onConfirm
    }

    private var typeCategories: [Category] {
        categories.filter { $0.type == type }.sorted { $0.sortOrder < $1.sortOrder }
    }
    private var amountValue: Double {
        Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var rentScheduleOptions: [PaymentQueueItem] {
        let amount = abs(row.amount)
        return rentSchedules
            .filter { row.amount >= 0 && $0.currency.caseInsensitiveCompare(row.currency) == .orderedSame && amount <= $0.outstandingAmount + 0.005 }
            .sorted {
                if $0.id == row.suggestedScheduleId { return true }
                if $1.id == row.suggestedScheduleId { return false }
                return $0.dueDate < $1.dueDate
            }
    }
    private var selectedSchedule: PaymentQueueItem? {
        rentSchedules.first { $0.id == scheduleId }
    }
    private var canConfirm: Bool {
        if target == "existing" {
            return row.suggestedTransactionId != nil && amountValue > 0
        }
        if target == "rent" {
            return !scheduleId.isEmpty && amountValue > 0
        }
        return !propertyId.isEmpty && !categoryId.isEmpty && amountValue > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Строка") {
                    Text(row.description).font(.subheadline)
                    Text("\(row.transactionDate) · \(AppFormatting.currency(row.amount, currency: row.currency))")
                        .font(.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                }
                if row.suggestedTransactionId != nil || (row.amount >= 0 && !rentScheduleOptions.isEmpty) {
                    Picker("Куда провести", selection: $target) {
                        if row.suggestedTransactionId != nil {
                            Text("Найденная").tag("existing")
                        }
                        if row.amount >= 0 && !rentScheduleOptions.isEmpty {
                            Text("Аренда").tag("rent")
                        }
                        Text("Операция").tag("transaction")
                    }
                    .pickerStyle(.segmented)
                }
                if target == "existing" {
                    Section("Найденная операция") {
                        Text("Похожа на уже созданную операцию. Строка выписки будет связана с ней без создания дубля.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Text(row.suggestedTransactionId ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                } else if target == "rent" {
                    Section("Начисление аренды") {
                        Picker("Платёж", selection: $scheduleId) {
                            Text("Не выбрано").tag("")
                            ForEach(rentScheduleOptions) { schedule in
                                Text(rentScheduleTitle(schedule)).tag(schedule.id)
                            }
                        }
                        if let selectedSchedule {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedSchedule.tenantName)
                                    .font(.subheadline.weight(.medium))
                                Text("\(selectedSchedule.propertyName) · срок \(AppFormatting.dateString(from: selectedSchedule.dueDate) ?? selectedSchedule.dueDate)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                Text("Остаток: \(AppFormatting.currency(selectedSchedule.outstandingAmount, currency: selectedSchedule.currency))")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                        }
                        if row.suggestedScheduleId == scheduleId, !scheduleId.isEmpty {
                            Text("Предложено по совпадению арендатора/объекта, периода и остатка начисления.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                } else {
                    Picker("Тип", selection: $type) {
                        Text("Расход").tag("expense"); Text("Доход").tag("income")
                    }.pickerStyle(.segmented)
                    Picker("Объект", selection: $propertyId) {
                        Text("Не выбрано").tag("")
                        ForEach(properties) { Text($0.name).tag($0.id) }
                    }
                    Picker("Категория", selection: $categoryId) {
                        Text("Не выбрано").tag("")
                        ForEach(typeCategories) { Text($0.name).tag($0.id) }
                    }
                }
                HStack {
                    TextField("0", text: $amountText).keyboardType(.decimalPad)
                    Text(row.currency).foregroundStyle(AppTheme.Colors.textSecondary)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(AppTheme.Colors.danger) }
            }
            .navigationTitle("Подтвердить операцию")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(target == "rent" ? "Провести оплату" : "Создать операцию") { Task { await confirm() } }
                        .disabled(!canConfirm)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        async let props: [Property]? = try? await APIClient.shared.request("/v1/properties", tokenProvider: { await MainActor.run { authManager.accessToken } }, refreshAndRetry: { await authManager.refreshToken() })
        async let cats: [Category]? = try? await APIClient.shared.request("/v1/categories", tokenProvider: { await MainActor.run { authManager.accessToken } }, refreshAndRetry: { await authManager.refreshToken() })
        async let schedules: [PaymentQueueItem]? = try? await LiveReconciliationClient(authManager: authManager).listRentSchedules(months: 24)
        properties = (await props) ?? []
        categories = (await cats) ?? []
        rentSchedules = (await schedules) ?? []
        type = row.amount >= 0 ? "income" : "expense"
        amountText = String(abs(row.amount))
        propertyId = row.suggestedPropertyId ?? properties.first?.id ?? ""
        categoryId = row.suggestedCategoryId ?? typeCategories.first?.id ?? ""
        if row.suggestedTransactionId != nil {
            target = "existing"
        } else if row.amount >= 0 {
            if let suggested = row.suggestedScheduleId, rentSchedules.contains(where: { $0.id == suggested }) {
                scheduleId = suggested
                target = "rent"
            } else if let first = rentScheduleOptions.first {
                scheduleId = first.id
            }
        }
    }

    private func confirm() async {
        let amount = amountValue
        guard amount > 0 else { return }
        let part: BankDecisionPart
        if target == "existing" {
            guard let transactionId = row.suggestedTransactionId else { return }
            part = ReconciliationViewModel.existingTransactionPart(row: row, transactionId: transactionId, amount: amount)
        } else if target == "rent" {
            guard !scheduleId.isEmpty else { return }
            part = ReconciliationViewModel.rentAllocationPart(row: row, scheduleId: scheduleId, amount: amount)
        } else {
            part = BankDecisionPart(
                propertyId: propertyId, categoryId: categoryId, type: type, amount: amount,
                description: row.description.isEmpty ? nil : row.description
            )
        }
        if await onConfirm([part]) { dismiss() } else { errorMessage = "Не удалось создать операцию." }
    }

    private func rentScheduleTitle(_ schedule: PaymentQueueItem) -> String {
        let due = AppFormatting.dateString(from: schedule.dueDate) ?? schedule.dueDate
        return "\(schedule.propertyName) · \(schedule.tenantName) · \(due)"
    }
}
