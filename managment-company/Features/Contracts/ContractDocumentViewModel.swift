import Combine
import Foundation
import PDFKit

/// What the contract screen needs to know about the lease it was opened from.
struct ContractLeaseContext: Equatable {
    var leaseId: String
    var propertyId: String
    var tenantId: String
    /// `YYYY-MM-DD`; the initial value of the contract date picker.
    var startDate: String
}

/// Where a missing contract value is fixed.
enum ContractFixTarget: Identifiable, Equatable {
    case landlordProfile
    case property(id: String)
    case tenant(id: String)

    var id: String {
        switch self {
        case .landlordProfile: return "landlord_profile"
        case .property(let id): return "property.\(id)"
        case .tenant(let id): return "tenant.\(id)"
        }
    }
}

/// Missing values that are fixed in one place.
struct ContractMissingGroup: Identifiable, Equatable {
    var entity: ContractMissingEntity
    var target: ContractFixTarget?
    var fields: [ContractMissingField]

    var id: String { "\(entity.rawValue).\(target?.id ?? "-")" }
}

enum ContractPreviewState: Equatable {
    case idle
    case loading
    case loaded(pageCount: Int)
    /// 422 CONTRACT_DATA_INCOMPLETE: the values to fill in.
    case incomplete([ContractMissingField])
    /// 501: no PDF converter on the server; only the DOCX is offered.
    case docxOnly
    case error(String)
}

enum ContractSaveState: Equatable {
    case idle
    case saving
    case saved([GeneratedContractFile])
    case error(String)
}

/// State and commands of `ContractDocumentView`. Works against any `ContractService`.
@MainActor
final class ContractDocumentViewModel: ObservableObject {
    @Published private(set) var previewState: ContractPreviewState = .idle
    @Published private(set) var saveState: ContractSaveState = .idle
    @Published private(set) var templates: [DocumentTemplate] = []
    /// nil: the server's default (the lease's own template, else the account default).
    @Published var selectedTemplateId: String?
    @Published var useCustomDate = false
    @Published var contractDate: Date
    @Published var meterElectricity = ""
    @Published var meterWater = ""
    /// One inventory item per line.
    @Published var inventoryText = ""
    @Published var keysCountText = ""
    /// The current PDF on disk (for the share sheet); nil until a preview has loaded.
    @Published private(set) var pdfFile: ContractTempFile?
    @Published private(set) var pdfData: Data?
    /// The DOCX fetched for sharing; presented as a share sheet.
    @Published var sharedFile: ContractTempFile?
    @Published private(set) var isFetchingDocx = false
    /// Informational line (printing is not available, a template list failure).
    @Published var notice: String?
    @Published var activeFix: ContractFixTarget?

    /// False after a 501: the PDF, print and PDF save are hidden, the DOCX stays.
    @Published private(set) var isPDFAvailable = true

    let context: ContractLeaseContext
    private let service: ContractService
    private let tempFiles: ContractTempFiles
    private var previewToken = 0
    private var saveIntent: (fingerprint: String, key: String)?

    init(context: ContractLeaseContext, service: ContractService, tempFiles: ContractTempFiles = ContractTempFiles()) {
        self.context = context
        self.service = service
        self.tempFiles = tempFiles
        contractDate = LeaseDay.pickerDate(context.startDate) ?? Date()
    }

    // MARK: Request

