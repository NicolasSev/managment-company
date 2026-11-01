import SwiftUI

/// Lease screen: the single source of everything about a contract (status and actions,
/// property and tenant, terms, charge queue, payments with allocations, deposit ledger,
/// tenant credit, events). Data and transitions come from a `LeaseV2Service`; today that is
/// the fixture-backed mock.
///
/// Accessibility identifiers (`lease.detail.*`) are stable hooks for the screenshot runner.
struct LeaseDetailView: View {
    @StateObject private var viewModel: LeaseDetailViewModel
    @State private var showAllEvents = false

    init(
        leaseId: String,
        service: LeaseV2Service,
        paymentQueue: LeaseChargePaymentQueueing? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: LeaseDetailViewModel(
                leaseId: leaseId,
                service: service,
                paymentQueue: paymentQueue ?? PendingMutationQueue.shared
            )
        )
    }

    var body: some View {
        ZStack {
            AppScreenBackground()
            content
        }
        .navigationTitle("Договор")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("lease.detail.screen")
        .task { await viewModel.load() }
        .refreshable { await viewModel.reload() }
        .sheet(item: $viewModel.activeSheet) { sheet in
            sheetView(sheet)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("lease.detail.loading")
        case .error(let message):
            EmptyStateView(
                title: "Договор недоступен",
                message: message,
                actionName: "Повторить",
                action: { Task { await viewModel.load() } },
                icon: "doc.badge.exclamationmark"
            )
            .accessibilityIdentifier("lease.detail.error")
        case .loaded(let lease):
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    if let banner = viewModel.banner {
                        bannerView(banner)
                    }
                    headerCard(lease)
                    actionsCard
                    balanceCard(lease)
                    termsCard(lease)
                    chargesCard(lease)
                    paymentsCard(lease)
                    depositCard(lease)
                    if !lease.amendments.isEmpty { amendmentsCard(lease) }
                    documentsCard(lease)
                    eventsCard(lease)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
    }

    // MARK: Header and actions

    private func headerCard(_ lease: LeaseAggregate) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lease.property.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .accessibilityIdentifier("lease.detail.property")
                        if let address = lease.property.address {
                            Text(address)
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                    Spacer()
                    LeaseStatusBadge(status: lease.status)
                        .accessibilityIdentifier("lease.detail.status")
                }

                Divider()

                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(AppTheme.Colors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lease.tenant.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .accessibilityIdentifier("lease.detail.tenant")
                        if let phone = lease.tenant.phone {
                            Text(phone)
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionsCard: some View {
        let buttons = viewModel.actionButtons.filter { $0.action != .returnDeposit }
        if !buttons.isEmpty {
            LeaseSectionCard(title: "Действия", identifier: "lease.detail.actions") {
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(buttons) { button in
                        actionButton(button)
                    }
                }
            }
        }
    }

    private func actionButton(_ button: LeaseActionButton) -> some View {
        let tint = button.isDestructive ? AppTheme.Colors.danger : AppTheme.Colors.accent
        return Button {
            viewModel.perform(button.action)
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: button.systemImage)
                Text(button.title).fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundStyle(tint)
            .padding(.vertical, AppTheme.Spacing.md)
            .padding(.horizontal, AppTheme.Spacing.md)
            .background(tint.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("lease.detail.action.\(button.action.rawValue)")
    }

    private func bannerView(_ message: String) -> some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.Colors.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.warning.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityIdentifier("lease.detail.banner")
    }

    // MARK: Balance and terms

    private func balanceCard(_ lease: LeaseAggregate) -> some View {
        let balance = lease.balance
        return LeaseSectionCard(title: "Баланс", identifier: "lease.detail.balance") {
            VStack(spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    LeaseMetricTile(
                        title: "К оплате",
                        value: balance.outstanding.formatted(),
                        color: balance.outstanding.isPositive ? AppTheme.Colors.textPrimary : AppTheme.Colors.success,
                        identifier: "lease.detail.balance.outstanding"
                    )
                    LeaseMetricTile(
                        title: balance.overdueCharges > 0 ? "Просрочено (\(balance.overdueCharges))" : "Просрочено",
                        value: balance.overdue.formatted(),
                        color: balance.overdue.isPositive ? AppTheme.Colors.danger : AppTheme.Colors.textPrimary,
                        identifier: "lease.detail.balance.overdue"
                    )
                }
                HStack(spacing: AppTheme.Spacing.sm) {
                    LeaseMetricTile(title: "Впереди", value: balance.upcoming.formatted(), identifier: "lease.detail.balance.upcoming")
                    LeaseMetricTile(title: "Оплачено", value: balance.paidToDate.formatted(), identifier: "lease.detail.balance.paid")
                }
                if balance.tenantCredit.isPositive {
                    LeaseKeyValueRow(
                        label: "Кредит арендатора",
                        value: balance.tenantCredit.formatted(),
                        valueColor: AppTheme.Colors.success,
                        identifier: "lease.detail.credit"
                    )
                }
                if let next = balance.nextCharge {
                    LeaseKeyValueRow(
                        label: "Ближайший платёж",
                        value: "\(next.outstanding.formatted()) до \(LeaseDay.short(next.dueDate))"
                    )
                }
            }
        }
    }

    private func termsCard(_ lease: LeaseAggregate) -> some View {
        LeaseSectionCard(title: "Условия", identifier: "lease.detail.terms") {
            VStack(spacing: AppTheme.Spacing.sm) {
                LeaseKeyValueRow(label: "Аренда", value: "\(lease.currentRentAmount.formatted()) / мес", identifier: "lease.detail.terms.rent")
                if lease.currentRentAmount != lease.rentAmount {
                    LeaseKeyValueRow(label: "Исходная ставка", value: lease.rentAmount.formatted())
                }
                LeaseKeyValueRow(label: "День оплаты", value: "\(lease.dueDay)-е число", identifier: "lease.detail.terms.due_day")
                LeaseKeyValueRow(label: "Срок", value: LeaseDay.period(lease.startDate, lease.endDate ?? lease.startDate) + (lease.endDate == nil ? " - бессрочно" : ""))
                LeaseKeyValueRow(label: "Заселение", value: LeaseDay.display(lease.activationDate), identifier: "lease.detail.terms.activation_date")
                if let moveOut = lease.moveOutDate {
                    LeaseKeyValueRow(label: "Выезд", value: LeaseDay.display(moveOut))
                }
                if let days = lease.endsInDays, lease.status == .active {
                    LeaseKeyValueRow(
                        label: "До окончания",
                        value: "\(days) дн.",
                        valueColor: lease.isEndingSoon ? AppTheme.Colors.warning : AppTheme.Colors.textPrimary
                    )
                }
                LeaseKeyValueRow(label: "Продлений", value: "\(lease.prolongationCount)", identifier: "lease.detail.terms.prolongation_count")
                if let deposit = lease.depositAmount {
                    LeaseKeyValueRow(label: "Депозит по договору", value: deposit.formatted())
                }
                LeaseKeyValueRow(label: "Коммунальные", value: lease.utilitiesPaidBy.title)
                if let reason = lease.terminationReason, !reason.isEmpty {
                    LeaseKeyValueRow(label: "Причина выезда", value: reason)
                }
                if let notes = lease.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Charges

    private func chargesCard(_ lease: LeaseAggregate) -> some View {
        let live = lease.charges.filter { !$0.isVoid }
        let queue = live.filter { $0.outstanding.isPositive }
        let settled = live.filter { !$0.outstanding.isPositive }
        return LeaseSectionCard(title: "Очередь начислений", identifier: "lease.detail.charges") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                if !lease.chargesPreview.isEmpty {
                    Text("Будут созданы при активации")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    ForEach(lease.chargesPreview, id: \.rowKey) { charge in
                        chargeRow(charge, in: lease, isPreview: true)
                    }
                } else if live.isEmpty {
                    Text("Начислений пока нет.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } else {
                    if queue.isEmpty {
                        Text("Все начисления оплачены.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.success)
                    }
                    ForEach(queue, id: \.rowKey) { charge in
                        chargeRow(charge, in: lease, isPreview: false)
                    }
                    if !settled.isEmpty {
                        DisclosureGroup("Закрытые начисления (\(settled.count))") {
                            VStack(spacing: AppTheme.Spacing.sm) {
                                ForEach(settled, id: \.rowKey) { charge in
                                    chargeRow(charge, in: lease, isPreview: false)
                                }
                            }
                            .padding(.top, AppTheme.Spacing.sm)
                        }
                        .font(.subheadline)
                        .accessibilityIdentifier("lease.detail.charges.settled")
                    }
                }
            }
        }
    }

    private func chargeRow(_ charge: LeaseCharge, in lease: LeaseAggregate, isPreview: Bool) -> some View {
        let key = charge.id ?? charge.rowKey
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                Image(systemName: charge.kind.systemImage)
                    .foregroundStyle(AppTheme.Colors.accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(charge.description ?? charge.kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("\(charge.kind == .rent ? "Период " : "")\(LeaseDay.period(charge.periodStart, charge.periodEnd)) · срок \(LeaseDay.short(charge.dueDate))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text((isPreview ? charge.amount : charge.outstanding.isPositive ? charge.outstanding : charge.amount).formatted())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(charge.isOverdue ? AppTheme.Colors.danger : AppTheme.Colors.textPrimary)
                        .accessibilityIdentifier("lease.detail.charge.\(key).outstanding")
                    if !isPreview {
                        Text(chargeCaption(charge))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(chargeCaptionColor(charge))
                    }
                }
            }
            if charge.canPay, let id = charge.id {
                Button {
                    viewModel.present(.payCharge(chargeId: id))
                } label: {
                    Label("Оплатить", systemImage: "banknote")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .background(AppTheme.Colors.accent.opacity(0.12))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lease.detail.charge.\(id).pay")
            }
        }
        .padding(AppTheme.Spacing.sm)
        .background(Color.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lease.detail.charge.\(key)")
    }

    private func chargeCaption(_ charge: LeaseCharge) -> String {
        if charge.isOverdue { return "просрочено \(charge.daysOverdue) дн." }
        if charge.paymentStatus == .partial {
            return "оплачено \(charge.allocated.formatted()) из \(charge.amount.formatted())"
        }
        return charge.paymentStatus.title
    }

    private func chargeCaptionColor(_ charge: LeaseCharge) -> Color {
        if charge.isOverdue { return AppTheme.Colors.danger }
        switch charge.paymentStatus {
        case .paid, .waived: return AppTheme.Colors.success
        case .partial: return AppTheme.Colors.warning
        default: return AppTheme.Colors.textSecondary
        }
    }

    // MARK: Payments

    private func paymentsCard(_ lease: LeaseAggregate) -> some View {
        LeaseSectionCard(title: "Платежи", identifier: "lease.detail.payments") {
            if lease.payments.isEmpty {
                Text("Платежей пока нет.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            } else {
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(lease.payments, id: \.id) { payment in
                        paymentRow(payment, in: lease)
                    }
                }
            }
        }
    }

    private func paymentRow(_ payment: LeasePayment, in lease: LeaseAggregate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LeaseDay.display(payment.receivedOn))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(paymentMeta(payment))
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Spacer()
                Text(payment.amount.formatted())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(payment.isReversed ? AppTheme.Colors.textTertiary : AppTheme.Colors.success)
                    .strikethrough(payment.isReversed)
            }
            if payment.isReversed {
                Text("Отменён\(payment.reverseReason.map { ": \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.danger)
            } else {
                ForEach(payment.allocations, id: \.chargeId) { allocation in
                    HStack {
                        Text("-> \(allocationLabel(allocation, in: lease))")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Spacer()
                        Text(allocation.amount.formatted())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                if payment.unallocated.isPositive {
                    HStack {
                        Text("-> Кредит арендатора")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.success)
                        Spacer()
                        Text(payment.unallocated.formatted())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.success)
                    }
                }
            }
            if let notes = payment.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .padding(AppTheme.Spacing.sm)
        .background(Color.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lease.detail.payment.\(payment.id)")
    }

    private func paymentMeta(_ payment: LeasePayment) -> String {
        var parts: [String] = []
        if let method = payment.method, let known = LeasePaymentMethod(rawValue: method) {
            parts.append(known.title)
        } else if let method = payment.method {
            parts.append(method == "deposit" ? "Зачёт депозита" : method)
        }
        if payment.depositPart.isPositive { parts.append("в т.ч. депозит \(payment.depositPart.formatted())") }
        return parts.joined(separator: " · ")
    }

    private func allocationLabel(_ allocation: LeasePaymentAllocation, in lease: LeaseAggregate) -> String {
        guard let charge = lease.charges.first(where: { $0.id == allocation.chargeId }) else {
            return allocation.kind.title
        }
        if let description = charge.description { return description }
        return "\(charge.kind.title) \(LeaseDay.period(charge.periodStart, charge.periodEnd))"
    }

    // MARK: Deposit

    private func depositCard(_ lease: LeaseAggregate) -> some View {
        let deposit = lease.deposit
        return LeaseSectionCard(title: "Депозит", identifier: "lease.detail.deposit") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Text(deposit.status.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .accessibilityIdentifier("lease.detail.deposit.status")
                    Spacer()
                    Text(deposit.amount.formatted())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                LeaseKeyValueRow(label: "Удерживается", value: deposit.held.formatted(), identifier: "lease.detail.deposit.held")
                if deposit.outstanding.isPositive {
                    LeaseKeyValueRow(label: "Ожидается от арендатора", value: deposit.outstanding.formatted(), valueColor: AppTheme.Colors.warning)
                }
                if deposit.returned.isPositive { LeaseKeyValueRow(label: "Возвращено", value: deposit.returned.formatted()) }
                if deposit.forfeited.isPositive { LeaseKeyValueRow(label: "Удержано владельцем", value: deposit.forfeited.formatted()) }
                if deposit.appliedToDebt.isPositive { LeaseKeyValueRow(label: "Зачтено в долг", value: deposit.appliedToDebt.formatted()) }

                if !deposit.ledger.isEmpty {
                    Divider()
                    Text("Журнал")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    ForEach(deposit.ledger.reversed(), id: \.id) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.entryType.title)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                Text("\(LeaseDay.short(entry.entryDate))\(entry.reason.map { " · \($0)" } ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                            Spacer()
                            Text(entry.amount.formatted())
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("lease.detail.deposit.entry.\(entry.id)")
                    }
                }

                if viewModel.actionButtons.contains(where: { $0.action == .returnDeposit }) {
                    Button {
                        viewModel.perform(.returnDeposit)
                    } label: {
                        Label("Депозит возвращён", systemImage: "arrow.uturn.backward.circle")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.Spacing.md)
                            .background(AppTheme.Colors.accent.opacity(0.12))
                            .foregroundStyle(AppTheme.Colors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("lease.detail.deposit.return")
                }
            }
        }
    }

    // MARK: Amendments, documents, events

    private func amendmentsCard(_ lease: LeaseAggregate) -> some View {
        LeaseSectionCard(title: "Изменения условий", identifier: "lease.detail.amendments") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                ForEach(lease.amendments) { amendment in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("С \(LeaseDay.display(amendment.effectiveFrom))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        let changes = [
                            amendment.rentAmount.map { "аренда \($0.formatted())" },
                            amendment.dueDay.map { "день оплаты \($0)-е" },
                        ].compactMap { $0 }.joined(separator: ", ")
                        Text(changes)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        if let note = amendment.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .italic()
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func documentsCard(_ lease: LeaseAggregate) -> some View {
        if !lease.documents.files.isEmpty {
            LeaseSectionCard(title: "Документы", identifier: "lease.detail.documents") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    ForEach(lease.documents.files) { file in
                        Label(file.filename, systemImage: file.id == lease.documents.signedFile?.id ? "checkmark.seal" : "doc")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                }
            }
        }
    }

    private func eventsCard(_ lease: LeaseAggregate) -> some View {
        let events = showAllEvents ? lease.events : Array(lease.events.prefix(8))
        return LeaseSectionCard(title: "События", identifier: "lease.detail.events") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.type.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(eventMeta(event))
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                if lease.events.count > 8 {
                    Button(showAllEvents ? "Свернуть" : "Показать все (\(lease.events.count))") {
                        showAllEvents.toggle()
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("lease.detail.events.toggle")
                }
            }
        }
    }

    private func eventMeta(_ event: LeaseEvent) -> String {
        var parts = [AppFormatting.dateString(from: event.at, dateStyle: .medium, timeStyle: .short) ?? event.at]
        if let actor = event.actor { parts.append(actor.name) }
        if let amount = event.payload["amount"]?.doubleValue {
            parts.append(AppFormatting.currency(amount, currency: viewModelCurrency))
        }
        return parts.joined(separator: " · ")
    }

    private var viewModelCurrency: String {
        viewModel.lease?.currency ?? "KZT"
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetView(_ sheet: LeaseSheet) -> some View {
        if let lease = viewModel.lease {
            switch sheet {
            case .markSigned: MarkSignedSheet(viewModel: viewModel, lease: lease)
            case .activate: ActivateLeaseSheet(viewModel: viewModel, lease: lease)
            case .cancel: CancelLeaseSheet(viewModel: viewModel)
            case .terminate: TerminateLeaseV2Sheet(viewModel: viewModel, lease: lease)
            case .amendRent: AmendRentSheet(viewModel: viewModel, lease: lease)
            case .addExtraCharge: AddExtraChargeSheet(viewModel: viewModel, lease: lease)
            case .payCharge(let chargeId): PayChargeSheet(viewModel: viewModel, lease: lease, chargeId: chargeId)
            case .returnDeposit: ReturnDepositSheet(viewModel: viewModel, lease: lease)
            case .replaceWithNew: ReplaceWithNewLeaseSheet(viewModel: viewModel)
            }
        }
    }
}
