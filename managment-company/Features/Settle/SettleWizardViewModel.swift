import Combine
import Foundation

enum SettleTenantMode: String, CaseIterable, Identifiable {
    case new
    case existing

    var id: String { rawValue }
    var title: String { self == .new ? "Новый" : "Существующий" }
}

enum SettleTermMode: String, CaseIterable, Identifiable {
    case months
    case endDate

    var id: String { rawValue }
    var title: String { self == .months ? "Срок в месяцах" : "Дата окончания" }
}

enum SettleLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum SettleRecognitionState: Equatable {
    case idle
    case uploading
    /// Fields are filled in from the photo and wait for the owner's review.
    case recognized
    /// The photo is not an identity document; nothing was filled in.
    case notIdentityDocument
    case failed(RecognitionError)
}

enum SettleSubmitState: Equatable {
    case idle
    case submitting
    /// The lease exists (`settle` answered 201).
    case settled
    case failed(String)
}

enum SettleContractState: Equatable {
    case idle
    case generating
    case ready
    case failed(String)
}

/// A decision the owner has to make after a 409.
enum SettleAlert: Identifiable, Equatable {
    case iinConflict(stored: SettleTenant?, providedName: String?)
    case leaseOverlap(conflictingLeaseId: String?, range: String?)

    var id: String {
        switch self {
        case .iinConflict: return "iin_conflict"
        case .leaseOverlap: return "lease_overlap"
        }
    }
}

/// Where the wizard pushes inside its own stack.
enum SettleNavigationTarget: Identifiable, Hashable {
    case lease(String)
    case contract

    var id: String {
        switch self {
        case .lease(let id): return "lease.\(id)"
        case .contract: return "contract"
        }
    }
}

/// State and commands of `SettleWizardView` (task L14): the five steps of the move-in, the
/// recognition of the identity document, the settle command and the contract after it.
///
/// - `idempotencyKey` is made once, when the wizard opens, and kept: a repeat after a network
///   failure sends the same key, so the server replays the first answer instead of making a
///   second tenant or lease. The settle never goes to `PendingMutationQueue`.
/// - After a successful settle the lease exists. A failure of the contract step is reported on
///   its own and retried on its own: the settle is never sent twice.
@MainActor
final class SettleWizardViewModel: ObservableObject {
    // MARK: Step

    @Published private(set) var step: SettleStep
    /// Direction of the last step change, for the transition.
    @Published private(set) var isMovingForward = true

    // MARK: Property and tenant choice

    @Published private(set) var properties: [Property] = []
    @Published private(set) var tenants: [Tenant] = []
    @Published private(set) var directoryState: SettleLoadState = .idle
    @Published var showOccupied = false
    @Published var selectedPropertyId: String?
    @Published var tenantMode: SettleTenantMode = .new
    @Published var tenantQuery = ""
    @Published var selectedTenantId: String?

    // MARK: New tenant and recognition

    @Published var form = SettleTenantForm()
    @Published private(set) var recognitionState: SettleRecognitionState = .idle
    @Published private(set) var reviewReasons: [RecognitionReviewReason] = []
    @Published private(set) var fieldConfidence: [String: Double] = [:]
    @Published private(set) var overallConfidence: Double?
    /// Fields the server (422) or the check of the IIN points at.
    @Published private(set) var highlightedFields: Set<SettleTenantField> = []
    /// The saved photo of the document; goes to settle as `identity_document_file_id`.
    @Published private(set) var identityFileId: String?
    private var confirmedFields: Set<SettleTenantField> = []
    private var hasRecognitionResult = false

    // MARK: Terms

    @Published var startDate: Date {
        didSet {
            guard !dueDayEdited else { return }
            dueDay = SettleTerms.dayOfMonth(LeaseDay.string(fromPicker: startDate)) ?? dueDay
        }
    }
    @Published var termMode: SettleTermMode = .months {
        didSet {
            if termMode == .endDate, oldValue == .months, let months = Int(termMonthsText) {
                endDate = SettleTerms.endDate(start: LeaseDay.string(fromPicker: startDate), months: months)
                    .flatMap(LeaseDay.pickerDate) ?? endDate
            }
        }
    }
    @Published var termMonthsText = String(SettleTerms.defaultTermMonths)
    @Published var endDate: Date
    @Published var rentText = "" {
        didSet { if !depositEdited { depositText = rentText } }
    }
    @Published var currency = "KZT"
    @Published private(set) var depositText = ""
    @Published private(set) var dueDay: Int
    @Published var remindDays = SettleTerms.defaultRemindDays
    @Published var utilitiesPaidBy: UtilitiesPaidBy = .tenant
    @Published var renewalReminderDays = SettleTerms.defaultRenewalReminderDays
    @Published var notes = ""
    private var depositEdited = false
    private var dueDayEdited = false

