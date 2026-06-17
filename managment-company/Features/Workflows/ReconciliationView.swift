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
    @State private var propertyId = ""
    @State private var categoryId = ""
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
    private var canConfirm: Bool {
        !propertyId.isEmpty && !categoryId.isEmpty && (Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Строка") {
                    Text(row.description).font(.subheadline)
                    Text("\(row.transactionDate) · \(AppFormatting.currency(row.amount, currency: row.currency))")
                        .font(.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                }
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
                    Button("Создать операцию") { Task { await confirm() } }
                        .disabled(!canConfirm)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        async let props: [Property]? = try? await APIClient.shared.request("/v1/properties", tokenProvider: { await MainActor.run { authManager.accessToken } }, refreshAndRetry: { await authManager.refreshToken() })
        async let cats: [Category]? = try? await APIClient.shared.request("/v1/categories", tokenProvider: { await MainActor.run { authManager.accessToken } }, refreshAndRetry: { await authManager.refreshToken() })
        properties = (await props) ?? []
        categories = (await cats) ?? []
        type = row.amount >= 0 ? "income" : "expense"
        amountText = String(abs(row.amount))
        propertyId = row.suggestedPropertyId ?? properties.first?.id ?? ""
        categoryId = row.suggestedCategoryId ?? typeCategories.first?.id ?? ""
    }

    private func confirm() async {
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")), amount > 0 else { return }
        let part = BankDecisionPart(
            propertyId: propertyId, categoryId: categoryId, type: type, amount: amount,
            description: row.description.isEmpty ? nil : row.description
        )
        if await onConfirm([part]) { dismiss() } else { errorMessage = "Не удалось создать операцию." }
    }
}
