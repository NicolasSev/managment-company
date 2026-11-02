//
//  ContractTests.swift
//  managment-companyTests
//
//  Contract printing (task T3c): the contract screen view model on a fake service (422 list of
//  missing fields, 501 DOCX-only mode, idempotent save), the landlord profile and template
//  view models, and the pure parts of the live service (error mapping, preview query,
//  Content-Disposition). The wire models are checked by LeaseV2ContractTests.
//

import Foundation
import Testing
@testable import managment_company

private let leaseId = "2d9f6b14-8a3c-4e71-b5d0-6c1e9a7f3b02"
private let propertyId = "3f9a1c22-8e47-4b6d-a0f3-6c2e9d7b5a10"
private let tenantId = "a52d7e19-0c64-4f1b-8e3a-9b7f2c6d4e21"

/// Body of `packages/api-contracts/fixtures/contract/contract-data-incomplete.json`.
private let incompleteJSON = """
{"error":{"code":"CONTRACT_DATA_INCOMPLETE","message":"the contract needs data that is not filled in yet","details":{"fields":[
{"entity":"landlord_profile","field":"iin","placeholder":"landlord.iin","message":"укажите ИИН арендодателя"},
{"entity":"property","entity_id":"3f9a1c22-8e47-4b6d-a0f3-6c2e9d7b5a10","field":"ownership_document","placeholder":"property.ownership_document","message":"заполни правоустанавливающий документ объекта"},
{"entity":"tenant","entity_id":"a52d7e19-0c64-4f1b-8e3a-9b7f2c6d4e21","field":"birth_date","placeholder":"tenant.birth_date","message":"укажите дату рождения арендатора"}]}}}
"""

private func incompleteFields() throws -> [ContractMissingField] {
    let envelope = try JSONDecoder().decode(ContractErrorEnvelope.self, from: Data(incompleteJSON.utf8))
    return try #require(envelope.error.details?.fields)
}

private let context = ContractLeaseContext(
    leaseId: leaseId,
    propertyId: propertyId,
    tenantId: tenantId,
    startDate: "2026-11-01"
)

@MainActor
private func makeViewModel(_ service: MockContractService = MockContractService()) -> (ContractDocumentViewModel, MockContractService) {
    (ContractDocumentViewModel(context: context, service: service), service)
}

// MARK: - Contract screen

@MainActor
@Suite(.serialized)
struct ContractDocumentViewModelTests {
    @Test func loadsSevenPagePreviewAndTemplates() async throws {
        let service = MockContractService()
        service.pdfPages = 7
        let (viewModel, _) = makeViewModel(service)

        await viewModel.start()

        #expect(viewModel.previewState == .loaded(pageCount: 7))
        #expect(viewModel.canPrintOrShare)
        #expect(viewModel.pdfData != nil)
        #expect(viewModel.pdfFile?.url.pathExtension == "pdf")
        #expect(viewModel.templates.count == 1)
        #expect(service.previewCalls.count == 1)
        #expect(service.previewCalls[0].format == .pdf)
    }

    @Test func incompleteDataListsMissingFieldsWithTargets() async throws {
        let service = MockContractService()
        service.previewOutcome = .failure(.incomplete(try incompleteFields()))
        let (viewModel, _) = makeViewModel(service)

        await viewModel.start()

        let fields = viewModel.missingFields
        #expect(fields.map(\.field) == ["iin", "ownership_document", "birth_date"])
        #expect(!viewModel.canPrintOrShare)
        #expect(viewModel.fixTarget(for: fields[0]) == .landlordProfile)
        #expect(viewModel.fixTarget(for: fields[1]) == .property(id: propertyId))
        #expect(viewModel.fixTarget(for: fields[2]) == .tenant(id: tenantId))
    }

    @Test func missingFieldsAreGroupedByWhereTheyAreFixed() async throws {
        let (viewModel, _) = makeViewModel()
        let iin = ContractMissingField(entity: .landlordProfile, entityId: nil, field: "iin", placeholder: "landlord.iin", message: "a")
        let phone = ContractMissingField(entity: .landlordProfile, entityId: nil, field: "phone", placeholder: "landlord.phone", message: "b")
        let end = ContractMissingField(entity: .lease, entityId: nil, field: "end_date", placeholder: "contract.end_date_long", message: "c")
        let groups = viewModel.missingGroups([iin, end, phone] + (try incompleteFields()).dropFirst())

        #expect(groups.map(\.entity) == [.landlordProfile, .lease, .property, .tenant])
        #expect(groups[0].fields.map(\.field) == ["iin", "phone"])
        #expect(groups[0].target == .landlordProfile)
        #expect(groups[1].target == nil)
    }