    var act: ContractAct {
        ContractAct(
            meterElectricity: meterElectricity,
            meterWater: meterWater,
            inventory: inventoryText.components(separatedBy: .newlines),
            keysCount: Int(keysCountText.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    var request: ContractRequest {
        ContractRequest(
            templateId: selectedTemplateId,
            contractDate: useCustomDate ? LeaseDay.string(fromPicker: contractDate) : nil,
            act: act.normalized
        )
    }

    /// Why the act form cannot be sent, else nil.
    var inputError: String? {
        let trimmedKeys = keysCountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeys.isEmpty, Int(trimmedKeys) == nil {
            return "Количество ключей: целое число."
        }
        return act.validationMessage
    }

    var defaultTemplateName: String? {
        templates.first(where: { $0.isDefault })?.name
    }

    var missingFields: [ContractMissingField] {
        if case .incomplete(let fields) = previewState { return fields }
        return []
    }

    var canPrintOrShare: Bool {
        if case .loaded = previewState { return pdfData != nil }
        return false
    }

    var formats: [ContractFormat] {
        isPDFAvailable ? [.pdf, .docx] : [.docx]
    }

    // MARK: Loading

    func start() async {
        await loadTemplates()
        await refreshPreview()
    }

    func loadTemplates() async {
        do {
            templates = try await service.listTemplates()
            if let selected = selectedTemplateId, !templates.contains(where: { $0.id == selected }) {
                selectedTemplateId = nil
            }
        } catch let error as ContractServiceError {
            notice = "Шаблоны не загрузились: \(error.userMessage)"
        } catch {
            notice = "Шаблоны не загрузились."
        }
    }

    /// Fetches the PDF preview for the current inputs. A newer call wins over an older one.
    func refreshPreview() async {
        previewToken += 1
        let token = previewToken
        if let message = inputError {
            previewState = .error(message)
            return
        }
        guard isPDFAvailable else {
            previewState = .docxOnly
            return
        }
        previewState = .loading
        do {
            let file = try await service.preview(leaseId: context.leaseId, format: .pdf, request: request)
            guard token == previewToken else { return }
            guard let document = PDFDocument(data: file.data), document.pageCount > 0 else {
                previewState = .error("Сервер вернул не PDF.")
                return
            }
            pdfData = file.data
            pdfFile = ContractTempFile(url: try tempFiles.write(file))
            previewState = .loaded(pageCount: document.pageCount)
        } catch {
            guard token == previewToken else { return }
            pdfData = nil
            pdfFile = nil
            apply(previewError: error)
        }
    }

    private func apply(previewError error: Error) {
        switch error as? ContractServiceError {
        case .incomplete(let fields)?:
            previewState = .incomplete(fields)
        case .pdfUnavailable?:
            isPDFAvailable = false
            previewState = .docxOnly
        case let known?:
            previewState = .error(known.userMessage)
        case nil:
            previewState = .error(ContractServiceError.unknown.userMessage)
        }
    }

    // MARK: Print

    /// Opens the system print panel with the loaded PDF.
    func printContract() {
        guard let data = pdfData else { return }
        if !ContractPrinter.printPDF(data, jobName: pdfFile?.url.lastPathComponent ?? "Договор") {
            notice = "Печать на этом устройстве недоступна."
        }
    }

    // MARK: DOCX

    /// Downloads the DOCX and hands it to the share sheet.
    func prepareDocx() async {
        guard !isFetchingDocx else { return }
        if let message = inputError {
            notice = message
            return
        }
        isFetchingDocx = true
        defer { isFetchingDocx = false }
        do {
            let file = try await service.preview(leaseId: context.leaseId, format: .docx, request: request)
            sharedFile = ContractTempFile(url: try tempFiles.write(file))
            notice = nil
        } catch let error as ContractServiceError {
            if case .incomplete(let fields) = error {
                previewState = .incomplete(fields)
            } else {
                notice = error.userMessage
            }
        } catch {
            notice = "Не удалось подготовить DOCX."
        }
    }

    // MARK: Save to the lease files

    /// `POST /v1/leases/:id/contract`. One Idempotency-Key per intent: the same inputs retried
    /// after a failure reuse the key (the server replays), changed inputs get a new one.
    func saveToLease() async {
        if case .saving = saveState { return }
        if let message = inputError {
            saveState = .error(message)
            return
        }
        saveState = .saving
        do {
            let response = try await generate(formats: formats)
            saveState = .saved(response.files)
            saveIntent = nil
        } catch let error as ContractServiceError {
            switch error {
            case .incomplete(let fields):
                previewState = .incomplete(fields)
                saveState = .error(error.userMessage)
            case .pdfUnavailable where isPDFAvailable:
                isPDFAvailable = false
                previewState = .docxOnly
                await saveDocxAfterPDFFailure()
            default:
                saveState = .error(error.userMessage)
            }
        } catch {
            saveState = .error(ContractServiceError.unknown.userMessage)
        }
    }

    private func saveDocxAfterPDFFailure() async {
        do {
            let response = try await generate(formats: [.docx])
            saveState = .saved(response.files)
            saveIntent = nil
        } catch let error as ContractServiceError {
            saveState = .error(error.userMessage)
        } catch {
            saveState = .error(ContractServiceError.unknown.userMessage)
        }
    }

    private func generate(formats: [ContractFormat]) async throws -> ContractGenerateResponse {
        let request = request
        let fingerprint = "\(request)|\(formats.map(\.rawValue))"
        let key: String
        if let intent = saveIntent, intent.fingerprint == fingerprint {
            key = intent.key
        } else {
            key = UUID().uuidString.lowercased()
            saveIntent = (fingerprint, key)
        }
        return try await service.generate(leaseId: context.leaseId, request: request, formats: formats, idempotencyKey: key)
    }

    // MARK: Missing fields

    /// Where the user can fix `field`; nil when the app has no form for it (lease terms).
    func fixTarget(for field: ContractMissingField) -> ContractFixTarget? {
        switch field.entity {
        case .landlordProfile:
            return .landlordProfile
        case .property:
            return .property(id: field.entityId ?? context.propertyId)
        case .tenant:
            return .tenant(id: field.entityId ?? context.tenantId)
        case .lease, .unknown:
            return nil
        }
    }

    /// The missing values grouped by the place they are fixed in, in the order the API listed them.
    func missingGroups(_ fields: [ContractMissingField]) -> [ContractMissingGroup] {
        var groups: [ContractMissingGroup] = []
        for field in fields {
            let target = fixTarget(for: field)
            if let index = groups.firstIndex(where: { $0.entity == field.entity && $0.target == target }) {
                groups[index].fields.append(field)
            } else {
                groups.append(ContractMissingGroup(entity: field.entity, target: target, fields: [field]))
            }
        }
        return groups
    }

    /// The fix screen closed: show the result of the fix.
    func fixFinished() async {
        activeFix = nil
        await refreshPreview()
    }

    func dismissSaved() {
        saveState = .idle
    }
}

extension ContractMissingEntity {
    var title: String {
        switch self {
        case .landlordProfile: return "Профиль арендодателя"
        case .property: return "Объект"
        case .tenant: return "Арендатор"
        case .lease: return "Договор аренды"
        case .unknown: return "Другое"
        }
    }

    var systemImage: String {
        switch self {
        case .landlordProfile: return "person.text.rectangle"
        case .property: return "building.2"
        case .tenant: return "person"
        case .lease: return "doc.text"
        case .unknown: return "questionmark.circle"
        }
    }
}
