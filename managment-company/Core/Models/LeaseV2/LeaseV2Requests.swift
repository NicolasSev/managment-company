import Foundation

// Request bodies of the lease-v2 commands (spec §9.1). Amounts go out as JSON numbers in
// major units; optional fields that are `nil` are omitted.

struct MarkSignedRequest: Codable, Equatable {
    var signedOn: String
    var signedFileId: String?

    enum CodingKeys: String, CodingKey {
        case signedOn = "signed_on"
        case signedFileId = "signed_file_id"
    }
}

struct ActivateLeaseRequest: Codable, Equatable {
    var activationDate: String
    var signedOn: String?
    var signedFileId: String?

    enum CodingKeys: String, CodingKey {
        case activationDate = "activation_date"
        case signedOn = "signed_on"
        case signedFileId = "signed_file_id"
    }
}

struct CancelLeaseRequest: Codable, Equatable {
    var reason: String
    var confirm: Bool?
}

struct TerminateLeaseRequest: Codable, Equatable {
    var moveOutDate: String
    var reason: String
    var forfeitAmount: Decimal?
    var confirm: Bool?

    enum CodingKeys: String, CodingKey {
        case reason, confirm
        case moveOutDate = "move_out_date"
        case forfeitAmount = "forfeit_amount"
    }
}

struct AmendRentRequest: Codable, Equatable {
    var effectiveFrom: String
    var rentAmount: Decimal?
    var dueDay: Int?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case note
        case effectiveFrom = "effective_from"
        case rentAmount = "rent_amount"
        case dueDay = "due_day"
    }
}

struct AddExtraChargeRequest: Codable, Equatable {
    var amount: Decimal
    var chargedOn: String
    var dueDate: String?
    var description: String

    enum CodingKeys: String, CodingKey {
        case amount, description
        case chargedOn = "charged_on"
        case dueDate = "due_date"
    }
}

/// Body of `POST /v1/lease-charges/:id/payments`. `amount == nil` pays the outstanding.
struct PayChargeRequest: Codable, Equatable {
    var amount: Decimal?
    var receivedOn: String
    var method: String
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case amount, method, notes
        case receivedOn = "received_on"
    }
}

struct ReturnDepositRequest: Codable, Equatable {
    var amount: Decimal?
    var returnedOn: String
    var method: String
    var applyToDebt: Decimal?
    var notes: String?
    var confirm: Bool?

    enum CodingKeys: String, CodingKey {
        case amount, method, notes, confirm
        case returnedOn = "returned_on"
        case applyToDebt = "apply_to_debt"
    }
}

/// Payment methods accepted by the money commands.
enum LeasePaymentMethod: String, CaseIterable, Identifiable {
    case kaspi
    case cash
    case bank

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kaspi: return "Kaspi"
        case .cash: return "Наличные"
        case .bank: return "Банк"
        }
    }
}

/// Signed-contract scan picked in the mark-signed sheet. Live mode uploads it to
/// `POST /v1/files` (`entity_type=lease`, `file_type=signed_contract`) and sends the id.
struct LeaseScanAttachment: Equatable {
    var fileName: String
    var mimeType: String
    var data: Data
}

/// `{ "payment" | "charge" | "entries" | "entry": …, "lease": <aggregate> }`: the money
/// commands answer with the changed rows plus the full refreshed aggregate. Only the lease
/// is needed to refresh the screen.
struct LeaseCommandResult: Decodable {
    let lease: LeaseAggregate
}
