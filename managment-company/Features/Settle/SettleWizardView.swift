import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Move-in wizard (task L14, M1 of the lease v2 design): Объект → Арендатор → Условия → Договор →
/// Готово. The tenant step reads the identity document with the camera (`VisionKit`), a photo or a
/// file; the last step settles (`POST /v1/workflows/settle`), builds the contract and offers
/// `LeaseDetailView`.
///
/// Present it as a sheet. `onSettled` fires once the lease exists (refresh the list behind);
/// `onOpenLease` is called with the new lease id by «К договору» (the host closes the sheet and
/// pushes `LeaseDetailView`). Without `onOpenLease` the wizard pushes the lease screen itself.
///
/// Accessibility identifiers: `settle.*`.
struct SettleWizardView: View {
    @StateObject private var viewModel: SettleWizardViewModel
    private let authManager: AuthManager
    private let onOpenLease: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?

    init(
        context: SettleWizardContext = SettleWizardContext(),
        authManager: AuthManager,
        onSettled: ((SettleResponse) -> Void)? = nil,
        onOpenLease: ((String) -> Void)? = nil
    ) {
        self.authManager = authManager
        self.onOpenLease = onOpenLease
        let mocks = LeaseV2ServiceProvider.useMocks
        let model = SettleWizardViewModel(
            context: context,
            leaseService: LeaseV2ServiceProvider.makeService(authManager: authManager),
            recognition: RecognitionServiceProvider.makeService(authManager: authManager),
            contracts: ContractServiceProvider.makeService(authManager: authManager),
            directory: mocks ? MockSettleDirectory() : LiveSettleDirectory(authManager: authManager),
            network: mocks ? StaticNetworkMonitor() : SettlePathMonitor()
        )
        model.onSettled = onSettled
        _viewModel = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()
                VStack(spacing: 0) {
                    stepper
                    if !viewModel.isOnline { offlineBanner }
                    ScrollViewReader { proxy in
                        ScrollView {
                            stepContent
                                .padding(.horizontal, AppTheme.Spacing.md)
                                .padding(.vertical, AppTheme.Spacing.lg)
                                .id(viewModel.step)
                                .transition(.opacity)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: viewModel.highlightedFields) { _, fields in
                            guard let first = SettleTenantField.allCases.first(where: fields.contains) else { return }
                            withAnimation(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion)) {
                                proxy.scrollTo(first, anchor: .center)
                            }
                        }
                    }
                    if viewModel.step != .done { bottomBar }
                }
                .animation(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: reduceMotion), value: viewModel.step)
            }
            .navigationTitle("Заселить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .accessibilityIdentifier("settle.close")
                }
            }
            .navigationDestination(item: $viewModel.navigationTarget) { target in
                destination(for: target)
            }
        }
        .interactiveDismissDisabled(viewModel.submitState == .submitting)
        .accessibilityIdentifier("settle.screen")
        .task { await viewModel.start() }
        .onDisappear { viewModel.stop() }
        .alert(
            alertTitle,
            isPresented: Binding(
                get: { viewModel.alert != nil },
                set: { if !$0 { viewModel.alert = nil } }
            ),
            presenting: viewModel.alert
        ) { alert in
            alertActions(alert)
        } message: { alert in
            Text(alertMessage(alert))
        }
        .sensoryFeedback(.success, trigger: viewModel.successSignal)
        .sensoryFeedback(.error, trigger: viewModel.errorSignal)
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCameraView(
                onScan: { image in
                    showCamera = false
                    guard let upload = RecognitionUploadBuilder.upload(from: image) else {
                        viewModel.reportUnreadableFile()
                        return
                    }
                    Task { await viewModel.recognize(upload) }
                },
                onCancel: { showCamera = false },
                onFailure: { _ in
                    showCamera = false
                    viewModel.reportUnreadableFile()
                }
            )
            .ignoresSafeArea()
            .accessibilityIdentifier("settle.camera")
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.jpeg, .png, .heic, .pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFile(result)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await handlePhoto(item) }
        }
    }

    // MARK: Header

    private var stepper: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(SettleStep.allCases) { item in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(item.rawValue <= viewModel.step.rawValue ? AppTheme.Colors.accent : AppTheme.Colors.border)
                        .frame(height: 4)
                        .accessibilityIdentifier("settle.stepper.\(item.identifier)")
                }
            }
            Text("Шаг \(viewModel.step.rawValue + 1) из \(SettleStep.allCases.count) · \(viewModel.step.title)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.sm)
        .padding(.bottom, AppTheme.Spacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Шаг \(viewModel.step.rawValue + 1) из \(SettleStep.allCases.count): \(viewModel.step.title)")
        .accessibilityIdentifier("settle.stepper")
    }

    private var offlineBanner: some View {
        SettleNotice(
            text: "Нет сети. Заселение работает только онлайн: подключитесь, чтобы продолжить.",
            tone: .danger,
            systemImage: "wifi.slash",
            identifier: "settle.offline"
        )
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch viewModel.step {
            case .property:
                SettlePropertyStep(viewModel: viewModel)
            case .tenant:
                SettleTenantStep(
                    viewModel: viewModel,
                    isCameraAvailable: DocumentCameraView.isSupported,
                    onScan: { showCamera = true },
                    photoItem: $photoItem,
                    onPickFile: { showFileImporter = true }
                )
            case .terms:
                SettleTermsStep(viewModel: viewModel)
            case .contract:
                SettleContractStep(viewModel: viewModel)
            case .done:
                SettleDoneStep(viewModel: viewModel, onOpenLease: openLease)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settle.step.\(viewModel.step.identifier)")
    }

    private var bottomBar: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            if viewModel.canGoBack {
                Button("Назад") { viewModel.back() }
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .frame(minHeight: 48)
                    .accessibilityIdentifier("settle.back")
            }
            PrimaryButton(
                title: viewModel.step == .contract ? "Заселить" : "Далее",
                action: { viewModel.advance() },
                isDisabled: !viewModel.canAdvance,
                systemImage: viewModel.step == .contract ? "person.badge.plus" : nil
            )
            .accessibilityIdentifier("settle.next")
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.background.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle().fill(AppTheme.Colors.border.opacity(0.6)).frame(height: 1)
        }
    }

    // MARK: Navigation inside the wizard

    @ViewBuilder
    private func destination(for target: SettleNavigationTarget) -> some View {
        switch target {
        case .lease(let id):
            SettleLeaseDestination(leaseId: id)
                .environmentObject(authManager)
        case .contract:
            if let context = viewModel.contractContext {
                ContractDocumentView(context: context)
                    .environmentObject(authManager)
            }
        }
    }

    private func openLease() {
        guard let id = viewModel.settleResponse?.lease.id else { return }
        if let onOpenLease {
            onOpenLease(id)
            dismiss()
        } else {
            viewModel.navigationTarget = .lease(id)
        }
    }

    // MARK: Alerts

    private var alertTitle: String {
        switch viewModel.alert {
        case .iinConflict(let stored, _)?:
            let name = stored.map { [$0.lastName, $0.firstName, $0.middleName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") }
            return "Арендатор с этим ИИН уже есть" + (name.map { ": \($0)" } ?? "")
        case .leaseOverlap?:
            return "Даты пересекаются с другим договором"
        case nil:
            return ""
        }
    }

    private func alertMessage(_ alert: SettleAlert) -> String {
        switch alert {
        case .iinConflict(_, let provided):
            if let provided, !provided.isEmpty {
                return "В форме указано другое имя: \(provided). Использовать сохранённого арендатора или исправить ИИН?"
            }
            return "Использовать сохранённого арендатора или исправить ИИН?"
        case .leaseOverlap(_, let range):
            let base = "В этом объекте уже есть договор на эти даты."
            return range.map { "\(base) Занято: \($0)." } ?? base
        }
    }

    @ViewBuilder
    private func alertActions(_ alert: SettleAlert) -> some View {
        switch alert {
        case .iinConflict(let stored, _):
            if stored != nil {
                Button("Использовать существующего") { viewModel.useStoredTenant() }
                    .accessibilityIdentifier("settle.alert.use_existing")
            }
            Button("Исправить ИИН") { viewModel.fixIIN() }
                .accessibilityIdentifier("settle.alert.fix_iin")
        case .leaseOverlap(let id, _):
            if id != nil {
                Button("Открыть договор") { viewModel.openConflictingLease() }
                    .accessibilityIdentifier("settle.alert.open_lease")
            }
            Button("Изменить даты") { viewModel.dismissOverlapToTerms() }
                .accessibilityIdentifier("settle.alert.change_dates")
        }
    }

    // MARK: Picked files

    private func handlePhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let upload = RecognitionUploadBuilder.upload(fromData: data, fileName: nil) else {
            viewModel.reportUnreadableFile()
            return
        }
        await viewModel.recognize(upload)
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let upload = RecognitionUploadBuilder.upload(fromData: data, fileName: url.lastPathComponent) else {
            viewModel.reportUnreadableFile()
            return
        }
        Task { await viewModel.recognize(upload) }
    }
}