    @Test func missingEntityIdFallsBackToTheLeaseOwners() {
        let (viewModel, _) = makeViewModel()
        let property = ContractMissingField(entity: .property, entityId: nil, field: "address", placeholder: "property.address", message: "m")
        let lease = ContractMissingField(entity: .lease, entityId: nil, field: "end_date", placeholder: "contract.end_date_long", message: "m")

        #expect(viewModel.fixTarget(for: property) == .property(id: propertyId))
        #expect(viewModel.fixTarget(for: lease) == nil)
    }

    @Test func previewRecoversAfterTheMissingDataIsFilled() async throws {
        let service = MockContractService()
        service.previewOutcome = .failure(.incomplete(try incompleteFields()))
        let (viewModel, _) = makeViewModel(service)
        await viewModel.start()

        service.previewOutcome = .success
        await viewModel.fixFinished()

        #expect(viewModel.previewState == .loaded(pageCount: 7))
        #expect(viewModel.activeFix == nil)
    }

    @Test func noPDFConverterSwitchesToDocxMode() async {
        let service = MockContractService()
        service.previewOutcome = .failure(.pdfUnavailable)
        let (viewModel, _) = makeViewModel(service)

        await viewModel.start()

        #expect(viewModel.previewState == .docxOnly)
        #expect(!viewModel.isPDFAvailable)
        #expect(!viewModel.canPrintOrShare)
        #expect(viewModel.formats == [.docx])

        // The mode sticks: no new PDF request.
        await viewModel.refreshPreview()
        #expect(service.previewCalls.count == 1)
    }

    @Test func saveSendsBothFormatsWithOneKeyPerIntent() async throws {
        let (viewModel, service) = makeViewModel()
        await viewModel.start()
        service.generateOutcome = .failure(.transport)

        await viewModel.saveToLease()
        #expect(viewModel.saveState == .error(ContractServiceError.transport.userMessage))
        // Same inputs retried: same key, so the server can replay.
        await viewModel.saveToLease()
        #expect(service.generateCalls.count == 2)
        #expect(service.generateCalls[0].idempotencyKey == service.generateCalls[1].idempotencyKey)
        #expect(service.generateCalls[0].formats == [.pdf, .docx])

        // Changed inputs: a new intent.
        viewModel.keysCountText = "2"
        await viewModel.saveToLease()
        #expect(service.generateCalls[2].idempotencyKey != service.generateCalls[1].idempotencyKey)
        #expect(service.generateCalls[2].request.act.keysCount == 2)

        service.generateOutcome = .success
        await viewModel.saveToLease()
        guard case .saved(let files) = viewModel.saveState else {
            Issue.record("expected saved, got \(viewModel.saveState)")
            return
        }
        #expect(files.map(\.fileType) == [.pdf, .docx])

        // After a success the next save is a new intent.
        await viewModel.saveToLease()
        #expect(service.generateCalls.last?.idempotencyKey != service.generateCalls[service.generateCalls.count - 2].idempotencyKey)
    }

    @Test func saveWhenIncompleteShowsTheMissingList() async throws {
        let service = MockContractService()
        service.generateOutcome = .failure(.incomplete(try incompleteFields()))
        let (viewModel, _) = makeViewModel(service)
        await viewModel.start()

        await viewModel.saveToLease()

        #expect(viewModel.missingFields.count == 3)
        #expect(viewModel.saveState == .error(ContractServiceError.incomplete([]).userMessage))
    }

    @Test func saveFallsBackToDocxWhenTheServerHasNoPDF() async {
        let service = MockContractService()
        let (viewModel, _) = makeViewModel(service)
        await viewModel.start()
        service.generateOutcome = .failure(.pdfUnavailable)

        await viewModel.saveToLease()
        // The scripted failure repeats for the DOCX-only retry, so it ends in an error, but the
        // mode switched and the retry asked for DOCX only.
        #expect(!viewModel.isPDFAvailable)
        #expect(service.generateCalls.map(\.formats) == [[.pdf, .docx], [.docx]])
        #expect(viewModel.previewState == .docxOnly)
    }