    // MARK: Contract

    @Published private(set) var templates: [DocumentTemplate] = []
    @Published var selectedTemplateId: String?
    @Published var signedOnPaper = true
    @Published var signedOnDate: Date
    @Published var activateFromStart = true
    @Published var sendForSignature = true

    // MARK: Result

    @Published private(set) var submitState: SettleSubmitState = .idle
    @Published private(set) var contractState: SettleContractState = .idle
    @Published private(set) var settleResponse: SettleResponse?
    @Published var alert: SettleAlert?
    @Published var banner: String?
    @Published var navigationTarget: SettleNavigationTarget?
    @Published private(set) var isOnline = true
    /// Bumped on a successful settle (`sensoryFeedback`, like `paidSignal` of the lease screen).
    @Published private(set) var successSignal = 0
    @Published private(set) var errorSignal = 0

    // MARK: Collaborators

    let context: SettleWizardContext
    /// `Idempotency-Key` of `POST /v1/workflows/settle`, one per wizard opening.
    let idempotencyKey: String
    private let contractIdempotencyKey: String
    private let leaseService: LeaseV2Service
    private let recognition: RecognitionService
    private let contracts: ContractService
    private let directory: SettleDirectory
    private let network: SettleNetworkMonitoring
    private let now: () -> Date
    private var didStart = false
    /// The running settle, for callers that wait for it (tests).
    private(set) var submitTask: Task<Void, Never>?
    var onSettled: ((SettleResponse) -> Void)?

    init(
        context: SettleWizardContext = SettleWizardContext(),
        leaseService: LeaseV2Service,
        recognition: RecognitionService,
        contracts: ContractService,
        directory: SettleDirectory,
        network: SettleNetworkMonitoring? = nil,
        idempotencyKey: String = UUID().uuidString.lowercased(),
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.leaseService = leaseService
        self.recognition = recognition
        self.contracts = contracts
        self.directory = directory
        if let network {
            self.network = network
        } else {
            self.network = SettlePathMonitor()
        }
        self.idempotencyKey = idempotencyKey
        self.contractIdempotencyKey = UUID().uuidString.lowercased()
        self.now = now

        step = context.initialStep
        selectedPropertyId = context.propertyId
        selectedTenantId = context.tenantId
        tenantMode = context.tenantId == nil ? .new : .existing

        let start = context.startDate.flatMap(LeaseDay.pickerDate) ?? now()
        startDate = start
        endDate = SettleTerms.endDate(start: LeaseDay.string(fromPicker: start), months: SettleTerms.defaultTermMonths)
            .flatMap(LeaseDay.pickerDate) ?? start
        signedOnDate = now()
        dueDay = context.dueDay ?? SettleTerms.dayOfMonth(LeaseDay.string(fromPicker: start)) ?? 1
        dueDayEdited = context.dueDay != nil
        if let rent = context.rentAmount {
            let money = Money(major: rent, currency: context.currency ?? "KZT")
            rentText = Self.plain(money.major)
            depositText = rentText
        }
        if let currency = context.currency { self.currency = currency }
        if let deposit = context.depositAmount {
            depositText = Self.plain(deposit)
            depositEdited = true
        }
    }

    /// Loads the lists and watches the network. Safe to call on every appearance.
    func start() async {
        guard !didStart else { return }
        didStart = true
        isOnline = network.isOnline
        network.start { [weak self] online in self?.isOnline = online }
        await loadDirectory()
    }

    func stop() {
        network.stop()
    }

    func loadDirectory() async {
        directoryState = .loading
        do {
            async let loadedProperties = directory.properties()
            async let loadedTenants = directory.tenants()
            properties = try await loadedProperties
            tenants = (try? await loadedTenants) ?? []
            directoryState = .loaded
        } catch {
            directoryState = .failed("Не удалось загрузить объекты.")
        }
    }

    // MARK: Step 1: property

