import SwiftUI
import UIKit

private struct ListedTransaction: Identifiable, Sendable {
    var id: String { transaction.id }
    let transaction: Transaction
    let propertyName: String
}

private struct TransactionDetailRoute: Identifiable {
    let id: String
    let propertyName: String?
}

private enum TransactionTypeFilter: String, CaseIterable, Identifiable {
    case all
    case income
    case expense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Все"
        case .income: return "Доход"
        case .expense: return "Расход"
        }
    }
}

private enum TransactionPeriodFilter: String, CaseIterable, Identifiable {
    case all
    case currentMonth
    case lastThreeMonths
    case currentYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "За всё время"
        case .currentMonth: return "Текущий месяц"
        case .lastThreeMonths: return "Последние 3 месяца"
        case .currentYear: return "Текущий год"
        }
    }
}

private enum TransactionExportFormat {
    case csv
    case pdf
}

private struct TransactionExportDocument: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

private struct TransactionTotals {
    let count: Int
    let incomeBase: Double
    let expenseBase: Double
    let activePropertyCount: Int

    var netBase: Double { incomeBase - expenseBase }
}

private struct PropertyTransactionSummary: Identifiable {
    let propertyId: String
    let propertyName: String
    let income: Double
    let expense: Double
    let count: Int

    var id: String { propertyId }
    var net: Double { income - expense }
}