    @Test func savedDocxOnlyWhenNoPDF() async {
        let service = MockContractService()
        service.previewOutcome = .failure(.pdfUnavailable)
        let (viewModel, _) = makeViewModel(service)
        await viewModel.start()

        await viewModel.saveToLease()

        #expect(service.generateCalls.map(\.formats) == [[.docx]])
        guard case .saved(let files) = viewModel.saveState else {
            Issue.record("expected saved")
            return
        }
        #expect(files.map(\.fileType) == [.docx])
    }

    @Test func requestCarriesTemplateDateAndAct() {
        let (viewModel, _) = makeViewModel()
        viewModel.selectedTemplateId = "5d0c7e91-3f28-4b6a-a1d4-8e2f9c3b7a05"
        viewModel.useCustomDate = true
        viewModel.contractDate = LeaseDay.pickerDate("2026-12-05")!
        viewModel.meterElectricity = " 16968 "
        viewModel.meterWater = "412,5"
        viewModel.keysCountText = "2"
        viewModel.inventoryText = "телевизор\n\n  холодильник, большой  \n"

        let request = viewModel.request
        #expect(request.templateId == "5d0c7e91-3f28-4b6a-a1d4-8e2f9c3b7a05")
        #expect(request.contractDate == "2026-12-05")
        #expect(request.act.meterElectricity == "16968")
        #expect(request.act.meterWater == "412,5")
        #expect(request.act.keysCount == 2)
        #expect(request.act.inventory == ["телевизор", "холодильник  большой"])
        #expect(viewModel.inputError == nil)
    }

    @Test func noCustomDateLeavesItToTheServer() {
        let (viewModel, _) = makeViewModel()
        #expect(viewModel.request.contractDate == nil)
        #expect(viewModel.request.act.isEmpty)
    }

    @Test func badActInputIsRejectedBeforeTheRequest() async {
        let (viewModel, service) = makeViewModel()
        viewModel.meterWater = "12 m3"
        await viewModel.refreshPreview()
        #expect(viewModel.inputError != nil)
        #expect(service.previewCalls.isEmpty)
        if case .error = viewModel.previewState {} else { Issue.record("expected error state") }

        viewModel.meterWater = ""
        viewModel.keysCountText = "99"
        #expect(viewModel.inputError != nil)
        viewModel.keysCountText = "abc"
        #expect(viewModel.inputError != nil)
    }

    @Test func docxIsFetchedAndHandedToTheShareSheet() async throws {
        let (viewModel, service) = makeViewModel()
        // The mock cannot make a real DOCX, so script the answer through a fake that can.
        let fake = DocxService(base: service)
        let model = ContractDocumentViewModel(context: context, service: fake)
        await model.prepareDocx()

        let file = try #require(model.sharedFile)
        #expect(file.url.pathExtension == "docx")
        #expect(try Data(contentsOf: file.url) == Data("docx".utf8))
        #expect(viewModel.sharedFile == nil)
    }
}

/// Wraps the mock and answers a DOCX preview with fixed bytes.
@MainActor
private final class DocxService: ContractService {
    let base: MockContractService
    init(base: MockContractService) { self.base = base }

    func preview(leaseId: String, format: ContractFormat, request: ContractRequest) async throws -> ContractFile {
        guard format == .docx else { return try await base.preview(leaseId: leaseId, format: format, request: request) }
        return ContractFile(data: Data("docx".utf8), filename: "Договор аренды.docx", mimeType: format.mimeType)
    }

    func generate(leaseId: String, request: ContractRequest, formats: [ContractFormat], idempotencyKey: String) async throws -> ContractGenerateResponse {
        try await base.generate(leaseId: leaseId, request: request, formats: formats, idempotencyKey: idempotencyKey)
    }
    func listTemplates() async throws -> [DocumentTemplate] { try await base.listTemplates() }
    func templateFile(id: String, format: ContractFormat) async throws -> ContractFile { try await base.templateFile(id: id, format: format) }
    func uploadTemplate(name: String, isDefault: Bool, fileData: Data, fileName: String) async throws -> DocumentTemplate {
        try await base.uploadTemplate(name: name, isDefault: isDefault, fileData: fileData, fileName: fileName)
    }
    func landlordProfile() async throws -> LandlordProfile { try await base.landlordProfile() }
    func saveLandlordProfile(_ input: LandlordProfileInput) async throws -> LandlordProfile { try await base.saveLandlordProfile(input) }
}

// MARK: - Landlord profile

@MainActor
@Suite(.serialized)
struct LandlordProfileViewModelTests {
    private func emptyProfile() -> LandlordProfile {
        LandlordProfile(
            fullName: "", fullNameShortGen: "", iin: "", document: "", address: "", phone: "", phone2: "",
            bankDetails: "", gender: nil, updatedAt: nil,
            missingFields: ["full_name", "full_name_short_gen", "iin", "document", "address", "phone"]
        )
    }

