import SwiftUI

/// A document ready to go up, with what it is about.
struct UtilityUploadRequest: Identifiable {
    let id = UUID()
    let upload: RecognitionUpload
    let target: UtilityUploadTarget
}

/// A bill to open in the review sheet. `payer` is what the caller already knows about the property.
struct UtilityBillRoute: Identifiable, Hashable {
    let billId: String
    var payer: UtilityPayer?

    var id: String { billId }
}

/// The wait after an upload: sending, recognising for up to 30 seconds, and then the result with
/// its next step (check the bill, open the duplicate, decide about an `other` document).
struct UtilityUploadFlowView: View {
    @StateObject private var model: UtilityUploadFlowModel
    private let upload: RecognitionUpload
    private let onOpenBill: (String) -> Void
    private let onGoToRent: () -> Void
    private let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        service: UtilityBillsService,
        request: UtilityUploadRequest,
        onOpenBill: @escaping (String) -> Void,
        onGoToRent: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: UtilityUploadFlowModel(service: service, target: request.target))
        upload = request.upload
        self.onOpenBill = onOpenBill
        self.onGoToRent = onGoToRent
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppTheme.Spacing.md) {
                        SurfaceCard {
                            result
                                .frame(maxWidth: .infinity)
                                .animation(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion), value: model.phase)
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                }
            }
            .navigationTitle("Загрузка счёта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.isWorking ? "Свернуть" : "Закрыть") { onFinished() }
                        .accessibilityIdentifier("utilities.upload.close")
                }
            }
        }
        .onAppear { model.begin(upload) }
        .sensoryFeedback(.success, trigger: isSuccess)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(false)
        .accessibilityContainer("utilities.upload")
    }

    private var isSuccess: Bool {
        if case .bill = model.phase { return true }
        return false
    }

    @ViewBuilder
    private var result: some View {
        switch model.phase {
        case .idle, .uploading:
            progress(title: "Загружаем файл…", detail: nil, identifier: "utilities.upload.uploading")
        case .recognizing:
            progress(
                title: "Распознаём счёт…",
                detail: "Обычно до 30 секунд. Окно можно закрыть: когда счёт будет готов, придёт уведомление.",
                identifier: "utilities.upload.recognizing"
            )
        case .bill(let bill):
            resultBlock(
                symbol: "checkmark.circle", tone: .success,
                title: bill.paidAt != nil && bill.totalDue == nil ? "Подтверждение оплаты получено" : "Счёт распознан",
                detail: billDetail(bill),
                identifier: "utilities.upload.bill"
            ) {
                PrimaryButton(title: "Проверить", action: { onOpenBill(bill.id) }, systemImage: "checkmark.seal")
                    .accessibilityIdentifier("utilities.upload.review")
            }
        case .duplicate(let bill):
            resultBlock(
                symbol: "doc.on.doc", tone: .info,
                title: "Этот файл уже загружен",
                detail: bill.map { "Он прикреплён к счёту за \(UtilityFormat.periodTitle($0.period).lowercased())." },
                identifier: "utilities.upload.duplicate"
            ) {
                if let bill {
                    PrimaryButton(title: "Открыть счёт", action: { onOpenBill(bill.id) })
                        .accessibilityIdentifier("utilities.upload.open_duplicate")
                }
            }
        case .other(_, let other):
            otherBlock(other)
        case .failed(let message, let bill):
            resultBlock(
                symbol: "exclamationmark.triangle", tone: .warning,
                title: "Счёт не распознан",
                detail: message,
                identifier: "utilities.upload.failed"
            ) {
                if let bill {
                    PrimaryButton(title: "Ввести вручную", action: { onOpenBill(bill.id) }, systemImage: "pencil")
                        .accessibilityIdentifier("utilities.upload.manual")
                }
            }
        case .deferred:
            resultBlock(
                symbol: "bell", tone: .info,
                title: "Распознавание занимает больше обычного",
                detail: "Придёт уведомление, когда счёт будет готов к проверке. Файл не потеряется.",
                identifier: "utilities.upload.deferred"
            ) {
                Button("Понятно") { onFinished() }
                    .buttonStyle(UtilitySecondaryButtonStyle())
                    .accessibilityIdentifier("utilities.upload.deferred.ok")
            }
        case .error(let text, let canRetry):
            resultBlock(
                symbol: "wifi.exclamationmark", tone: .danger,
                title: "Не удалось загрузить",
                detail: text,
                identifier: "utilities.upload.error"
            ) {
                if canRetry {
                    PrimaryButton(title: "Повторить", action: { Task { await model.retry() } })
                        .accessibilityIdentifier("utilities.upload.retry")
                }
            }
        }
    }

    private func billDetail(_ bill: UtilityBillBrief) -> String {
        var parts = [UtilityFormat.periodTitle(bill.period)]
        let amount = bill.totalDue ?? bill.totalPaid
        if let amount { parts.append(UtilityFormat.money(amount, currency: bill.currency, alwaysFraction: true)) }
        let hints = bill.reviewReasons.isEmpty ? "" : " Есть подсказки, на что обратить внимание."
        return parts.joined(separator: " · ") + "." + hints + " Данные ещё не подтверждены."
    }

    private func progress(title: String, detail: String?, identifier: String) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, AppTheme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func resultBlock<Actions: View>(
        symbol: String,
        tone: StatusTone,
        title: String,
        detail: String?,
        identifier: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(tone.color)
                .symbolEffect(.bounce, value: model.phase)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            actions()
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .accessibilityContainer(identifier)
    }

    /// An `other` document: a transfer that is not a utility bill. It never creates a bill.
    private func otherBlock(_ other: UtilityOtherResult) -> some View {
        var facts: [String] = []
        if let amount = other.amount { facts.append(UtilityFormat.money(amount, currency: other.currency, alwaysFraction: true)) }
        if let date = UtilityFormat.day(other.paymentDate) { facts.append(date) }
        return resultBlock(
            symbol: "doc.questionmark", tone: .warning,
            title: "Это не коммунальный счёт",
            detail: (facts.isEmpty ? "" : facts.joined(separator: " · ") + ". ") + "Счёт не создан. Файл можно связать с арендой или отклонить.",
            identifier: "utilities.upload.other"
        ) {
            VStack(spacing: AppTheme.Spacing.sm) {
                if other.actions.contains(.attachToRent) {
                    Button { onGoToRent() } label: {
                        Label("К платежам аренды", systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(UtilitySecondaryButtonStyle())
                    .accessibilityIdentifier("utilities.upload.other.rent")
                }
                if other.actions.contains(.reject) {
                    Button { Task { await model.rejectOther(); if model.didRejectOther { onFinished() } } } label: {
                        Label("Отклонить", systemImage: "xmark.circle")
                    }
                    .buttonStyle(UtilitySecondaryButtonStyle(tone: AppTheme.Colors.danger))
                    .disabled(model.isRejecting)
                    .accessibilityIdentifier("utilities.upload.other.reject")
                }
            }
        }
    }
}

// MARK: - Presenters

private struct UtilityUploadPresenter: ViewModifier {
    @Binding var request: UtilityUploadRequest?
    let service: UtilityBillsService
    let onOpenBill: (String) -> Void
    let onGoToRent: () -> Void
    let onFinished: () async -> Void

    @State private var pendingBill: String?
    @State private var pendingRent = false

    func body(content: Content) -> some View {
        content.sheet(item: $request, onDismiss: handleDismiss) { request in
            UtilityUploadFlowView(
                service: service,
                request: request,
                onOpenBill: { id in
                    pendingBill = id
                    self.request = nil
                },
                onGoToRent: {
                    pendingRent = true
                    self.request = nil
                },
                onFinished: { self.request = nil }
            )
        }
    }

    private func handleDismiss() {
        Task { await onFinished() }
        if let id = pendingBill {
            pendingBill = nil
            onOpenBill(id)
        }
        if pendingRent {
            pendingRent = false
            onGoToRent()
        }
    }
}

private struct UtilityReviewPresenter: ViewModifier {
    @Binding var route: UtilityBillRoute?
    let service: UtilityBillsService
    let timeZoneIdentifier: String
    let onChanged: () async -> Void

    func body(content: Content) -> some View {
        content.sheet(item: $route) { route in
            UtilityBillReviewSheet(
                billId: route.billId,
                service: service,
                payer: route.payer,
                timeZoneIdentifier: timeZoneIdentifier,
                onChanged: onChanged
            )
        }
    }
}

extension View {
    /// Shows the upload flow for `request` (nil: closed). `onOpenBill` runs after the sheet closed,
    /// with the bill the owner chose to check.
    func utilityUploadFlow(
        request: Binding<UtilityUploadRequest?>,
        service: UtilityBillsService,
        onOpenBill: @escaping (String) -> Void,
        onGoToRent: @escaping () -> Void = {},
        onFinished: @escaping () async -> Void = {}
    ) -> some View {
        modifier(UtilityUploadPresenter(
            request: request, service: service, onOpenBill: onOpenBill, onGoToRent: onGoToRent, onFinished: onFinished
        ))
    }

    /// Shows the review sheet of a bill (nil: closed).
    func utilityBillReview(
        route: Binding<UtilityBillRoute?>,
        service: UtilityBillsService,
        timeZoneIdentifier: String = "Asia/Almaty",
        onChanged: @escaping () async -> Void
    ) -> some View {
        modifier(UtilityReviewPresenter(route: route, service: service, timeZoneIdentifier: timeZoneIdentifier, onChanged: onChanged))
    }
}