struct TransactionsListView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject private var notificationRouter: NotificationDeepLinkRouter
    @State private var rows: [ListedTransaction] = []
    @State private var propertiesById: [String: Property] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showReceiptSheet = false
    @State private var showAddTransactionSheet = false
    @State private var selectedTransaction: TransactionDetailRoute?
    @State private var selectedPropertyId = ""
    @State private var typeFilter: TransactionTypeFilter = .all
    @State private var periodFilter: TransactionPeriodFilter = .all
    @State private var searchText = ""
    @State private var exportDocument: TransactionExportDocument?
    @State private var exportErrorMessage: String?

    private var propertiesList: [Property] {
        Array(propertiesById.values).sorted { $0.name < $1.name }
    }

    private var filteredRows: [ListedTransaction] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bounds = periodBounds(for: periodFilter)

        return rows.filter { row in
            let tx = row.transaction
            if !selectedPropertyId.isEmpty, tx.propertyId != selectedPropertyId {
                return false
            }
            if typeFilter != .all, tx.type.lowercased() != typeFilter.rawValue {
                return false
            }
            if let bounds,
               (tx.transactionDate < bounds.from || tx.transactionDate >= bounds.to) {
                return false
            }
            guard !query.isEmpty else { return true }

            let haystack = [
                row.propertyName,
                tx.type,
                tx.currency,
                tx.description,
                tx.transactionDate,
                String(tx.amount),
                String(tx.amountBase)
            ]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(query)
        }
    }

    private var totals: TransactionTotals {
        let income = filteredRows
            .filter { $0.transaction.type.lowercased() == "income" }
            .reduce(0) { $0 + $1.transaction.amountBase }
        let expense = filteredRows
            .filter { $0.transaction.type.lowercased() == "expense" }
            .reduce(0) { $0 + $1.transaction.amountBase }
        let activePropertyCount = Set(filteredRows.map { $0.transaction.propertyId }).count
        return TransactionTotals(
            count: filteredRows.count,
            incomeBase: income,
            expenseBase: expense,
            activePropertyCount: activePropertyCount
        )
    }

    private var propertySummaries: [PropertyTransactionSummary] {
        var summaries: [String: PropertyTransactionSummary] = [:]

        for row in filteredRows {
            let current = summaries[row.transaction.propertyId]
            let isIncome = row.transaction.type.lowercased() == "income"
            summaries[row.transaction.propertyId] = PropertyTransactionSummary(
                propertyId: row.transaction.propertyId,
                propertyName: row.propertyName,
                income: (current?.income ?? 0) + (isIncome ? row.transaction.amountBase : 0),
                expense: (current?.expense ?? 0) + (isIncome ? 0 : row.transaction.amountBase),
                count: (current?.count ?? 0) + 1
            )
        }

        return summaries.values
            .sorted { abs($0.net) > abs($1.net) }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()

                content
            }
            .navigationTitle("Операции")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            exportTransactions(as: .csv)
                        } label: {
                            Label("CSV", systemImage: "tablecells")
                        }
                        .disabled(filteredRows.isEmpty)

                        Button {
                            exportTransactions(as: .pdf)
                        } label: {
                            Label("PDF", systemImage: "doc.richtext")
                        }
                        .disabled(filteredRows.isEmpty)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Экспорт операций")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddTransactionSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Добавить операцию")
                }
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
            .sheet(isPresented: $showAddTransactionSheet) {
                QuickTransactionSheet(
                    propertyId: nil,
                    properties: propertiesList
                ) {
                    await loadPortfolioTransactions()
                }
                .environmentObject(authManager)
            }
            .sheet(item: $selectedTransaction) { route in
                TransactionDetailSheet(
                    transactionId: route.id,
                    propertyName: route.propertyName,
                    baseCurrency: authManager.user?.baseCurrency ?? "KZT"
                )
                .environmentObject(authManager)
            }
            .sheet(item: $exportDocument) { document in
                NavigationStack {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                            Image(systemName: "doc.badge.arrow.up")
                                .font(.title2)
                                .foregroundStyle(AppTheme.Colors.accent)

                            Text(document.title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.textPrimary)

                            Text("Экспорт построен по текущим фильтрам и видимой выборке операций.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textSecondary)

                            ShareLink(item: document.url) {
                                Label("Поделиться файлом", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                    .navigationTitle("Экспорт")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Готово") { exportDocument = nil }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .task {
                await loadPortfolioTransactions()
            }
            .onChange(of: notificationRouter.pendingRoute) { _, _ in
                Task { await handlePendingNotificationRoute() }
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

                    reportingControls

                    if let exportErrorMessage {
                        SurfaceCard(padding: AppTheme.Spacing.md) {
                            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(AppTheme.Colors.warning)
                                Text(exportErrorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                        }
                    }

                    utilityReceiptBanner

                    if filteredRows.isEmpty {
                        EmptyStateView(
                            title: "Операций по фильтрам нет",
                            message: "Попробуйте другой объект, период, тип операции или поисковый запрос.",
                            actionName: "Сбросить фильтры",
                            action: { resetFilters() },
                            icon: "line.3.horizontal.decrease.circle"
                        )
                    } else {
                        LazyVStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(filteredRows) { row in
                                Button {
                                    selectedTransaction = TransactionDetailRoute(
                                        id: row.transaction.id,
                                        propertyName: row.propertyName
                                    )
                                } label: {
                                    ListedTransactionCard(
                                        row: row,
                                        baseCurrency: authManager.user?.baseCurrency ?? "KZT"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        propertySummarySection
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
    }

    private var reportingControls: some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Отчетная выборка")
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        Text("Фильтры, итоговые суммы и экспорт считают только видимые операции.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Spacer()

                    Menu {
                        Button {
                            exportTransactions(as: .csv)
                        } label: {
                            Label("CSV", systemImage: "tablecells")
                        }
                        .disabled(filteredRows.isEmpty)

                        Button {
                            exportTransactions(as: .pdf)
                        } label: {
                            Label("PDF", systemImage: "doc.richtext")
                        }
                        .disabled(filteredRows.isEmpty)
                    } label: {
                        Label("Экспорт", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                    TextField("Поиск по объекту, типу, описанию", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, 11)
                .background(AppTheme.Colors.backgroundSecondary.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: AppTheme.Spacing.sm) {
                    Picker("Объект", selection: $selectedPropertyId) {
                        Text("Все объекты").tag("")
                        ForEach(propertiesList) { property in
                            Text(property.name).tag(property.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("Период", selection: $periodFilter) {
                        ForEach(TransactionPeriodFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("Тип", selection: $typeFilter) {
                        ForEach(TransactionTypeFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.sm) {
                    transactionMetric(title: "Операций", value: "\(totals.count)", color: AppTheme.Colors.accent)
                    transactionMetric(
                        title: "Доходы",
                        value: AppFormatting.compactAmount(totals.incomeBase, currency: baseCurrency),
                        color: AppTheme.Colors.success
                    )
                    transactionMetric(
                        title: "Расходы",
                        value: AppFormatting.compactAmount(totals.expenseBase, currency: baseCurrency),
                        color: AppTheme.Colors.danger
                    )
                    transactionMetric(
                        title: "Чистое",
                        value: AppFormatting.compactAmount(totals.netBase, currency: baseCurrency),
                        color: totals.netBase >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger
                    )
                }
            }
        }
    }

    private var propertySummarySection: some View {
        SurfaceCard(padding: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Динамика по объектам")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                if propertySummaries.isEmpty {
                    Text("Сводка появится после операций в текущей выборке.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } else {
                    ForEach(propertySummaries) { summary in
                        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(summary.propertyName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                Text("Операций в выборке: \(summary.count)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text(AppFormatting.compactAmount(summary.net, currency: baseCurrency))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(summary.net >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger)
                                Text("\(AppFormatting.compactAmount(summary.income, currency: baseCurrency)) / \(AppFormatting.compactAmount(summary.expense, currency: baseCurrency))")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                        }
                        .padding(.vertical, 6)
                        Divider().opacity(0.35)
                    }
                }
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

    private var baseCurrency: String {
        authManager.user?.baseCurrency ?? "KZT"
    }

    private func transactionMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @MainActor
    private func loadPortfolioTransactions() async {
        errorMessage = nil
        if rows.isEmpty { isLoading = true }
        defer { isLoading = false }

        // 1. Properties are the entry point — a genuine failure here is the only
        //    reason to show the full "Операции недоступны" state.
        let properties: [Property]
        do {
            properties = try await APIClient.shared.request(
                "/v1/properties",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
        } catch {
            rows = []
            errorMessage = "Не удалось загрузить журнал операций."
            return
        }

        propertiesById = Dictionary(uniqueKeysWithValues: properties.map { ($0.id, $0) })
        if !selectedPropertyId.isEmpty, propertiesById[selectedPropertyId] == nil {
            selectedPropertyId = ""
        }

        guard !properties.isEmpty else {
            rows = []
            return
        }

        // 2. Fetch each property's transactions concurrently and tolerate partial
        //    failures: one flaky request must not discard everything that loaded.
        let auth = authManager
        let outcome = await withTaskGroup(
            of: (rows: [ListedTransaction], failed: Bool).self
        ) { group in
            for property in properties {
                group.addTask {
                    do {
                        let data = try await APIClient.shared.requestData(
                            "/v1/properties/\(property.id)/transactions?per_page=100",
                            tokenProvider: { await MainActor.run { auth.accessToken } },
                            refreshAndRetry: { await auth.refreshToken() }
                        )
                        let decoded = try JSONDecoder().decode(APIResponse<[Transaction]>.self, from: data)
                        let listed = decoded.data.map {
                            ListedTransaction(transaction: $0, propertyName: property.name)
                        }
                        return (listed, false)
                    } catch {
                        return ([], true)
                    }
                }
            }

            var merged: [ListedTransaction] = []
            var failures = 0
            for await result in group {
                merged.append(contentsOf: result.rows)
                if result.failed { failures += 1 }
            }
            return (merged, failures)
        }

        // 3. Every property request failed → nothing to show, surface the error.
        if outcome.1 == properties.count {
            rows = []
            errorMessage = "Не удалось загрузить журнал операций."
            return
        }

        var merged = outcome.0
        merged.sort {
            ($0.transaction.transactionDate, $0.id) > ($1.transaction.transactionDate, $1.id)
        }
        rows = merged

        // 4. Partial success → keep the data, warn inline (banner above the list).
        if outcome.1 > 0 {
            errorMessage = "Часть объектов не загрузилась (\(outcome.1) из \(properties.count)). Потяните список вниз, чтобы повторить."
        }

        await handlePendingNotificationRoute()
    }

    private func handlePendingNotificationRoute() async {
        guard let route = notificationRouter.pendingRoute,
              case .transaction(let transactionId) = route.kind else { return }

        if isLoading && rows.isEmpty { return }

        let row = rows.first(where: { $0.transaction.id == transactionId })
        selectedTransaction = TransactionDetailRoute(
            id: transactionId,
            propertyName: row?.propertyName
        )
        notificationRouter.clearRoute(route)
    }

    private func periodBounds(for filter: TransactionPeriodFilter) -> (from: String, to: String)? {
        guard filter != .all else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let startOfCurrentMonth = calendar.date(from: DateComponents(year: components.year, month: components.month, day: 1)),
              let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfCurrentMonth),
              let year = components.year,
              let startOfCurrentYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let startOfNextYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return nil
        }

        switch filter {
        case .all:
            return nil
        case .currentMonth:
            return (Self.isoDate(startOfCurrentMonth), Self.isoDate(startOfNextMonth))
        case .lastThreeMonths:
            let from = calendar.date(byAdding: .month, value: -2, to: startOfCurrentMonth) ?? startOfCurrentMonth
            return (Self.isoDate(from), Self.isoDate(startOfNextMonth))
        case .currentYear:
            return (Self.isoDate(startOfCurrentYear), Self.isoDate(startOfNextYear))
        }
    }

    private func resetFilters() {
        selectedPropertyId = ""
        typeFilter = .all
        periodFilter = .all
        searchText = ""
    }

    private func exportTransactions(as format: TransactionExportFormat) {
        exportErrorMessage = nil
        do {
            let url: URL
            let title: String
            switch format {
            case .csv:
                url = try makeTransactionsCSV()
                title = "CSV готов"
            case .pdf:
                url = try makeTransactionsPDF()
                title = "PDF готов"
            }
            exportDocument = TransactionExportDocument(title: title, url: url)
        } catch {
            exportErrorMessage = "Не удалось подготовить экспорт операций."
        }
    }

    private func makeTransactionsCSV() throws -> URL {
        let headers = ["date", "property", "type", "amount", "currency", "amount_base", "description"]
        let lines = [headers] + filteredRows.map { row in
            [
                row.transaction.transactionDate,
                row.propertyName,
                row.transaction.type,
                String(row.transaction.amount),
                row.transaction.currency,
                String(row.transaction.amountBase),
                row.transaction.description ?? ""
            ]
        }
        let csv = lines.map { $0.map(Self.csvEscape).joined(separator: ",") }.joined(separator: "\n")
        let url = temporaryExportURL(prefix: "transactions-export", fileExtension: "csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTransactionsPDF() throws -> URL {
        let url = temporaryExportURL(prefix: "transactions-export", fileExtension: "pdf")
        let bounds = CGRect(x: 0, y: 0, width: 842, height: 595)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let rowsForExport = filteredRows
        let totalsForExport = totals
        let summary = exportSummaryLine

        try renderer.writePDF(to: url) { context in
            var y = drawTransactionsPDFHeader(
                context: context,
                bounds: bounds,
                totals: totalsForExport,
                summary: summary
            )
            drawTransactionsPDFTableHeader(at: &y, bounds: bounds)

            for row in rowsForExport {
                if y > bounds.height - 46 {
                    y = drawTransactionsPDFHeader(
                        context: context,
                        bounds: bounds,
                        totals: totalsForExport,
                        summary: summary
                    )
                    drawTransactionsPDFTableHeader(at: &y, bounds: bounds)
                }
                drawTransactionsPDFRow(row, at: &y, bounds: bounds)
            }
        }

        return url
    }

    private var exportSummaryLine: String {
        let propertyLabel = selectedPropertyId.isEmpty
            ? "Все объекты"
            : (propertiesById[selectedPropertyId]?.name ?? "Выбранный объект")
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryLabel = query.isEmpty ? "без поиска" : "поиск: \(query)"
        return "\(propertyLabel) · \(periodFilter.title) · \(typeFilter.title) · \(queryLabel)"
    }

    private func temporaryExportURL(prefix: String, fileExtension ext: String) -> URL {
        let stamp = Self.exportTimestamp()
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(stamp).\(ext)")
    }

    nonisolated private static func csvEscape(_ raw: String) -> String {
        let escaped = raw.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    nonisolated private static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    nonisolated private static func exportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    @discardableResult
    private func drawTransactionsPDFHeader(
        context: UIGraphicsPDFRendererContext,
        bounds: CGRect,
        totals: TransactionTotals,
        summary: String
    ) -> CGFloat {
        context.beginPage()
        var y: CGFloat = 34
        drawPDFText("Экспорт операций", x: 32, y: y, width: bounds.width - 64, font: .boldSystemFont(ofSize: 20))
        y += 28
        drawPDFText(summary, x: 32, y: y, width: bounds.width - 64, font: .systemFont(ofSize: 10), color: .darkGray)
        y += 20
        let totalsLine = "Операций: \(totals.count) · Доходы: \(AppFormatting.compactAmount(totals.incomeBase, currency: baseCurrency)) · Расходы: \(AppFormatting.compactAmount(totals.expenseBase, currency: baseCurrency)) · Чистое: \(AppFormatting.compactAmount(totals.netBase, currency: baseCurrency))"
        drawPDFText(totalsLine, x: 32, y: y, width: bounds.width - 64, font: .systemFont(ofSize: 10), color: .darkGray)
        return y + 28
    }

    private func drawTransactionsPDFTableHeader(at y: inout CGFloat, bounds: CGRect) {
        let headers = ["Дата", "Объект", "Тип", "Сумма", "База", "Описание"]
        let columns = transactionPDFColumns(bounds: bounds)
        for index in headers.indices {
            drawPDFText(headers[index], x: columns[index].minX, y: y, width: columns[index].width, font: .boldSystemFont(ofSize: 9))
        }
        y += 17
    }

    private func drawTransactionsPDFRow(_ row: ListedTransaction, at y: inout CGFloat, bounds: CGRect) {
        let columns = transactionPDFColumns(bounds: bounds)
        let values = [
            row.transaction.transactionDate,
            row.propertyName,
            row.transaction.type,
            AppFormatting.compactAmount(row.transaction.amount, currency: row.transaction.currency),
            AppFormatting.compactAmount(row.transaction.amountBase, currency: baseCurrency),
            row.transaction.description ?? ""
        ]
        for index in values.indices {
            drawPDFText(values[index], x: columns[index].minX, y: y, width: columns[index].width, font: .systemFont(ofSize: 8.5), color: .black)
        }
        y += 15
    }

    private func transactionPDFColumns(bounds: CGRect) -> [CGRect] {
        let x: CGFloat = 32
        return [
            CGRect(x: x, y: 0, width: 82, height: 14),
            CGRect(x: x + 88, y: 0, width: 160, height: 14),
            CGRect(x: x + 254, y: 0, width: 58, height: 14),
            CGRect(x: x + 318, y: 0, width: 94, height: 14),
            CGRect(x: x + 418, y: 0, width: 98, height: 14),
            CGRect(x: x + 522, y: 0, width: bounds.width - 554, height: 14)
        ]
    }

    private func drawPDFText(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        font: UIFont,
        color: UIColor = .black
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            in: CGRect(x: x, y: y, width: width, height: 18),
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
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