    @Test func highlightsMissingFieldsUntilTyped() async {
        let service = MockContractService(profile: emptyProfile())
        let viewModel = LandlordProfileViewModel(service: service)
        await viewModel.load()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.highlightedCount == 6)
        #expect(viewModel.isHighlighted(.iin))
        #expect(!viewModel.isHighlighted(.bankDetails))

        viewModel.form.iin = "950312401236"
        #expect(!viewModel.isHighlighted(.iin))
        #expect(viewModel.highlightedCount == 5)
        #expect(viewModel.isDirty)
    }

    @Test func saveRoundTripsAndRefreshesMissing() async {
        let service = MockContractService(profile: emptyProfile())
        let viewModel = LandlordProfileViewModel(service: service)
        await viewModel.load()
        viewModel.form.fullName = "Карцева Татьяна Викторовна"
        viewModel.form.fullNameShortGen = "Карцевой Т.В."
        viewModel.form.iin = "950312401236"
        viewModel.form.document = "удостоверение"
        viewModel.form.address = "г. Алматы"
        viewModel.form.phone = "+7 777 677 84 42"
        viewModel.form.gender = .female

        await viewModel.save()

        #expect(service.savedProfiles.count == 1)
        #expect(service.savedProfiles[0].gender == .female)
        #expect(viewModel.highlightedCount == 0)
        #expect(!viewModel.isDirty)
        #expect(viewModel.message == "Профиль сохранён.")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func badIinIsRejectedLocally() async {
        let service = MockContractService(profile: emptyProfile())
        let viewModel = LandlordProfileViewModel(service: service)
        await viewModel.load()
        viewModel.form.iin = "12345"

        await viewModel.save()

        #expect(service.savedProfiles.isEmpty)
        #expect(viewModel.errorMessage == "ИИН: ровно 12 цифр.")
    }

    @Test func serverValidationErrorIsShown() async {
        let service = MockContractService(profile: emptyProfile())
        let viewModel = LandlordProfileViewModel(service: service)
        await viewModel.load()
        viewModel.form.fullName = "x"
        service.profileOutcome = .failure(.validation(message: "iin: invalid check digit"))

        await viewModel.save()

        #expect(viewModel.errorMessage == "iin: invalid check digit")
        #expect(viewModel.isDirty)
    }

    @Test func putBodyHasNullGenderAndAllFields() throws {
        let data = try JSONEncoder().encode(LandlordProfileInput())
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json.keys.sorted() == ["address", "bank_details", "document", "full_name", "full_name_short_gen", "gender", "iin", "phone", "phone2"])
        #expect(json["gender"] is NSNull)
    }
}

// MARK: - Templates

@MainActor
@Suite(.serialized)
struct ContractTemplatesViewModelTests {
    @Test func listsAndOpensATemplate() async throws {
        let service = MockContractService()
        let viewModel = ContractTemplatesViewModel(service: service)
        await viewModel.load()
        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.templates.count == 1)

        await viewModel.open(viewModel.templates[0])
        #expect(viewModel.previewFile != nil)
    }

    @Test func uploadAddsTemplateAndMakesItDefault() async {
        let service = MockContractService()
        let viewModel = ContractTemplatesViewModel(service: service)
        await viewModel.load()

        viewModel.prepareUpload(data: Data("PK".utf8), fileName: "Мой шаблон.docx")
        #expect(viewModel.draft?.name == "Мой шаблон")
        #expect(viewModel.draft?.isDefault == true)
        await viewModel.confirmUpload()

        #expect(viewModel.draft == nil)
        #expect(viewModel.templates.count == 2)
        #expect(viewModel.templates.filter(\.isDefault).map(\.name) == ["Мой шаблон"])
        #expect(service.uploads.first?.fileName == "Мой шаблон.docx")
    }

    @Test func templateInvalidShowsTheReasonAndKeepsTheDraft() async {
        let service = MockContractService()
        service.uploadOutcome = .failure(.templateInvalid(reason: "unknown placeholder", unknownPlaceholders: ["tenant.shoe_size"], splitPlaceholders: []))
        let viewModel = ContractTemplatesViewModel(service: service)
        await viewModel.load()
        viewModel.prepareUpload(data: Data("PK".utf8), fileName: "t.docx")

        await viewModel.confirmUpload()

        #expect(viewModel.draft != nil)
        #expect(viewModel.uploadError?.contains("tenant.shoe_size") == true)
        #expect(viewModel.uploadError?.contains("unknown placeholder") == true)
    }

    @Test func refusesNonDocxAndOversizedFiles() {
        let viewModel = ContractTemplatesViewModel(service: MockContractService())
        viewModel.prepareUpload(data: Data("x".utf8), fileName: "t.pdf")
        #expect(viewModel.draft == nil)
        #expect(viewModel.notice != nil)

        viewModel.prepareUpload(data: Data(count: ContractTemplatesViewModel.maxTemplateBytes + 1), fileName: "t.docx")
        #expect(viewModel.draft == nil)
        #expect(viewModel.notice == "Файл больше 5 МБ.")
    }
}

