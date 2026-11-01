import Foundation

/// `lease_amendments` row: a rent and/or due-day change effective from a date, without a
/// signature cycle (spec §3.6).
struct LeaseAmendment: Encodable, Hashable, Identifiable {
    var id: String
    var effectiveFrom: String
    var rentAmount: Money?
    var dueDay: Int?
    var note: String?
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, note
        case effectiveFrom = "effective_from"
        case rentAmount = "rent_amount"
        case dueDay = "due_day"
        case createdAt = "created_at"
    }

    init(id: String, effectiveFrom: String, rentAmount: Money?, dueDay: Int?, note: String?, createdAt: String) {
        self.id = id
        self.effectiveFrom = effectiveFrom
        self.rentAmount = rentAmount
        self.dueDay = dueDay
        self.note = note
        self.createdAt = createdAt
    }

    /// The wire object carries no currency (it is the lease's rent currency), so the enclosing
    /// aggregate decodes it through this initializer (hence `Encodable` only).
    init(from decoder: Decoder, currency: String) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        effectiveFrom = try c.decode(String.self, forKey: .effectiveFrom)
        rentAmount = try c.decodeMoneyIfPresent(.rentAmount, currency: currency)
        dueDay = try c.decodeIfPresent(Int.self, forKey: .dueDay)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        createdAt = try c.decode(String.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(effectiveFrom, forKey: .effectiveFrom)
        try c.encodeMoneyIfPresent(rentAmount, forKey: .rentAmount)
        try c.encode(dueDay, forKey: .dueDay)
        try c.encode(note, forKey: .note)
        try c.encode(createdAt, forKey: .createdAt)
    }
}