    /// Free, live properties. The one the entry point named always stays in the list.
    var selectableProperties: [Property] {
        properties
            .filter { !$0.isArchived }
            .filter { showOccupied || $0.status.lowercased() != "occupied" || $0.id == context.propertyId || $0.id == selectedPropertyId }
            .sorted { lhs, rhs in
                let l = lhs.status.lowercased() == "occupied"
                let r = rhs.status.lowercased() == "occupied"
                return l != r ? !l : lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var hiddenOccupiedCount: Int {
        properties.filter { !$0.isArchived && $0.status.lowercased() == "occupied" }.count
    }

    var selectedProperty: Property? {
        properties.first { $0.id == selectedPropertyId }
    }

    // MARK: Step 2: tenant

    var selectedTenant: Tenant? {
        tenants.first { $0.id == selectedTenantId }
    }

    /// Search over name, IIN and phone (the list is already on the device).
    var filteredTenants: [Tenant] {
        let query = tenantQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return tenants }
        let digits = query.filter(\.isNumber)
        return tenants.filter { tenant in
            let name = [tenant.lastName, tenant.firstName, tenant.middleName].compactMap { $0 }.joined(separator: " ").lowercased()
            if name.contains(query) { return true }
            if !digits.isEmpty {
                if (tenant.iin ?? "").contains(digits) { return true }
                if (tenant.phone ?? "").filter(\.isNumber).contains(digits) { return true }
            }
            return false
        }
    }

    /// Name shown for the tenant of the request: the form or the chosen existing one.
    var tenantDisplayName: String {
        switch tenantMode {
        case .new: return form.fullName
        case .existing: return selectedTenant.map { [$0.lastName, $0.firstName, $0.middleName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") } ?? ""
        }
    }

    func setValue(_ value: String, for field: SettleTenantField) {
        form[field] = value
        confirmedFields.insert(field)
        highlightedFields.remove(field)
    }

    func badge(for field: SettleTenantField) -> SettleFieldBadge {
        let value = form[field].trimmingCharacters(in: .whitespacesAndNewlines)
        let showsMissing = hasRecognitionResult || highlightedFields.contains(field)
        if value.isEmpty {
            return showsMissing && field.requiredForContract ? .missing : .none
        }
        if !confirmedFields.contains(field), let confidence = fieldConfidence[field.rawValue],
           confidence < RecognitionReviewReason.lowConfidenceThreshold {
            return .lowConfidence(percent: Int((confidence * 100).rounded()))
        }
        return .none
    }

    func isHighlighted(_ field: SettleTenantField) -> Bool {
        highlightedFields.contains(field)
    }

    /// The IIN is typed but is not 12 digits.
    var iinFormatWarning: String? {
        let iin = form.trimmedIIN
        guard !iin.isEmpty, !form.hasValidIINFormat else { return nil }
        return "ИИН состоит из 12 цифр."
    }

    // MARK: Recognition

    /// Sends the photo or PDF to `POST /v1/recognition/identity-document` and fills in the form.
    func recognize(_ upload: RecognitionUpload) async {
        guard recognitionState != .uploading else { return }
        guard isOnline else {
            recognitionState = .failed(.transport)
            return
        }
        guard upload.data.count <= RecognitionUpload.maxBytes else {
            recognitionState = .failed(.validation(message: "Файл больше 10 МБ. Выберите файл поменьше."))
            return
        }
        recognitionState = .uploading
        banner = nil
        do {
            let result = try await recognition.recognizeIdentityDocument(upload, tenantId: nil)
            apply(result)
        } catch let error as RecognitionError {
            fail(recognition: error)
        } catch {
            fail(recognition: .unknown)
        }
    }

    /// The photo could not be read here (a cancelled or broken pick).
    func reportUnreadableFile() {
        recognitionState = .failed(.validation(message: "Не удалось открыть файл. Выберите JPEG, PNG, HEIC или PDF."))
    }

    /// «Заполнить вручную»: drops the failure and keeps what the server saved.
    func continueManually() {
        recognitionState = .idle
    }

    private func fail(recognition error: RecognitionError) {
        recognitionState = .failed(error)
        errorSignal += 1
        if let fileId = error.fileId { identityFileId = fileId }
    }

    private func apply(_ result: IdentityRecognitionResult) {
        hasRecognitionResult = true
        reviewReasons = result.reviewReasons.map(RecognitionReviewReason.init(code:))
        overallConfidence = result.overallConfidence
        guard result.isIdentityDocument else {
            // Not a document: nothing is filled in and the saved file is not attached.
            recognitionState = .notIdentityDocument
            identityFileId = nil
            fieldConfidence = [:]
            return
        }
        let fields = result.fields
        func take(_ field: SettleTenantField, _ value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            form[field] = value
        }
        take(.lastName, fields.lastName)
        take(.firstName, fields.firstName)
        take(.middleName, fields.middleName)
        take(.iin, fields.iin)
        take(.documentNumber, fields.documentNumber)
        take(.documentIssuedBy, fields.documentIssuedBy)
        take(.documentIssuedAt, fields.documentIssuedAt.map { String($0.prefix(10)) })
        take(.birthDate, fields.birthDate.map { String($0.prefix(10)) })
        take(.registrationAddress, fields.registrationAddress)
        if let type = TenantDocumentType(rawValue: fields.documentType ?? result.documentKind.tenantDocumentType) {
            form.documentType = type
        }
        fieldConfidence = result.fieldConfidence
        confirmedFields = []
        highlightedFields = []
        identityFileId = result.fileId
        recognitionState = .recognized
    }

    // MARK: Terms

    var rentAmount: Decimal? {
        guard let money = Money.parse(rentText, currency: currency), money.major > 0 else { return nil }
        return money.major
    }

    var depositAmount: Decimal? {
        let trimmed = depositText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Money.parse(trimmed, currency: currency)?.major
    }

    var termMonths: Int? {
        guard let months = Int(termMonthsText.trimmingCharacters(in: .whitespaces)),
              (1...SettleTerms.maxTermMonths).contains(months) else { return nil }
        return months
    }

    func editDeposit(_ text: String) {
        depositEdited = true
        depositText = text
    }

    func editDueDay(_ day: Int) {
        dueDayEdited = true
        dueDay = min(max(day, 1), 31)
    }

    /// Why the terms cannot go on, else nil. Russian, ready for the footer.
    var termsError: String? {
        if rentAmount == nil { return "Укажите сумму аренды." }
        if !depositText.trimmingCharacters(in: .whitespaces).isEmpty, depositAmount == nil {
            return "Депозит: число, например 280000."
        }
        switch termMode {
        case .months:
            if termMonths == nil { return "Срок: от 1 до \(SettleTerms.maxTermMonths) месяцев." }
        case .endDate:
            if LeaseDay.string(fromPicker: endDate) <= LeaseDay.string(fromPicker: startDate) {
                return "Дата окончания должна быть позже даты заезда."
            }
        }
        return nil
    }

    /// First day of the lease as the wire value.
    var startDay: String { LeaseDay.string(fromPicker: startDate) }

    /// Last day of the lease for the summary, nil for an open-ended or invalid term.
    var endDay: String? {
        switch termMode {
        case .months: return termMonths.flatMap { SettleTerms.endDate(start: startDay, months: $0) }
        case .endDate: return LeaseDay.string(fromPicker: endDate)
        }
    }

    // MARK: Contract

    /// The signing options may not go with the dates: a signature in the future, an activation
    /// too far ahead (the API activates within 30 days of today).
    var contractError: String? {
        if signedOnPaper {
            if LeaseDay.string(fromPicker: signedOnDate) > LeaseDay.string(fromPicker: now()) {
                return "Дата подписания не может быть в будущем."
            }
            if activateFromStart, let limit = LeaseDay.addingDays(30, to: LeaseDay.string(fromPicker: now())),
               startDay > limit {
                return "Дата заезда позже чем через 30 дней: сразу активировать договор нельзя. Отключите активацию."
            }
        }
        return nil
    }

    var selectedTemplate: DocumentTemplate? {
        templates.first { $0.id == selectedTemplateId }
    }

    func loadTemplates() async {
        guard templates.isEmpty else { return }
        guard let list = try? await contracts.listTemplates() else { return }
        templates = list
        if selectedTemplateId == nil { selectedTemplateId = list.first(where: { $0.isDefault })?.id }
    }

    /// What the next press will do: no signing option leaves the lease a draft.
    var outcomeSummary: String {
        if signedOnPaper {
            return activateFromStart
                ? "Договор подписан на бумаге и станет действующим с \(LeaseDay.display(startDay))."
                : "Договор подписан на бумаге. Активировать его можно позже."
        }
        return sendForSignature ? "Договор уйдёт на подпись." : "Договор останется черновиком."
    }

    // MARK: Navigation

    var canAdvance: Bool {
        guard isOnline || step == .done else { return false }
        switch step {
        case .property: return selectedPropertyId != nil
        case .tenant:
            switch tenantMode {
            case .new:
                guard !form.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                return form.trimmedIIN.isEmpty || form.hasValidIINFormat
            case .existing:
                return selectedTenantId != nil
            }
        case .terms: return termsError == nil
        case .contract: return contractError == nil
        case .done: return false
        }
    }

    var canGoBack: Bool {
        guard let previous = step.previous else { return false }
        if case .submitting = submitState { return false }
        if settleResponse != nil { return false }
        if context.locksProperty, previous == .property { return false }
        return true
    }

    func advance() {
        guard canAdvance, let next = step.next else { return }
        banner = nil
        isMovingForward = true
        step = next
        if next == .done {
            submitTask = Task { await submit() }
        }
    }

    func back() {
        guard canGoBack, let previous = step.previous else { return }
        banner = nil
        isMovingForward = false
        step = previous
        if submitState != .settled { submitState = .idle }
    }

    func go(to target: SettleStep) {
        isMovingForward = target.rawValue >= step.rawValue
        step = target
    }

    // MARK: Settle

    /// The body of `POST /v1/workflows/settle` for what the owner entered.
    func buildRequest() -> SettleRequest? {
        guard let propertyId = selectedPropertyId, let rent = rentAmount else { return nil }
        let lease = SettleLeaseInput(
            startDate: startDay,
            endDate: termMode == .endDate ? LeaseDay.string(fromPicker: endDate) : nil,
            termMonths: termMode == .months ? termMonths : nil,
            rentAmount: rent,
            rentCurrency: currency,
            depositAmount: depositAmount,
            dueDay: dueDay,
            remindDaysBefore: remindDays,
            utilitiesPaidBy: utilitiesPaidBy,
            renewalReminderDays: renewalReminderDays,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        var request = SettleRequest(propertyId: propertyId, lease: lease)
        request.replacesLeaseId = context.replacesLeaseId
        request.templateId = selectedTemplateId
        switch tenantMode {
        case .new:
            request.tenant = form.input
            request.identityDocumentFileId = identityFileId
        case .existing:
            request.tenantId = selectedTenantId
        }
        if signedOnPaper {
            request.signedOn = LeaseDay.string(fromPicker: signedOnDate)
            if activateFromStart { request.activate = true }
        } else if sendForSignature {
            request.sendForSignature = true
        }
        return request
    }

    /// Settle, then the contract file. Safe to call again after a failure: the same
    /// `Idempotency-Key` goes out, and a lease that already exists is not created twice.
    func submit() async {
        if case .submitting = submitState { return }
        if contractState == .generating { return }
        guard isOnline else {
            submitState = .failed("Нет сети. Заселение работает только онлайн: подключитесь и повторите.")
            return
        }
        if settleResponse == nil {
            guard let request = buildRequest() else {
                submitState = .failed("Не хватает данных для договора. Вернитесь назад и проверьте шаги.")
                return
            }
            submitState = .submitting
            banner = nil
            do {
                let response = try await leaseService.settle(request, idempotencyKey: idempotencyKey)
                settleResponse = response
                submitState = .settled
                successSignal += 1
                onSettled?(response)
            } catch let error as SettleError {
                handle(error)
                return
            } catch {
                handle(.other(LiveLeaseV2Service.map(error)))
                return
            }
        }
        await generateContract()
    }

    func retryContract() async {
        guard settleResponse != nil else { return }
        await generateContract()
    }

    private func generateContract() async {
        guard let lease = settleResponse?.lease else { return }
        contractState = .generating
        let request = ContractRequest(templateId: selectedTemplateId, contractDate: nil, act: ContractAct())
        do {
            do {
                _ = try await contracts.generate(leaseId: lease.id, request: request, formats: [.pdf, .docx], idempotencyKey: contractIdempotencyKey)
            } catch ContractServiceError.pdfUnavailable {
                // No PDF converter on the server: the DOCX still works.
                _ = try await contracts.generate(leaseId: lease.id, request: request, formats: [.docx], idempotencyKey: contractIdempotencyKey)
            }
            contractState = .ready
        } catch let error as ContractServiceError {
            contractState = .failed(Self.contractMessage(error))
        } catch {
            contractState = .failed(ContractServiceError.unknown.userMessage)
        }
    }

    private static func contractMessage(_ error: ContractServiceError) -> String {
        if case .incomplete = error {
            return "Договор создан, но в документе не хватает данных. Откройте договор и заполните отмеченные поля."
        }
        return error.userMessage
    }

    /// Context for `ContractDocumentView` of the new lease.
    var contractContext: ContractLeaseContext? {
        guard let lease = settleResponse?.lease else { return nil }
        return ContractLeaseContext(leaseId: lease.id, propertyId: lease.propertyId, tenantId: lease.tenantId, startDate: lease.startDate)
    }

    // MARK: Error branches

    private func handle(_ error: SettleError) {
        errorSignal += 1
        submitState = .idle
        switch error {
        case .tenantIINConflict(let stored, let provided):
            highlightedFields = [.iin]
            go(to: .tenant)
            alert = .iinConflict(stored: stored, providedName: provided?.fullName)
        case .leaseOverlap(let id, let from, let to):
            go(to: .terms)
            let range = [from, to].compactMap { $0 }.map { LeaseDay.display($0) }.joined(separator: " — ")
            alert = .leaseOverlap(conflictingLeaseId: id, range: range.isEmpty ? nil : range)
        case .identityIncomplete(let missing):
            let fields = Set(missing.compactMap(SettleTenantField.init(wire:)))
            highlightedFields = fields.isEmpty ? Set(SettleTenantField.allCases.filter(\.requiredForContract)) : fields
            go(to: .tenant)
            banner = "Не хватает данных арендатора: \(fields.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: ", ")). Заполните отмеченные поля."
        case .validation(let fields):
            handleValidation(fields)
        case .replaceTargetInvalid:
            submitState = .failed("Этот договор нельзя заменить: он уже не действует или изменился. Закройте мастер и обновите экран.")
        case .other(let inner):
            submitState = .failed(inner.userMessage)
        }
    }

    private func handleValidation(_ errors: [SettleFieldError]) {
        let tenantFields = Set(errors.compactMap { error -> SettleTenantField? in
            error.field.hasPrefix("tenant.") ? SettleTenantField(wire: error.field) : nil
        })
        let message = errors.map(\.message).filter { !$0.isEmpty }.joined(separator: " ")
        if !tenantFields.isEmpty {
            highlightedFields = tenantFields
            go(to: .tenant)
        } else if errors.contains(where: { $0.field.hasPrefix("lease.") }) {
            go(to: .terms)
        } else if errors.contains(where: { $0.field == "signed_on" || $0.field == "activation_date" }) {
            go(to: .contract)
        } else if errors.contains(where: { $0.field == "property_id" }) {
            go(to: .property)
        } else {
            submitState = .failed(message.isEmpty ? "Проверьте введённые данные." : message)
            return
        }
        banner = message.isEmpty ? "Проверьте отмеченные поля." : message
    }

    // MARK: Alert answers

    /// «Использовать существующего» after `TENANT_IIN_CONFLICT`: the stored tenant takes the
    /// place of the new one; the owner confirms on the contract step.
    func useStoredTenant() {
        guard case .iinConflict(let stored?, _)? = alert else {
            alert = nil
            return
        }
        alert = nil
        highlightedFields = []
        if !tenants.contains(where: { $0.id == stored.id }) {
            tenants.append(Tenant(
                id: stored.id,
                firstName: stored.firstName,
                lastName: stored.lastName,
                phone: stored.phone,
                email: stored.email,
                cohabitants: stored.cohabitants,
                notes: stored.notes,
                middleName: stored.middleName,
                iin: stored.iin,
                documentType: stored.documentType,
                documentNumber: stored.documentNumber,
                documentIssuedBy: stored.documentIssuedBy,
                documentIssuedAt: stored.documentIssuedAt,
                birthDate: stored.birthDate,
                registrationAddress: stored.registrationAddress
            ))
        }
        tenantMode = .existing
        selectedTenantId = stored.id
        go(to: .contract)
    }

    /// «Исправить» after `TENANT_IIN_CONFLICT`: back to the IIN.
    func fixIIN() {
        alert = nil
        highlightedFields = [.iin]
        go(to: .tenant)
    }

    /// «Открыть договор» after `LEASE_OVERLAP`: the conflicting lease opens inside the wizard,
    /// Back returns to the entered terms.
    func openConflictingLease() {
        guard case .leaseOverlap(let id?, _)? = alert else {
            alert = nil
            return
        }
        alert = nil
        navigationTarget = .lease(id)
    }

    func dismissOverlapToTerms() {
        alert = nil
        go(to: .terms)
    }

    // MARK: Formatting

    /// `280000` for `Decimal 280000`: the plain text the rent field starts with.
    static func plain(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
