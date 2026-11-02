import Foundation

/// `RecognitionService` with the answer of `briefs/_recognition-contract.md`, for previews, the
/// simulator without a server and the unit tests. Scripted per call: success, `other` (not an
/// identity document) or any `RecognitionError`.
final class MockRecognitionService: RecognitionService {
    static let shared = MockRecognitionService(latency: .milliseconds(900))

    enum Outcome {
        case success
        /// `identity-document-other.json`: a photo of something else.
        case notIdentityDocument
        case failure(RecognitionError)
    }

    var outcome: Outcome = .success
    var latency: Duration

    private(set) var calls: [(upload: RecognitionUpload, tenantId: String?)] = []

    init(latency: Duration = .zero) {
        self.latency = latency
    }

    func recognizeIdentityDocument(_ upload: RecognitionUpload, tenantId: String?) async throws -> IdentityRecognitionResult {
        calls.append((upload, tenantId))
        if latency > .zero { try await Task.sleep(for: latency) }
        switch outcome {
        case .success:
            return try Self.decode(Self.identityJSON)
        case .notIdentityDocument:
            return try Self.decode(Self.otherJSON)
        case .failure(let error):
            throw error
        }
    }

    static func decode(_ json: String) throws -> IdentityRecognitionResult {
        try JSONDecoder().decode(APIResponse<IdentityRecognitionResult>.self, from: Data(json.utf8)).data
    }

    /// `identity-document-response.json` of the contract.
    static let identityJSON = """
    {"data":{
      "extraction_id":"3f1c7a52-6d0e-4b8a-9c41-0e5b2d7f8a13","file_id":"2a6e9c1d-7f3b-4d8a-b5e0-4c1f8a3d9e67","status":"needs_review",
      "document_kind":"id_card",
      "fields":{
        "last_name":"Ахметов","first_name":"Ерлан","middle_name":"Серикович",
        "iin":"900722304561","document_type":"id_card","document_number":"052318774",
        "document_issued_by":"МВД РК","document_issued_at":"2019-08-14","expires_at":"2029-08-13",
        "birth_date":"1990-07-22","sex":"male","nationality":"Казахстан","registration_address":null
      },
      "field_confidence":{"last_name":0.99,"first_name":0.99,"middle_name":0.97,"iin":0.98,"document_number":0.95,"document_issued_by":0.9,"document_issued_at":0.93,"expires_at":0.93,"birth_date":0.98,"registration_address":0.0},
      "overall_confidence":0.94,
      "review_reasons":["missing:registration_address"],
      "provider":"gemini","model":"gemini-2.5-flash","duration_ms":6400
    }}
    """

    /// `identity-document-other.json`: `document_kind: other`, every field null.
    static let otherJSON = """
    {"data":{
      "extraction_id":"8d2b4f60-1a7c-4e93-b5d8-3c6a9e0f1b24","file_id":"5c9e1a73-2b4d-4f86-a0e7-7d3b8c1f6a95","status":"needs_review",
      "document_kind":"other",
      "fields":{
        "last_name":null,"first_name":null,"middle_name":null,
        "iin":null,"document_type":"other","document_number":null,
        "document_issued_by":null,"document_issued_at":null,"expires_at":null,
        "birth_date":null,"sex":null,"nationality":null,"registration_address":null
      },
      "field_confidence":{},
      "overall_confidence":0.0,
      "review_reasons":["not_identity_document"],
      "provider":"gemini","model":"gemini-2.5-flash","duration_ms":3100
    }}
    """
}

/// The contract name of the mock; the project pattern is `Mock<Service>` (`MockContractService`).
typealias RecognitionServiceMock = MockRecognitionService