// MARK: - Live service pure parts

@MainActor
@Suite(.serialized)
struct LiveContractServiceTests {
    @Test func mapsIncompleteErrorBody() throws {
        let error = LiveContractService.mapError(status: 422, data: Data(incompleteJSON.utf8))
        #expect(error == .incomplete(try incompleteFields()))
    }

    @Test func mapsTemplateInvalid() {
        let body = #"{"error":{"code":"TEMPLATE_INVALID","message":"m","details":{"reason":"split","unknown_placeholders":["a.b"],"split_placeholders":["c.d"]}}}"#
        #expect(LiveContractService.mapError(status: 422, data: Data(body.utf8)) == .templateInvalid(reason: "split", unknownPlaceholders: ["a.b"], splitPlaceholders: ["c.d"]))
    }

    @Test func mapsPdfAndStateAndTransportErrors() {
        func map(_ status: Int, _ code: String) -> ContractServiceError {
            LiveContractService.mapError(status: status, data: Data(#"{"error":{"code":"\#(code)","message":"m"}}"#.utf8))
        }
        #expect(map(501, "PDF_CONVERSION_UNAVAILABLE") == .pdfUnavailable)
        #expect(map(502, "PDF_CONVERSION_FAILED") == .pdfFailed)
        #expect(map(422, "INVALID_STATE_TRANSITION") == .invalidState)
        #expect(map(404, "NOT_FOUND") == .notFound)
        #expect(LiveContractService.mapError(status: 503, data: Data()) == .transport)
    }

    @Test func joinsFieldErrorsOfA400() {
        let body = #"{"error":{"code":"VALIDATION_ERROR","message":"bad","details":[{"field":"iin","message":"wrong check digit"},{"field":"phone","message":"too long"}]}}"#
        #expect(LiveContractService.mapError(status: 400, data: Data(body.utf8)) == .validation(message: "iin: wrong check digit; phone: too long"))
    }

    @Test func previewQueryHasOnlyWhatIsSet() {
        var request = ContractRequest()
        #expect(LiveContractService.previewQuery(format: .pdf, request: request).map(\.name) == ["format"])

        request.templateId = "t"
        request.contractDate = "2026-11-01"
        request.act = ContractAct(meterElectricity: "1", meterWater: "2", inventory: ["a", "b"], keysCount: 2)
        let items = LiveContractService.previewQuery(format: .docx, request: request)
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(dict == [
            "format": "docx", "template_id": "t", "contract_date": "2026-11-01",
            "meter_electricity": "1", "meter_water": "2", "inventory": "a,b", "keys_count": "2",
        ])
    }

    @Test func contentDispositionPrefersTheUtf8Name() {
        let header = #"inline; filename="dogovor-Akhmetov.pdf"; filename*=UTF-8''%D0%94%D0%BE%D0%B3%D0%BE%D0%B2%D0%BE%D1%80.pdf"#
        #expect(LiveContractService.filename(fromContentDisposition: header) == "Договор.pdf")
        #expect(LiveContractService.filename(fromContentDisposition: #"attachment; filename="a.docx""#) == "a.docx")
        #expect(LiveContractService.filename(fromContentDisposition: nil) == nil)
        #expect(LiveContractService.safeFilename("../../etc/passwd") == "passwd")
    }

    @Test func generateBodyHasNullsAndOptionalAct() throws {
        let body = ContractGenerateBody(templateId: nil, contractDate: nil, formats: [.pdf, .docx], act: nil)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        #expect(json["template_id"] is NSNull)
        #expect(json["contract_date"] is NSNull)
        #expect(json["formats"] as? [String] == ["pdf", "docx"])
        #expect(json["act"] == nil)
    }
}
