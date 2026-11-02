import Foundation
import UIKit

/// `ContractService` with sample data, for the lease screens that run on `MockLeaseV2Service`
/// and for the unit tests. The preview is a generated PDF; the DOCX and the template upload are
/// not available in this mode (the bytes could not be a real document).
///
/// Behaviour is scripted per call kind so a test can ask for a 422 list or a 501.
final class MockContractService: ContractService {
    static let shared = MockContractService()

    enum Outcome {
        case success
        case failure(ContractServiceError)
    }

    var previewOutcome: Outcome = .success
    var generateOutcome: Outcome = .success
    var templatesOutcome: Outcome = .success
    var profileOutcome: Outcome = .success
    var uploadOutcome: Outcome = .success
    var pdfPages = 7
    var latency: Duration = .zero

    private(set) var previewCalls: [(format: ContractFormat, request: ContractRequest)] = []
    private(set) var generateCalls: [(request: ContractRequest, formats: [ContractFormat], idempotencyKey: String)] = []
    private(set) var savedProfiles: [LandlordProfileInput] = []
    private(set) var uploads: [(name: String, isDefault: Bool, fileName: String, size: Int)] = []

    private(set) var templates: [DocumentTemplate]
    private var profile: LandlordProfile

    init(templates: [DocumentTemplate]? = nil, profile: LandlordProfile? = nil) {
        self.templates = templates ?? Self.sampleTemplates
        self.profile = profile ?? Self.sampleProfile
    }

    // MARK: ContractService

    func preview(leaseId: String, format: ContractFormat, request: ContractRequest) async throws -> ContractFile {
        previewCalls.append((format, request))
        try await pause()
        try fail(previewOutcome)
        switch format {
        case .pdf:
            return ContractFile(data: Self.makePDF(pages: pdfPages), filename: "dogovor-obrazec.pdf", mimeType: format.mimeType)
        case .docx:
            throw ContractServiceError.validation(message: "DOCX недоступен в режиме макета.")
        }
    }

    func generate(
        leaseId: String,
        request: ContractRequest,
        formats: [ContractFormat],
        idempotencyKey: String
    ) async throws -> ContractGenerateResponse {
        generateCalls.append((request, formats, idempotencyKey))
        try await pause()
        try fail(generateOutcome)
        let lease = try LeaseV2Fixtures.aggregate(named: LeaseV2Fixtures.activeName)
        let files = formats.map { format in
            GeneratedContractFile(
                id: UUID().uuidString.lowercased(),
                fileType: format == .pdf ? .pdf : .docx,
                filename: "dogovor-obrazec.\(format.fileExtension)",
                mimeType: format.mimeType,
                sizeBytes: 72_939,
                downloadUrl: nil,
                downloadUrlExpiresAt: nil
            )
        }
        return ContractGenerateResponse(files: files, lease: lease)
    }

    func listTemplates() async throws -> [DocumentTemplate] {
        try await pause()
        try fail(templatesOutcome)
        return templates
    }

    func templateFile(id: String, format: ContractFormat) async throws -> ContractFile {
        try await pause()
        try fail(templatesOutcome)
        guard format == .pdf else { throw ContractServiceError.validation(message: "DOCX недоступен в режиме макета.") }
        return ContractFile(data: Self.makePDF(pages: 2), filename: "shablon.pdf", mimeType: format.mimeType)
    }

    func uploadTemplate(name: String, isDefault: Bool, fileData: Data, fileName: String) async throws -> DocumentTemplate {
        uploads.append((name, isDefault, fileName, fileData.count))
        try await pause()
        try fail(uploadOutcome)
        if isDefault {
            templates = templates.map { var item = $0; item.isDefault = false; return item }
        }
        let created = DocumentTemplate(
            id: UUID().uuidString.lowercased(),
            kind: .rentContract,
            name: name,
            version: 1,
            isSystem: false,
            isDefault: isDefault,
            sizeBytes: Int64(fileData.count),
            createdAt: "2026-11-01T12:00:00Z",
            sha256: nil
        )
        templates.append(created)
        return created
    }

    func landlordProfile() async throws -> LandlordProfile {
        try await pause()
        try fail(profileOutcome)
        return profile
    }

    func saveLandlordProfile(_ input: LandlordProfileInput) async throws -> LandlordProfile {
        savedProfiles.append(input)
        try await pause()
        try fail(profileOutcome)
        profile = LandlordProfile(
            fullName: input.fullName,
            fullNameShortGen: input.fullNameShortGen,
            iin: input.iin,
            document: input.document,
            address: input.address,
            phone: input.phone,
            phone2: input.phone2,
            bankDetails: input.bankDetails,
            gender: input.gender,
            updatedAt: "2026-11-01T12:00:00Z",
            missingFields: Self.missingFields(of: input)
        )
        return profile
    }

    // MARK: Helpers

    private func pause() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
    }

    private func fail(_ outcome: Outcome) throws {
        if case .failure(let error) = outcome { throw error }
    }

    /// Same required set as the API (`landlord.*` placeholders without the optional ones).
    static func missingFields(of input: LandlordProfileInput) -> [String] {
        var missing: [String] = []
        func need(_ name: String, _ value: String) {
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.append(name) }
        }
        need("full_name", input.fullName)
        need("full_name_short_gen", input.fullNameShortGen)
        need("iin", input.iin)
        need("document", input.document)
        need("address", input.address)
        need("phone", input.phone)
        return missing
    }

    static let sampleTemplates: [DocumentTemplate] = [
        DocumentTemplate(
            id: "00000000-0000-4000-8000-0000000c0001",
            kind: .rentContract,
            name: "Договор аренды жилого помещения (РК, русский) + акт приема-передачи",
            version: 1,
            isSystem: true,
            isDefault: true,
            sizeBytes: nil,
            createdAt: "2026-11-01T12:00:00Z",
            sha256: nil
        )
    ]

    static let sampleProfile = LandlordProfile(
        fullName: "Карцева Татьяна Викторовна",
        fullNameShortGen: "Карцевой Т.В.",
        iin: "950312401236",
        document: "удостоверение личности РК № 038812457, выдано МВД РК 20.06.2019",
        address: "г. Алматы, ул. Джаркенская 22",
        phone: "+7 777 677 84 42",
        phone2: "",
        bankDetails: "",
        gender: .female,
        updatedAt: "2026-11-01T16:58:50Z",
        missingFields: []
    )

    /// A plain multi-page PDF (page number and a title), A4.
    static func makePDF(pages: Int) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            for page in 1...max(pages, 1) {
                context.beginPage()
                let title = "Договор аренды (образец)" as NSString
                title.draw(at: CGPoint(x: 56, y: 56), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20)])
                ("Страница \(page) из \(max(pages, 1))" as NSString)
                    .draw(at: CGPoint(x: 56, y: 96), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
            }
        }
    }
}
