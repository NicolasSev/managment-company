import SwiftUI
import UIKit

struct PropertyDetailView: View {
    let property: Property
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var transactions: [Transaction] = []
    @State private var tenants: [Tenant] = []
    @State private var leases: [Lease] = []
    @State private var utilities: [PropertyUtility] = []
    @State private var utilitiesHistoryExtra: [PropertyUtility] = []
    @State private var utilityReceipts: [UtilityReceiptPayload] = []
    @State private var maintenanceRequests: [MaintenanceRequest] = []
    @State private var leaseSchedulesByLeaseId: [String: [LeasePaymentSchedule]] = [:]
    @State private var scheduleForMarkPaidSheet: LeasePaymentSchedule?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showTransactionSheet = false
    @State private var showEditForm = false
    @State private var showUtilityForm = false
    @State private var editingUtility: PropertyUtility?
    @State private var selectedUtility: PropertyUtility?
    @State private var selectedUtilityReceipt: UtilityReceiptRoute?
    @State private var showMaintenanceForm = false
    @State private var editingMaintenance: MaintenanceRequest?
    @State private var maintenanceToDelete: MaintenanceRequest?
    @State private var updatingMaintenanceId: String?
    @State private var editingTransaction: Transaction?
    @State private var transactionToDelete: Transaction?
    @State private var utilityToDelete: PropertyUtility?
    @State private var receiptToDelete: UtilityReceiptPayload?
    @State private var showLeaseForm = false
    @State private var editingLease: Lease?
    @State private var leaseToTerminate: Lease?
    @State private var generatingScheduleLeaseId: String?
    @State private var linkedTransaction: LinkedTransactionRoute?
    @State private var purchaseUSDEquivalent: ExchangeRateConversionDTO?
    @State private var welcomeCopyMessage: String?

    /// Merges paginated property utilities with portfolio history (longer horizon) for this object.
    private var utilitiesForDisplay: [PropertyUtility] {
        var merged: [String: PropertyUtility] = Dictionary(uniqueKeysWithValues: utilities.map { ($0.id, $0) })
        for extra in utilitiesHistoryExtra where extra.propertyId == property.id {
            merged[extra.id] = merged[extra.id] ?? extra
        }
        return Array(merged.values).sorted {
            if $0.periodYear == $1.periodYear {
                return $0.periodMonth > $1.periodMonth
            }
            return $0.periodYear > $1.periodYear
        }
    }

    private var utilityReceiptsForDisplay: [UtilityReceiptPayload] {
        utilityReceipts.sorted { left, right in
            let leftPeriod = UtilityReceiptDisplay.receiptPeriodSortKey(left)
            let rightPeriod = UtilityReceiptDisplay.receiptPeriodSortKey(right)
            if leftPeriod == rightPeriod {
                return UtilityReceiptDisplay.receiptDateSortKey(left) > UtilityReceiptDisplay.receiptDateSortKey(right)
            }
            return leftPeriod > rightPeriod
        }
    }

    private var utilityReceiptById: [String: UtilityReceiptPayload] {
        Dictionary(uniqueKeysWithValues: utilityReceipts.map { ($0.id, $0) })
    }

    private var purchasePriceText: String {
        guard let price = property.purchasePrice else { return "Не указано" }
        let kztValue = AppFormatting.currency(price, currency: property.purchaseCurrency ?? "KZT")
        guard let purchaseUSDEquivalent else { return kztValue }
        return "\(kztValue) / ≈ \(AppFormatting.compactAmount(purchaseUSDEquivalent.convertedAmount, currency: "USD"))"
    }

    private var tenantWelcomeText: String {
        let address = property.displayAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        let wifiLogin = property.wifiLogin?.trimmingCharacters(in: .whitespacesAndNewlines)
        let wifiPassword = property.wifiPassword?.trimmingCharacters(in: .whitespacesAndNewlines)
        let utilityAccount = property.utilityAccountNumber?.trimmingCharacters(in: .whitespacesAndNewlines)

        return [
            "Здравствуйте! Добро пожаловать.",
            "",
            "Адрес объекта: \(address?.isEmpty == false ? address! : property.name)",
            "Wi-Fi: \(wifiLogin?.isEmpty == false ? wifiLogin! : "не указан")",
            "Пароль Wi-Fi: \(wifiPassword?.isEmpty == false ? wifiPassword! : "не указан")",
            "Лицевой счёт для оплаты коммунальных услуг: \(utilityAccount?.isEmpty == false ? utilityAccount! : "не указан")",
            "",
            "Если появятся вопросы по заезду, оплате или коммунальным услугам, напишите мне."
        ].joined(separator: "\n")
    }

    private var sortedLeases: [Lease] {
        leases.sorted {
            if $0.status.lowercased() == $1.status.lowercased() {
                return ($0.moveInDate ?? $0.startDate) > ($1.moveInDate ?? $1.startDate)
            }
            return $0.status.lowercased() == "active"
        }
    }

