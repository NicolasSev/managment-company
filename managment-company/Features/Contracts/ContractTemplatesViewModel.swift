import Combine
import Foundation

/// A picked `.docx` waiting for a name and the "default" choice.
struct ContractTemplateDraft: Identifiable, Equatable {
    let id = UUID()
    var fileName: String
    var data: Data
    var name: String
    var isDefault: Bool
}

/// State of `Settings → Шаблоны договора` (`GET/POST /v1/document-templates`).
@MainActor
final class ContractTemplatesViewModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded
        case error(String)
    }

    /// `contract.MaxTemplateSize` of the API.
    static let maxTemplateBytes = 5 * 1024 * 1024

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var templates: [DocumentTemplate] = []
    /// Template opened in QuickLook.
    @Published var previewFile: ContractTempFile?
    @Published private(set) var openingId: String?
    @Published var draft: ContractTemplateDraft?
    @Published private(set) var isUploading = false
    /// Error inside the upload sheet (422 TEMPLATE_INVALID reasons included).
    @Published private(set) var uploadError: String?
    /// Line on the list screen.
    @Published var notice: String?

    private let service: ContractService
    private let tempFiles: ContractTempFiles

    init(service: ContractService, tempFiles: ContractTempFiles = ContractTempFiles()) {
        self.service = service
        self.tempFiles = tempFiles
    }

    func load() async {
        if templates.isEmpty { loadState = .loading }
        do {
            templates = try await service.listTemplates()
            loadState = .loaded
        } catch let error as ContractServiceError {
            loadState = .error(error.userMessage)
        } catch {
            loadState = .error(ContractServiceError.unknown.userMessage)
        }
    }

    // MARK: Open

    /// Opens the template itself with its `{{placeholders}}`: the PDF, or the DOCX when the
    /// server cannot convert.
    func open(_ template: DocumentTemplate) async {
        guard openingId == nil else { return }
        openingId = template.id
        notice = nil
        defer { openingId = nil }
        do {
            let file: ContractFile
            do {
                file = try await service.templateFile(id: template.id, format: .pdf)
            } catch ContractServiceError.pdfUnavailable {
                file = try await service.templateFile(id: template.id, format: .docx)
            }
            previewFile = ContractTempFile(url: try tempFiles.write(file))
        } catch let error as ContractServiceError {
            notice = error.userMessage
        } catch {
            notice = "Не удалось открыть шаблон."
        }
    }

    // MARK: Upload

    /// Reads a picked file (security-scoped URL from `fileImporter`) into a draft.
    func prepareUpload(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            prepareUpload(data: data, fileName: url.lastPathComponent)
        } catch {
            notice = "Не удалось прочитать файл."
        }
    }

    func prepareUpload(data: Data, fileName: String) {
        notice = nil
        uploadError = nil
        guard fileName.lowercased().hasSuffix(".docx") else {
            notice = "Нужен файл Word с расширением .docx."
            return
        }
        guard data.count <= Self.maxTemplateBytes else {
            notice = "Файл больше 5 МБ."
            return
        }
        guard !data.isEmpty else {
            notice = "Файл пустой."
            return
        }
        let base = (fileName as NSString).deletingPathExtension
        draft = ContractTemplateDraft(
            fileName: fileName,
            data: data,
            name: base,
            isDefault: templates.allSatisfy { $0.isSystem }
        )
    }

    func cancelUpload() {
        draft = nil
        uploadError = nil
    }

    func confirmUpload() async {
        guard let draft, !isUploading else { return }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            uploadError = "Укажите название шаблона."
            return
        }
        isUploading = true
        uploadError = nil
        defer { isUploading = false }
        do {
            _ = try await service.uploadTemplate(name: name, isDefault: draft.isDefault, fileData: draft.data, fileName: draft.fileName)
            self.draft = nil
            notice = "Шаблон «\(name)» добавлен."
            await load()
        } catch let error as ContractServiceError {
            uploadError = error.userMessage
        } catch {
            uploadError = ContractServiceError.unknown.userMessage
        }
    }
}