/// `LeaseDetailView` of a lease, on the service the app currently runs on.
struct SettleLeaseDestination: View {
    let leaseId: String
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        LeaseDetailView(
            leaseId: leaseId,
            service: LeaseV2ServiceProvider.makeService(authManager: authManager)
        )
    }
}

// MARK: - Presenting the wizard from a screen

/// Shows the wizard as a sheet for the context the entry point sets, refreshes the screen behind
/// once a lease was made, and pushes `LeaseDetailView` after «К договору». The host must sit in a
/// `NavigationStack` and have `AuthManager` in the environment.
private struct SettleWizardPresenter: ViewModifier {
    @Binding var context: SettleWizardContext?
    let onChanged: () async -> Void

    @EnvironmentObject private var authManager: AuthManager
    @State private var didSettle = false
    @State private var pendingLeaseId: String?
    @State private var openedLeaseId: String?

    func body(content: Content) -> some View {
        content
            .sheet(item: $context, onDismiss: handleDismiss) { context in
                SettleWizardView(
                    context: context,
                    authManager: authManager,
                    onSettled: { _ in didSettle = true },
                    onOpenLease: { pendingLeaseId = $0 }
                )
                .environmentObject(authManager)
            }
            .navigationDestination(item: $openedLeaseId) { id in
                SettleLeaseDestination(leaseId: id)
                    .environmentObject(authManager)
            }
    }

    private func handleDismiss() {
        if didSettle {
            didSettle = false
            Task { await onChanged() }
        }
        if let id = pendingLeaseId {
            pendingLeaseId = nil
            openedLeaseId = id
        }
    }
}

extension View {
    /// Presents the move-in wizard for `context` (nil: closed). `onChanged` runs after the sheet
    /// closes if a lease was made, so the list or card behind refreshes.
    func settleWizard(context: Binding<SettleWizardContext?>, onChanged: @escaping () async -> Void) -> some View {
        modifier(SettleWizardPresenter(context: context, onChanged: onChanged))
    }
}