    var body: some View {
        ZStack {
            AppScreenBackground()

            content
        }
        .navigationTitle(property.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Редактировать") { showEditForm = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Добавить операцию") { showTransactionSheet = true }
            }
        }
        .task { await loadData() }
        .refreshable { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .pendingMarkPaidQueueLeaseAffected)) { note in
            guard let leaseId = note.userInfo?["leaseId"] as? String,
                  leases.contains(where: { $0.id == leaseId }) else { return }
            Task {
                await refreshSchedule(leaseID: leaseId)
                await loadTransactions()
                await MainActor.run { errorMessage = nil }
            }
        }
        .sheet(isPresented: $showTransactionSheet) {
            QuickTransactionSheet(propertyId: property.id) { await loadData() }
                .environmentObject(authManager)
        }
        .sheet(item: $editingTransaction) { transaction in
            QuickTransactionSheet(propertyId: property.id, transaction: transaction) {
                await loadData()
            }
            .environmentObject(authManager)
        }
        .sheet(isPresented: $showEditForm) {
            PropertyFormView(
                property: property,
                onSave: { await loadData() },
                onDelete: { dismiss() }
            )
            .environmentObject(authManager)
        }
        .sheet(isPresented: $showUtilityForm) {
            UtilityFormView(propertyId: property.id, utility: editingUtility) {
                await loadUtilities()
                await loadUtilitiesHistoryExtra()
                await loadUtilityReceipts()
            }
            .environmentObject(authManager)
        }
        .sheet(item: $selectedUtility) { utility in
            UtilityDetailSheet(utility: utility)
                .environmentObject(authManager)
        }
        .sheet(item: $selectedUtilityReceipt) { route in
            UtilityReceiptDetailSheet(
                receiptId: route.id,
                initialReceipt: utilityReceiptById[route.id]
            )
            .environmentObject(authManager)
        }
        .sheet(isPresented: $showMaintenanceForm) {
            MaintenanceFormSheet(propertyId: property.id, request: editingMaintenance) {
                await loadMaintenance()
            }
            .environmentObject(authManager)
        }
        .sheet(isPresented: $showLeaseForm) {
            LeaseFormSheet(propertyId: property.id, tenants: tenants) {
                await loadData()
            }
            .environmentObject(authManager)
        }
        .sheet(item: $editingLease) { lease in
            LeaseFormSheet(propertyId: property.id, tenants: tenants, lease: lease) {
                await loadData()
            }
            .environmentObject(authManager)
        }
        .sheet(item: $leaseToTerminate) { lease in
            TerminateLeaseSheet(
                lease: lease,
                tenant: tenants.first(where: { $0.id == lease.tenantId })
            ) {
                await loadData()
            }
            .environmentObject(authManager)
        }
        .sheet(item: $linkedTransaction) { route in
            TransactionDetailSheet(
                transactionId: route.id,
                propertyName: property.name,
                baseCurrency: authManager.user?.baseCurrency ?? "KZT"
            )
            .environmentObject(authManager)
        }
        .confirmationDialog(
            "Удалить операцию?",
            isPresented: Binding(
                get: { transactionToDelete != nil },
                set: { if !$0 { transactionToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let transaction = transactionToDelete {
                    Task { await deleteTransaction(transaction) }
                }
            }
            Button("Отмена", role: .cancel) {
                transactionToDelete = nil
            }
        } message: {
            Text("Операция будет удалена из журнала объекта и финансовой статистики.")
        }
        .confirmationDialog(
            "Удалить заявку на обслуживание?",
            isPresented: Binding(
                get: { maintenanceToDelete != nil },
                set: { if !$0 { maintenanceToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let request = maintenanceToDelete {
                    Task { await deleteMaintenance(request) }
                }
            }
            Button("Отмена", role: .cancel) {
                maintenanceToDelete = nil
            }
        } message: {
            Text("Заявка будет скрыта из списка обслуживания объекта.")
        }
        .confirmationDialog(
            "Удалить начисление коммуналки?",
            isPresented: Binding(
                get: { utilityToDelete != nil },
                set: { if !$0 { utilityToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let utility = utilityToDelete {
                    Task { await deleteUtility(utility) }
                }
            }
            Button("Отмена", role: .cancel) {
                utilityToDelete = nil
            }
        } message: {
            Text("Начисление будет удалено из истории коммунальных платежей объекта.")
        }
        .confirmationDialog(
            "Удалить квитанцию?",
            isPresented: Binding(
                get: { receiptToDelete != nil },
                set: { if !$0 { receiptToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let receipt = receiptToDelete {
                    Task { await deleteReceipt(receipt) }
                }
            }
            Button("Отмена", role: .cancel) {
                receiptToDelete = nil
            }
        } message: {
            Text("Распознанная квитанция будет удалена. Подтверждённые квитанции удалить нельзя — удалите материализованные начисления.")
        }
        .sheet(item: $scheduleForMarkPaidSheet) { schedule in
            MarkSchedulePaidSheet(schedule: schedule) {
                await refreshSchedule(leaseID: schedule.leaseId)
                await loadTransactions()
                await MainActor.run { errorMessage = nil }
            }
            .environmentObject(authManager)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, transactions.isEmpty, leases.isEmpty, utilitiesForDisplay.isEmpty, maintenanceRequests.isEmpty {
            EmptyStateView(
                title: "Не удалось загрузить активность объекта",
                message: errorMessage,
                actionName: "Повторить",
                action: { Task { await loadData() } },
                icon: "wifi.exclamationmark"
            )
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    heroSection

                    if let errorMessage {
                        statusBanner(errorMessage, color: AppTheme.Colors.warning)
                    }
                    if let welcomeCopyMessage {
                        statusBanner(welcomeCopyMessage, color: AppTheme.Colors.success)
                    }

                    factsSection

                    PropertyFilesSection(propertyId: property.id)
                        .environmentObject(authManager)

                    transactionsSection
                    tenantsSection
                    utilitiesSection
                    maintenanceSection
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
    }

    private var heroSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(propertyTypeLabel(property.propertyType))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .foregroundStyle(AppTheme.Colors.textSecondary)

                        Text(property.name)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        if let addr = property.displayAddress {
                            Label(addr, systemImage: "mappin.and.ellipse")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        } else {
                            Text("Адрес объекта пока не указан.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }

                    Spacer()

                    StatusBadge(status: property.status)
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    metricCard(
                        title: "Оценка",
                        value: AppFormatting.currency(
                            property.currentValue ?? property.purchasePrice ?? 0,
                            currency: property.currentValueCurrency ?? property.purchaseCurrency ?? "KZT"
                        ),
                        fallback: property.currentValue == nil && property.purchasePrice == nil
                    )
                    metricCard(
                        title: "Комнаты",
                        value: property.rooms.map(String.init) ?? "N/A",
                        fallback: property.rooms == nil
                    )
                    metricCard(
                        title: "Площадь",
                        value: property.areaSqm.map { "\(Int($0.rounded())) m²" } ?? "N/A",
                        fallback: property.areaSqm == nil
                    )
                }
            }
        }
    }

    private var factsSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Детали объекта")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                VStack(spacing: AppTheme.Spacing.sm) {
                    detailRow("Дата покупки", value: AppFormatting.dateString(from: property.purchaseDate) ?? "Не указано")
                    detailRow("Цена покупки", value: purchasePriceText)
                    detailRow("Район", value: property.district ?? "Не указано")
                    detailRow("Этаж", value: property.floor.map { "Этаж \($0)" } ?? "Не указано")
                    if let acc = property.utilityAccountNumber, !acc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailRow("Лицевой счёт (ЖКХ)", value: acc)
                    }
                    if let login = property.wifiLogin, !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailRow("Wi-Fi", value: login)
                    }
                    if let password = property.wifiPassword, !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailRow("Пароль Wi-Fi", value: password)
                    }
                    detailRow("Заметки", value: property.notes ?? "Заметок по объекту пока нет")
                }

                Button {
                    copyTenantWelcomeText()
                } label: {
                    Label("Скопировать памятку арендатору", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var transactionsSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                sectionHeader(
                    title: "Операции",
                    subtitle: "Последнее движение денег по объекту."
                )

                if transactions.isEmpty {
                    sectionPlaceholder(
                        title: "Операций пока нет",
                        message: "Добавьте первый доход или расход, чтобы журнал объекта стал полезным на мобильном.",
                        icon: "banknote"
                    )
                } else {
                    ForEach(transactions.prefix(10)) { transaction in
                        TransactionRow(
                            transaction: transaction,
                            baseCurrency: authManager.user?.baseCurrency ?? "KZT",
                            onEdit: { editingTransaction = transaction },
                            onDelete: { transactionToDelete = transaction }
                        )
                    }
                }
            }
        }
    }

    private var tenantsSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    sectionHeader(
                        title: "Арендаторы",
                        subtitle: "Аренда, график платежей и контакты в одном месте."
                    )

                    Spacer()

                    Button {
                        showLeaseForm = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.headline)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.Colors.accent)
                    .accessibilityLabel("Заселить арендатора")
                }

                if leases.isEmpty {
                    sectionPlaceholder(
                        title: "Арендаторы пока не привязаны",
                        message: "Заселите арендатора, чтобы отслеживать условия аренды, окно оплаты и график платежей.",
                        icon: "person.2"
                    )
                } else {
                    ForEach(sortedLeases) { lease in
                        let tenant = tenants.first(where: { $0.id == lease.tenantId })

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(tenant?.displayName ?? "Неизвестный арендатор")
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.Colors.textPrimary)

                                    if let email = tenant?.email, !email.isEmpty {
                                        Label(email, systemImage: "envelope")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.Colors.textSecondary)
                                    } else if let phone = tenant?.phone, !phone.isEmpty {
                                        Label(phone, systemImage: "phone")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.Colors.textSecondary)
                                    } else {
                                        Text("Контакты не указаны")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.Colors.textSecondary)
                                    }

                                    if let cohabitants = tenant?.cohabitants, !cohabitants.isEmpty {
                                        Label(cohabitants, systemImage: "person.2")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.Colors.textSecondary)
                                    }
                                }

                                Spacer()

                                StatusBadge(status: lease.status)
                            }

                            if isLeaseEarlyMoveOut(lease) {
                                Label("Выехал раньше срока", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.warning)
                            }

                            HStack(spacing: AppTheme.Spacing.sm) {
                                metricCard(
                                    title: "Аренда",
                                    value: AppFormatting.currency(lease.rentAmount, currency: lease.rentCurrency)
                                )
                                metricCard(
                                    title: "Заезд",
                                    value: AppFormatting.dateString(from: lease.moveInDate ?? lease.startDate) ?? lease.startDate
                                )
                                metricCard(
                                    title: "Окно оплаты",
                                    value: leasePaymentWindow(lease)
                                )
                            }

                            HStack(spacing: AppTheme.Spacing.sm) {
                                leaseActionButton(
                                    title: "Изменить",
                                    icon: "pencil",
                                    color: AppTheme.Colors.accent
                                ) {
                                    editingLease = lease
                                }

                                if lease.status.lowercased() == "active" {
                                    leaseActionButton(
                                        title: leaseSchedulesByLeaseId[lease.id]?.isEmpty == false ? "Обновить график" : "Создать график",
                                        icon: generatingScheduleLeaseId == lease.id ? "arrow.triangle.2.circlepath" : "calendar.badge.plus",
                                        color: AppTheme.Colors.info
                                    ) {
                                        Task { await generateSchedule(for: lease) }
                                    }
                                    .disabled(generatingScheduleLeaseId != nil)

                                    leaseActionButton(
                                        title: "Прекратить",
                                        icon: "power",
                                        color: AppTheme.Colors.danger
                                    ) {
                                        leaseToTerminate = lease
                                    }
                                }
                            }

                            if let scheduleRows = leaseSchedulesByLeaseId[lease.id], !scheduleRows.isEmpty {
                                leaseScheduleSection(rows: scheduleRows)
                            } else if lease.status.lowercased() == "active" {
                                Text("График аренды ещё не загружен или не создан. Его можно сформировать здесь.")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .padding(.top, 4)
                            }

                            EntityFilesSection(
                                entityType: "lease",
                                entityId: lease.id,
                                title: "Файлы договора аренды",
                                isEmbedded: true,
                                fileTypes: [
                                    EntityFileType(value: "lease_agreement", label: "Договор"),
                                    EntityFileType(value: "document", label: "Документ"),
                                    EntityFileType(value: "receipt", label: "Квитанция")
                                ]
                            )
                            .environmentObject(authManager)

                            if let terminatedAt = lease.terminatedAt {
                                Text("Прекращено \(AppFormatting.dateString(from: terminatedAt) ?? terminatedAt)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.warning)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var utilitiesSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    sectionHeader(
                        title: "Коммуналка",
                        subtitle: "Ежемесячные коммунальные расходы и квитанции по объекту."
                    )

                    Spacer()

                    Button {
                        editingUtility = nil
                        showUtilityForm = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.Colors.accent)
                    .accessibilityLabel("Добавить коммуналку")
                }

                if utilitiesForDisplay.isEmpty && utilityReceiptsForDisplay.isEmpty {
                    sectionPlaceholder(
                        title: "Коммуналка пока не добавлена",
                        message: "Добавляйте ежемесячную коммуналку здесь; для старых периодов данные подтягиваются из истории портфеля (до 36 мес.).",
                        icon: "receipt"
                    )
                } else {
                    if !utilitiesForDisplay.isEmpty {
                        ForEach(utilitiesForDisplay.prefix(36)) { utility in
                            utilityListRow(utility)
                        }
                    }

                    if !utilityReceiptsForDisplay.isEmpty {
                        utilityReceiptsHistorySection(Array(utilityReceiptsForDisplay.prefix(8)))
                    }
                }
            }
        }
    }

    private var maintenanceSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    sectionHeader(
                        title: "Обслуживание",
                        subtitle: "Ремонты, подрядчики и заявки по объекту."
                    )

                    Spacer()

                    Button {
                        editingMaintenance = nil
                        showMaintenanceForm = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.Colors.accent)
                    .accessibilityLabel("Добавить заявку на обслуживание")
                }

                if maintenanceRequests.isEmpty {
                    sectionPlaceholder(
                        title: "Заявок на обслуживание пока нет",
                        message: "Создавайте здесь ремонты, плановые работы и обращения к подрядчикам по объекту.",
                        icon: "wrench.and.screwdriver"
                    )
                } else {
                    ForEach(maintenanceRequests) { request in
                        maintenanceRow(request)
                    }
                }
            }
        }
    }

    private func maintenanceRow(_ request: MaintenanceRequest) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(MaintenanceDisplay.categoryLabel(request.category))
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    Text(request.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(2)

                    if let description = request.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    maintenanceStatusPill(request.status)
                    maintenancePriorityPill(request.priority)

                    if let scheduled = request.scheduledDate,
                       let formatted = AppFormatting.dateString(from: scheduled) {
                        Text(formatted)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                Menu {
                    ForEach(MaintenanceDisplay.statuses, id: \.self) { status in
                        Button(MaintenanceDisplay.statusLabel(status)) {
                            Task { await updateMaintenance(request, status: status) }
                        }
                    }
                } label: {
                    Label("Статус", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(AppTheme.Colors.info.opacity(0.12))
                        .foregroundStyle(AppTheme.Colors.info)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(updatingMaintenanceId == request.id)

                utilityActionButton(
                    title: "Изменить",
                    icon: "pencil",
                    color: AppTheme.Colors.textSecondary
                ) {
                    editingMaintenance = request
                    showMaintenanceForm = true
                }

                utilityActionButton(
                    title: "Удалить",
                    icon: "trash",
                    color: AppTheme.Colors.danger
                ) {
                    maintenanceToDelete = request
                }
            }

            if updatingMaintenanceId == request.id {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func maintenanceStatusPill(_ status: String) -> some View {
        Text(MaintenanceDisplay.statusLabel(status))
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(MaintenanceDisplay.statusColor(status).opacity(0.14))
            .foregroundStyle(MaintenanceDisplay.statusColor(status))
            .clipShape(Capsule())
    }

    private func maintenancePriorityPill(_ priority: String) -> some View {
        Text(MaintenanceDisplay.priorityLabel(priority))
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(MaintenanceDisplay.priorityColor(priority).opacity(0.12))
            .foregroundStyle(MaintenanceDisplay.priorityColor(priority))
            .clipShape(Capsule())
    }

    private func utilityListRow(_ utility: PropertyUtility) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Button {
                selectedUtility = utility
            } label: {
                utilityRow(utility)
            }
            .buttonStyle(.plain)

            HStack(spacing: AppTheme.Spacing.sm) {
                utilityActionButton(
                    title: "Детали",
                    icon: "info.circle",
                    color: AppTheme.Colors.accent
                ) {
                    selectedUtility = utility
                }

                utilityActionButton(
                    title: "Изменить",
                    icon: "pencil",
                    color: AppTheme.Colors.textSecondary
                ) {
                    editingUtility = utility
                    showUtilityForm = true
                }

                if let receiptId = utility.sourceReceiptId?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !receiptId.isEmpty {
                    utilityActionButton(
                        title: "Квитанция",
                        icon: "doc.text.magnifyingglass",
                        color: AppTheme.Colors.info
                    ) {
                        selectedUtilityReceipt = UtilityReceiptRoute(id: receiptId)
                    }
                }

                utilityActionButton(
                    title: "Удалить",
                    icon: "trash",
                    color: AppTheme.Colors.danger
                ) {
                    utilityToDelete = utility
                }
            }
        }
    }

    private func utilityActionButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .background(color.opacity(0.12))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func utilityReceiptsHistorySection(_ receipts: [UtilityReceiptPayload]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Divider()
                .padding(.vertical, AppTheme.Spacing.xs)

            HStack(alignment: .firstTextBaseline) {
                Text("Распознанные квитанции")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Spacer()

                Text("\(utilityReceiptsForDisplay.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
            }

            ForEach(receipts, id: \.id) { receipt in
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Button {
                        selectedUtilityReceipt = UtilityReceiptRoute(id: receipt.id)
                    } label: {
                        utilityReceiptRow(receipt)
                    }
                    .buttonStyle(.plain)

                    if receipt.status.lowercased() != "confirmed" {
                        utilityActionButton(
                            title: "Удалить квитанцию",
                            icon: "trash",
                            color: AppTheme.Colors.danger
                        ) {
                            receiptToDelete = receipt
                        }
                    }
                }
            }

            if utilityReceiptsForDisplay.count > receipts.count {
                Text("Еще квитанций: \(utilityReceiptsForDisplay.count - receipts.count).")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .padding(.top, AppTheme.Spacing.sm)
    }

    private func utilityReceiptRow(_ receipt: UtilityReceiptPayload) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(UtilityReceiptDisplay.receiptPeriodLabel(receipt))
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(receipt.provider?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? receipt.provider! : "Поставщик не распознан")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)

                if let account = receipt.accountNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !account.isEmpty {
                    Text("Л/с \(account)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(receipt.totalAmount.map { AppFormatting.compactAmount($0, currency: receipt.currency ?? "KZT") } ?? "Сумма не распознана")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                StatusBadge(status: UtilityReceiptDisplay.receiptStatusLabel(receipt.status))

                if let paymentDate = receipt.paymentDate,
                   let formatted = AppFormatting.dateString(from: paymentDate) {
                    Text(formatted)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func leaseScheduleSection(rows: [LeasePaymentSchedule]) -> some View {
        let sorted = rows.sorted { $0.dueDate < $1.dueDate }
        let capped = Array(sorted.prefix(24))
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("График платежей")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            ForEach(capped) { row in
                leaseScheduleRow(row)
            }
        }
        .padding(.top, AppTheme.Spacing.sm)
    }

    private func leaseScheduleRow(_ row: LeasePaymentSchedule) -> some View {
        let canMark = scheduleRowCanMarkPaid(row)

        return HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppFormatting.dateString(from: row.dueDate) ?? row.dueDate)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                if row.isOverdue {
                    Text("Просрочено на \(row.daysOverdue) дн.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.warning)
                } else if let paidAt = row.paidAt, !paidAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Оплачено \(AppFormatting.dateString(from: paidAt) ?? paidAt)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.success)
                }
            }
            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(AppFormatting.compactAmount(row.expectedAmount, currency: row.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                StatusBadge(status: row.status)
            }

            if let transactionId = row.transactionId, !transactionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    linkedTransaction = LinkedTransactionRoute(id: transactionId)
                } label: {
                    Image(systemName: "receipt")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.Colors.accent)
                .accessibilityLabel("Открыть связанную операцию")
            } else if canMark {
                Button {
                    scheduleForMarkPaidSheet = row
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.Colors.success)
                .accessibilityLabel("Отметить платёж оплаченным")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func leaseActionButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(color.opacity(0.12))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func metricCard(title: String, value: String, fallback: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(fallback ? AppTheme.Colors.textSecondary : AppTheme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    private func sectionPlaceholder(title: String, message: String, icon: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 36, height: 36)
                .background(AppTheme.Colors.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(2)
            }

            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private func utilityRow(_ utility: PropertyUtility) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(utilityPeriodLabel(utility))
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(utilityTypeLabel(utility.utilityType))
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(utility.provider?.isEmpty == false ? utility.provider! : "Поставщик не указан")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                if utility.sourceReceiptId?.isEmpty == false {
                    Label("Из распознанной квитанции", systemImage: "doc.text.magnifyingglass")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.info)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(AppFormatting.compactAmount(utility.amount, currency: utility.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                StatusBadge(status: utility.status)

                if let due = utility.dueDate {
                    Text("Срок: \(AppFormatting.dateString(from: due) ?? due)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadTransactions() }
            group.addTask { await loadLeases() }
            group.addTask { await loadUtilities() }
            group.addTask { await loadUtilityReceipts() }
            group.addTask { await loadMaintenance() }
        }

        await loadTenants()
        await loadLeaseSchedules()
        await loadUtilitiesHistoryExtra()
        await loadPurchaseUSDEquivalent()
    }

    private func loadPurchaseUSDEquivalent() async {
        guard let amount = property.purchasePrice, amount > 0 else {
            purchaseUSDEquivalent = nil
            return
        }

        let base = (property.purchaseCurrency ?? "KZT").uppercased()
        var path = "/v1/exchange-rates/convert?amount=\(amount)&base=\(base)&target=USD"
        if let date = property.purchaseDate, !date.isEmpty {
            path += "&date=\(date)"
        }

        do {
            let data = try await APIClient.shared.requestData(
                path,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let decoded = try JSONDecoder().decode(APIResponse<ExchangeRateConversionDTO>.self, from: data)
            purchaseUSDEquivalent = decoded.data
        } catch {
            purchaseUSDEquivalent = nil
        }
    }

    private func loadLeaseSchedules() async {
        for lease in leases {
            await refreshSchedule(leaseID: lease.id)
        }
    }

    private func refreshSchedule(leaseID: String) async {
        var next = leaseSchedulesByLeaseId
        do {
            let data = try await APIClient.shared.requestData(
                "/v1/leases/\(leaseID)/payment-schedule",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let env = try JSONDecoder().decode(APIListEnvelope<LeasePaymentSchedule>.self, from: data)
            if env.data.isEmpty {
                next.removeValue(forKey: leaseID)
            } else {
                next[leaseID] = env.data
            }
        } catch {
            // сохраняем предыдущие строки графика при сетевой ошибке
        }
        leaseSchedulesByLeaseId = next
    }

    private func generateSchedule(for lease: Lease) async {
        guard generatingScheduleLeaseId == nil else { return }
        generatingScheduleLeaseId = lease.id
        errorMessage = nil
        defer { generatingScheduleLeaseId = nil }

        do {
            let data = try await APIClient.shared.requestData(
                "/v1/leases/\(lease.id)/generate-schedule",
                method: "POST",
                body: GenerateScheduleBody(),
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let env = try JSONDecoder().decode(APIListEnvelope<LeasePaymentSchedule>.self, from: data)
            if env.data.isEmpty {
                leaseSchedulesByLeaseId.removeValue(forKey: lease.id)
            } else {
                leaseSchedulesByLeaseId[lease.id] = env.data
            }
            await loadTransactions()
        } catch {
            errorMessage = "Не удалось сформировать график аренды. Потяните для обновления и попробуйте еще раз."
        }
    }

    private func scheduleRowCanMarkPaid(_ row: LeasePaymentSchedule) -> Bool {
        if row.actualPaymentId != nil {
            return false
        }
        switch row.status.lowercased() {
        case "paid", "matched", "skipped":
            return false
        default:
            return true
        }
    }

    private func loadUtilitiesHistoryExtra() async {
        do {
            let data = try await APIClient.shared.requestData(
                "/v1/analytics/utilities-history?months=36",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let env = try JSONDecoder().decode(APIListEnvelope<PropertyUtility>.self, from: data)
            utilitiesHistoryExtra = env.data.filter { $0.propertyId == property.id }
        } catch {
            utilitiesHistoryExtra = []
        }
    }

    private func loadUtilityReceipts() async {
        do {
            let data = try await APIClient.shared.requestData(
                "/v1/properties/\(property.id)/utility-receipts?per_page=100",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let env = try JSONDecoder().decode(APIListEnvelope<UtilityReceiptPayload>.self, from: data)
            utilityReceipts = env.data
        } catch {
            utilityReceipts = []
        }
    }

    private func loadMaintenance() async {
        do {
            let data = try await APIClient.shared.requestData(
                "/v1/properties/\(property.id)/maintenance",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let env = try JSONDecoder().decode(APIListEnvelope<MaintenanceRequest>.self, from: data)
            maintenanceRequests = env.data
        } catch {
            maintenanceRequests = []
        }
    }

    private func updateMaintenance(_ request: MaintenanceRequest, status: String? = nil, priority: String? = nil) async {
        guard updatingMaintenanceId == nil else { return }
        updatingMaintenanceId = request.id
        errorMessage = nil
        defer { updatingMaintenanceId = nil }

        let body = MaintenanceInput(
            request: request,
            status: status ?? request.status,
            priority: priority ?? request.priority
        )

        do {
            _ = try await APIClient.shared.requestData(
                "/v1/maintenance/\(request.id)",
                method: "PUT",
                body: body,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            AppHaptics.success()
            await loadMaintenance()
        } catch {
            AppHaptics.warning()
            errorMessage = "Не удалось обновить заявку на обслуживание."
        }
    }

    private func deleteMaintenance(_ request: MaintenanceRequest) async {
        do {
            _ = try await APIClient.shared.requestData(
                "/v1/maintenance/\(request.id)",
                method: "DELETE",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            maintenanceToDelete = nil
            AppHaptics.success()
            await loadMaintenance()
        } catch {
            AppHaptics.warning()
            errorMessage = "Не удалось удалить заявку на обслуживание."
        }
    }

    private func loadTransactions() async {
        do {
            let data = try await APIClient.shared.requestData(
                "/v1/properties/\(property.id)/transactions",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let decoded = try JSONDecoder().decode(APIResponse<[Transaction]>.self, from: data)
            transactions = decoded.data
        } catch {
            transactions = []
            errorMessage = "Часть активности объекта не загрузилась. Потяните для обновления и попробуйте еще раз."
        }
    }

    private func deleteTransaction(_ transaction: Transaction) async {
        do {
            _ = try await APIClient.shared.requestData(
                "/v1/transactions/\(transaction.id)",
                method: "DELETE",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            transactionToDelete = nil
            await loadData()
        } catch {
            errorMessage = "Не удалось удалить операцию. Потяните для обновления и попробуйте еще раз."
        }
    }

    private func deleteUtility(_ utility: PropertyUtility) async {
        do {
            _ = try await APIClient.shared.requestData(
                "/v1/utilities/\(utility.id)",
                method: "DELETE",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            utilityToDelete = nil
            AppHaptics.success()
            await loadUtilities()
            await loadUtilitiesHistoryExtra()
            await loadUtilityReceipts()
        } catch {
            AppHaptics.warning()
            errorMessage = "Не удалось удалить начисление коммуналки."
        }
    }

    private func deleteReceipt(_ receipt: UtilityReceiptPayload) async {
        do {
            _ = try await APIClient.shared.requestData(
                "/v1/utility-receipts/\(receipt.id)",
                method: "DELETE",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            receiptToDelete = nil
            AppHaptics.success()
            await loadUtilityReceipts()
        } catch {
            AppHaptics.warning()
            errorMessage = "Не удалось удалить квитанцию. Подтверждённые квитанции удалить нельзя."
        }
    }

    private func copyTenantWelcomeText() {
        UIPasteboard.general.string = tenantWelcomeText
        welcomeCopyMessage = "Памятка для арендатора скопирована."
    }

    private func loadLeases() async {
        do {
            let data = try await APIClient.shared.requestData(
                "/v1/properties/\(property.id)/leases",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let decoded = try JSONDecoder().decode(APIResponse<[Lease]>.self, from: data)
            leases = decoded.data
        } catch {
            leases = []
            errorMessage = "Часть активности объекта не загрузилась. Потяните для обновления и попробуйте еще раз."
        }
    }

    private func loadTenants() async {
        do {
            let data = try await APIClient.shared.requestData(
                "/v1/tenants?per_page=100",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let decoded = try JSONDecoder().decode(APIResponse<[Tenant]>.self, from: data)
            tenants = decoded.data
        } catch {
            tenants = []
            errorMessage = "Контакты арендатора не загрузились. Потяните для обновления и попробуйте еще раз."
        }
    }

    private func loadUtilities() async {
        do {
            let data = try await APIClient.shared.requestData(
                "/v1/properties/\(property.id)/utilities?per_page=60",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let decoded = try JSONDecoder().decode(APIListEnvelope<PropertyUtility>.self, from: data)
            utilities = decoded.data.sorted {
                if $0.periodYear == $1.periodYear {
                    return $0.periodMonth > $1.periodMonth
                }
                return $0.periodYear > $1.periodYear
            }
        } catch {
            utilities = []
            errorMessage = "История коммуналки не загрузилась. Потяните для обновления и попробуйте еще раз."
        }
    }

    private func leasePaymentWindow(_ lease: Lease) -> String {
        let start = lease.paymentWindowStartDay ?? lease.paymentDay ?? 1
        let end = lease.paymentWindowEndDay ?? lease.paymentDueDay ?? lease.paymentDay ?? start
        return "\(start)-\(end)"
    }

    private func isLeaseEarlyMoveOut(_ lease: Lease) -> Bool {
        if lease.terminationReason?.trimmingCharacters(in: .whitespacesAndNewlines) == "Выехал раньше срока" {
            return true
        }
        guard let terminatedAt = lease.terminatedAt,
              let endDate = lease.endDate else {
            return false
        }
        return terminatedAt < endDate
    }

    private func utilityPeriodLabel(_ utility: PropertyUtility) -> String {
        UtilityReceiptDisplay.utilityPeriodLabel(year: utility.periodYear, month: utility.periodMonth)
    }

    private func utilityTypeLabel(_ value: String) -> String {
        UtilityReceiptDisplay.utilityTypeLabel(value)
    }

    private func propertyTypeLabel(_ value: String) -> String {
        switch value {
        case "apartment": return "Квартира"
        case "house": return "Дом"
        case "commercial": return "Коммерция"
        case "land": return "Земля"
        case "other": return "Другое"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct GenerateScheduleBody: Encodable {}

private struct LinkedTransactionRoute: Identifiable {
    let id: String
}

private struct UtilityReceiptRoute: Identifiable {
    let id: String
}

private struct MaintenanceRequest: Identifiable, Codable {
    let id: String
    let propertyId: String
    let tenantId: String?
    let title: String
    let description: String?
    let category: String
    let priority: String
    let status: String
    let contractorName: String?
    let contractorPhone: String?
    let estimatedCost: Double?
    let actualCost: Double?
    let currency: String
    let scheduledDate: String?
    let completedAt: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, priority, status, currency
        case propertyId = "property_id"
        case tenantId = "tenant_id"
        case contractorName = "contractor_name"
        case contractorPhone = "contractor_phone"
        case estimatedCost = "estimated_cost"
        case actualCost = "actual_cost"
        case scheduledDate = "scheduled_date"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct MaintenanceInput: Encodable {
    let propertyId: String
    let tenantId: String?
    let title: String
    let description: String?
    let category: String
    let priority: String
    let status: String
    let contractorName: String?
    let contractorPhone: String?
    let estimatedCost: Double?
    let actualCost: Double?
    let currency: String
    let scheduledDate: String?
    let completedAt: String?

    init(
        propertyId: String,
        tenantId: String? = nil,
        title: String,
        description: String?,
        category: String,
        priority: String,
        status: String,
        contractorName: String?,
        contractorPhone: String?,
        estimatedCost: Double?,
        actualCost: Double?,
        currency: String,
        scheduledDate: String?,
        completedAt: String?
    ) {
        self.propertyId = propertyId
        self.tenantId = tenantId
        self.title = title
        self.description = description
        self.category = category
        self.priority = priority
        self.status = status
        self.contractorName = contractorName
        self.contractorPhone = contractorPhone
        self.estimatedCost = estimatedCost
        self.actualCost = actualCost
        self.currency = currency
        self.scheduledDate = scheduledDate
        self.completedAt = completedAt
    }

    init(request: MaintenanceRequest, status: String, priority: String) {
        self.init(
            propertyId: request.propertyId,
            tenantId: request.tenantId,
            title: request.title,
            description: request.description,
            category: request.category,
            priority: priority,
            status: status,
            contractorName: request.contractorName,
            contractorPhone: request.contractorPhone,
            estimatedCost: request.estimatedCost,
            actualCost: request.actualCost,
            currency: request.currency,
            scheduledDate: request.scheduledDate,
            completedAt: request.completedAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case title, description, category, priority, status, currency
        case propertyId = "property_id"
        case tenantId = "tenant_id"
        case contractorName = "contractor_name"
        case contractorPhone = "contractor_phone"
        case estimatedCost = "estimated_cost"
        case actualCost = "actual_cost"
        case scheduledDate = "scheduled_date"
        case completedAt = "completed_at"
    }
}

private enum MaintenanceDisplay {
    static let categories = ["plumbing", "electrical", "hvac", "general", "appliance", "other"]
    static let priorities = ["low", "medium", "high", "urgent"]
    static let statuses = ["requested", "scheduled", "in_progress", "completed", "cancelled"]

    static func categoryLabel(_ value: String) -> String {
        switch value {
        case "plumbing": return "Сантехника"
        case "electrical": return "Электрика"
        case "hvac": return "Климат"
        case "general": return "Общее"
        case "appliance": return "Техника"
        case "other": return "Другое"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func priorityLabel(_ value: String) -> String {
        switch value {
        case "low": return "Низкий"
        case "medium": return "Средний"
        case "high": return "Высокий"
        case "urgent": return "Срочно"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func statusLabel(_ value: String) -> String {
        switch value {
        case "requested": return "Запрошено"
        case "scheduled": return "Запланировано"
        case "in_progress": return "В работе"
        case "completed": return "Завершено"
        case "cancelled": return "Отменено"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func statusColor(_ value: String) -> Color {
        switch value {
        case "completed":
            return AppTheme.Colors.success
        case "cancelled":
            return AppTheme.Colors.danger
        case "scheduled", "in_progress":
            return AppTheme.Colors.info
        default:
            return AppTheme.Colors.warning
        }
    }

    static func priorityColor(_ value: String) -> Color {
        switch value {
        case "urgent", "high":
            return AppTheme.Colors.danger
        case "medium":
            return AppTheme.Colors.warning
        default:
            return AppTheme.Colors.textSecondary
        }
    }

    static func decimalText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct MaintenanceFormSheet: View {
    let propertyId: String
    var request: MaintenanceRequest?
    var onSave: () async -> Void

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var category = "plumbing"
    @State private var priority = "medium"
    @State private var status = "requested"
    @State private var contractorName = ""
    @State private var contractorPhone = ""
    @State private var estimatedCost = ""
    @State private var actualCost = ""
    @State private var currency = "USD"
    @State private var scheduledDate = Date()
    @State private var hasScheduledDate = false
    @State private var completedAt = Date()
    @State private var hasCompletedAt = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Заявка") {
                    AppTextField(title: "Название", text: $title, placeholder: "Что нужно сделать?")
                    Picker("Категория", selection: $category) {
                        ForEach(MaintenanceDisplay.categories, id: \.self) { value in
                            Text(MaintenanceDisplay.categoryLabel(value)).tag(value)
                        }
                    }
                    AppTextField(title: "Описание", text: $descriptionText, placeholder: "Детали работ")
                }

                Section("Статус") {
                    Picker("Статус", selection: $status) {
                        ForEach(MaintenanceDisplay.statuses, id: \.self) { value in
                            Text(MaintenanceDisplay.statusLabel(value)).tag(value)
                        }
                    }
                    Picker("Приоритет", selection: $priority) {
                        ForEach(MaintenanceDisplay.priorities, id: \.self) { value in
                            Text(MaintenanceDisplay.priorityLabel(value)).tag(value)
                        }
                    }
                }

                Section("Подрядчик") {
                    AppTextField(title: "Имя", text: $contractorName, placeholder: "Компания или мастер")
                    AppTextField(
                        title: "Телефон",
                        text: $contractorPhone,
                        placeholder: "+7",
                        keyboardType: .phonePad
                    )
                }

                Section("Стоимость") {
                    AppTextField(
                        title: "План",
                        text: $estimatedCost,
                        placeholder: "0",
                        keyboardType: .decimalPad,
                        autocapitalization: .never
                    )
                    AppTextField(
                        title: "Факт",
                        text: $actualCost,
                        placeholder: "0",
                        keyboardType: .decimalPad,
                        autocapitalization: .never
                    )
                    AppTextField(
                        title: "Валюта",
                        text: $currency,
                        placeholder: "USD",
                        autocapitalization: .characters
                    )
                }

                Section("Даты") {
                    Toggle("Запланировать дату", isOn: $hasScheduledDate)
                    if hasScheduledDate {
                        DatePicker("Дата работ", selection: $scheduledDate, displayedComponents: .date)
                    }
                    Toggle("Указать завершение", isOn: $hasCompletedAt)
                    if hasCompletedAt {
                        DatePicker("Завершено", selection: $completedAt, displayedComponents: .date)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }
            }
            .navigationTitle(request == nil ? "Новая заявка" : "Редактировать заявку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled(!canSave || isLoading)
                }
            }
            .onAppear { populateFromRequest() }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            optionalAmountIsValid(estimatedCost) &&
            optionalAmountIsValid(actualCost)
    }

    private func populateFromRequest() {
        guard let request else { return }
        title = request.title
        descriptionText = request.description ?? ""
        category = MaintenanceDisplay.categories.contains(request.category) ? request.category : "other"
        priority = MaintenanceDisplay.priorities.contains(request.priority) ? request.priority : "medium"
        status = MaintenanceDisplay.statuses.contains(request.status) ? request.status : "requested"
        contractorName = request.contractorName ?? ""
        contractorPhone = request.contractorPhone ?? ""
        estimatedCost = request.estimatedCost.map { MaintenanceDisplay.decimalText($0) } ?? ""
        actualCost = request.actualCost.map { MaintenanceDisplay.decimalText($0) } ?? ""
        currency = request.currency
        if let scheduled = request.scheduledDate, let parsed = AppFormatting.parsedDate(from: scheduled) {
            scheduledDate = parsed
            hasScheduledDate = true
        }
        if let completed = request.completedAt, let parsed = AppFormatting.parsedDate(from: completed) {
            completedAt = parsed
            hasCompletedAt = true
        }
    }

    private func save() async {
        guard canSave else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let body = MaintenanceInput(
            propertyId: propertyId,
            tenantId: request?.tenantId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            category: category,
            priority: priority,
            status: status,
            contractorName: contractorName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            contractorPhone: contractorPhone.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            estimatedCost: parsedOptionalAmount(estimatedCost),
            actualCost: parsedOptionalAmount(actualCost),
            currency: currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().nilIfBlank ?? "USD",
            scheduledDate: hasScheduledDate ? dateString(scheduledDate) : nil,
            completedAt: hasCompletedAt ? dateString(completedAt) : nil
        )

        do {
            if let request {
                _ = try await APIClient.shared.requestData(
                    "/v1/maintenance/\(request.id)",
                    method: "PUT",
                    body: body,
                    tokenProvider: { await MainActor.run { authManager.accessToken } },
                    refreshAndRetry: { await authManager.refreshToken() }
                )
            } else {
                _ = try await APIClient.shared.requestData(
                    "/v1/maintenance",
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
            errorMessage = "Не удалось сохранить заявку на обслуживание."
        }
    }

    private func optionalAmountIsValid(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedOptionalAmount(raw) != nil
    }

    private func parsedOptionalAmount(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private enum UtilityReceiptDisplay {
    static func utilityTypeLabel(_ value: String) -> String {
        switch value {
        case "utilities": return "Коммунальные услуги"
        case "electricity": return "Электричество"
        case "cold_water": return "Холодная вода"
        case "hot_water": return "Горячая вода"
        case "water": return "Вода"
        case "water_disposal": return "Водоотведение"
        case "gas": return "Газ"
        case "heating": return "Отопление"
        case "common_area": return "МОП"
        case "waste": return "Вывоз отходов"
        case "elevator": return "Лифт"
        case "intercom": return "Домофон"
        case "internet": return "Интернет"
        case "tv": return "ТВ"
        case "capital_repair": return "Капремонт"
        case "maintenance": return "Обслуживание"
        case "other": return "Другое"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func utilityPeriodLabel(year: Int, month: Int) -> String {
        monthYearLabel(year: year, month: month) ?? "\(month)/\(year)"
    }

    static func receiptPeriodLabel(_ receipt: UtilityReceiptPayload) -> String {
        if let year = receipt.periodYear, let month = receipt.periodMonth,
           let label = monthYearLabel(year: year, month: month) {
            return label
        }
        if let paymentDate = receipt.paymentDate,
           let formatted = AppFormatting.dateString(from: paymentDate, dateStyle: .long) {
            return formatted
        }
        return "Период не распознан"
    }

    static func receiptStatusLabel(_ status: String) -> String {
        switch status {
        case "queued": return "В очереди"
        case "processing": return "Распознается"
        case "parsed": return "Распознана"
        case "confirmed": return "Сохранена"
        case "failed": return "Ошибка"
        default: return status
        }
    }

    static func receiptPeriodSortKey(_ receipt: UtilityReceiptPayload) -> String {
        let year = receipt.periodYear ?? 0
        let month = receipt.periodMonth ?? 0
        return "\(year)-\(String(format: "%02d", month))"
    }

    static func receiptDateSortKey(_ receipt: UtilityReceiptPayload) -> String {
        receipt.paymentDate ?? receipt.confirmedAt ?? receipt.createdAt ?? receipt.updatedAt ?? ""
    }

    static func decimalText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func monthYearLabel(year: Int, month: Int) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "MMMM yyyy"
        let components = DateComponents(year: year, month: month, day: 1)
        guard let date = Calendar.current.date(from: components) else { return nil }
        return formatter.string(from: date)
    }
}

private struct UtilityDetailSheet: View {
    let utility: PropertyUtility

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(UtilityReceiptDisplay.utilityPeriodLabel(year: utility.periodYear, month: utility.periodMonth))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)

                                    Text(UtilityReceiptDisplay.utilityTypeLabel(utility.utilityType))
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                }

                                Spacer()

                                StatusBadge(status: utility.status)
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.sm) {
                                detailCell(
                                    title: "Сумма",
                                    value: AppFormatting.compactAmount(utility.amount, currency: utility.currency)
                                )
                                detailCell(
                                    title: "Поставщик",
                                    value: utility.provider?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? utility.provider! : "Не указан"
                                )
                                detailCell(
                                    title: "Срок оплаты",
                                    value: AppFormatting.dateString(from: utility.dueDate) ?? "Не указан"
                                )
                                detailCell(
                                    title: "Оплачено",
                                    value: AppFormatting.dateString(from: utility.paidAt) ?? "Не оплачено"
                                )
                            }

                            if let notes = utility.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                                detailRow("Заметки", value: notes)
                            }

                            if let receiptId = utility.sourceReceiptId?.trimmingCharacters(in: .whitespacesAndNewlines), !receiptId.isEmpty {
                                detailRow("Квитанция", value: receiptId)
                            }

                            if let confidence = utility.ocrConfidence {
                                detailRow("OCR", value: "\(Int((confidence * 100).rounded()))%")
                            }

                            if let processedAt = utility.ocrProcessedAt {
                                detailRow("Обработано", value: AppFormatting.dateString(from: processedAt) ?? processedAt)
                            }
                        }
                    }

                    SurfaceCard {
                        EntityFilesSection(
                            entityType: "utility",
                            entityId: utility.id,
                            title: "Файлы начисления",
                            isEmbedded: true,
                            fileTypes: [
                                EntityFileType(value: "receipt", label: "Квитанция"),
                                EntityFileType(value: "document", label: "Документ"),
                                EntityFileType(value: "photo", label: "Фото")
                            ]
                        )
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
            .background(AppScreenBackground())
            .navigationTitle("Коммуналка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func detailCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct UtilityReceiptDetailSheet: View {
    let receiptId: String

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var receipt: UtilityReceiptPayload?
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(receiptId: String, initialReceipt: UtilityReceiptPayload? = nil) {
        self.receiptId = receiptId
        _receipt = State(initialValue: initialReceipt)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    if isLoading && receipt == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else if let receipt {
                        receiptSummary(receipt)
                        receiptItems(receipt.items ?? [], currency: receipt.currency ?? "KZT")

                        if !receipt.fileId.isEmpty {
                            SurfaceCard {
                                Label("Файл квитанции сохранён в системе.", systemImage: "doc.text")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                        }
                    } else {
                        sectionPlaceholder
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.Colors.warning)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
            .background(AppScreenBackground())
            .navigationTitle("Квитанция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .task(id: receiptId) { await loadReceipt() }
        }
    }

    private func receiptSummary(_ receipt: UtilityReceiptPayload) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(UtilityReceiptDisplay.receiptPeriodLabel(receipt))
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)

                        Text(receipt.totalAmount.map { AppFormatting.currency($0, currency: receipt.currency ?? "KZT") } ?? "Сумма не распознана")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }

                    Spacer()

                    StatusBadge(status: UtilityReceiptDisplay.receiptStatusLabel(receipt.status))
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.sm) {
                    detailCell("Поставщик", receipt.provider ?? "Не распознан")
                    detailCell("Лицевой счёт", receipt.accountNumber ?? "Не распознан")
                    detailCell("Дата квитанции", AppFormatting.dateString(from: receipt.paymentDate) ?? "Не распознана")
                    detailCell("Уверенность", receipt.extractionConfidence.map { "\(Int(($0 * 100).rounded()))%" } ?? "Нет данных")
                }

                if let failure = receipt.failureReason?.trimmingCharacters(in: .whitespacesAndNewlines), !failure.isEmpty {
                    detailRow("Ошибка", value: failure)
                }
            }
        }
    }

    private func receiptItems(_ items: [UtilityReceiptItemPayload], currency: String) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Строки квитанции")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                if items.isEmpty {
                    Text("Детали начислений не распознаны или ещё не загружены.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, AppTheme.Spacing.sm)
                } else {
                    ForEach(items) { item in
                        receiptItemRow(item, currency: currency)
                    }
                }
            }
        }
    }

    private func receiptItemRow(_ item: UtilityReceiptItemPayload, currency: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(UtilityReceiptDisplay.utilityTypeLabel(item.utilityType))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    if let label = item.labelRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }

                Spacer()

                Text(AppFormatting.compactAmount(item.amount, currency: currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                if let tariff = item.tariff {
                    infoPill("Тариф \(UtilityReceiptDisplay.decimalText(tariff))")
                }
                if let consumption = item.consumption {
                    infoPill("Расход \(UtilityReceiptDisplay.decimalText(consumption))\(item.unit.map { " \($0)" } ?? "")")
                }
                if item.materializedUtilityId != nil {
                    infoPill("Сохранено")
                }
            }

            if item.previousReading != nil || item.currentReading != nil {
                Text("Показания: \(item.previousReading.map { UtilityReceiptDisplay.decimalText($0) } ?? "-") → \(item.currentReading.map { UtilityReceiptDisplay.decimalText($0) } ?? "-")")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func infoPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppTheme.Colors.accent.opacity(0.1))
            .foregroundStyle(AppTheme.Colors.accent)
            .clipShape(Capsule())
    }

    private func detailCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sectionPlaceholder: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(AppTheme.Colors.accent)

                Text("Квитанция недоступна")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("Не удалось загрузить детали квитанции. Потяните экран объекта для обновления и попробуйте снова.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    private func loadReceipt() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try await APIClient.shared.requestData(
                "/v1/utility-receipts/\(receiptId)",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let decoded = try JSONDecoder().decode(APIResponse<UtilityReceiptPayload>.self, from: data)
            receipt = decoded.data
        } catch {
            errorMessage = "Не удалось загрузить детали квитанции."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}

private struct ExchangeRateConversionDTO: Decodable {
    let convertedAmount: Double
    let rateDate: String

    enum CodingKeys: String, CodingKey {
        case convertedAmount = "converted_amount"
        case rateDate = "rate_date"
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    let baseCurrency: String
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppFormatting.dateString(from: transaction.transactionDate) ?? transaction.transactionDate)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                HStack(spacing: 8) {
                    StatusBadge(status: transaction.type)

                    if let description = transaction.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(2)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(AppFormatting.compactAmount(transaction.amount, currency: transaction.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(transaction.type == "income" ? AppTheme.Colors.success : AppTheme.Colors.danger)

                Text("База \(AppFormatting.currency(transaction.amountBase, currency: baseCurrency))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Menu {
                Button("Редактировать", systemImage: "pencil", action: onEdit)
                Button("Удалить", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
