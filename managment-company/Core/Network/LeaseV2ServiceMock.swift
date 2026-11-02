import Foundation

private final class LeaseV2FixtureBundleToken {}

/// Reads the lease-v2 contract fixtures bundled with the app (`Core/Resources/LeaseV2Fixtures`,
/// copied from `packages/api-contracts/fixtures/lease-v2` by `make ios-contract-fixtures`).
enum LeaseV2Fixtures {
    static let activeName = "lease-aggregate.active"
    static let pendingName = "lease-aggregate.pending"
    static let tenantOverviewName = "tenant-overview"
    static let paymentQueueName = "payment-queue"
    static let settleResponseName = "settle-response"

    static func data(named name: String, bundle: Bundle? = nil) throws -> Data {
        let bundle = bundle ?? Bundle(for: LeaseV2FixtureBundleToken.self)
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "LeaseV2Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
        guard let url else { throw LeaseV2Error.notFound }
        return try Data(contentsOf: url)
    }

    static func aggregate(named name: String, bundle: Bundle? = nil) throws -> LeaseAggregate {
        try JSONDecoder().decode(APIResponse<LeaseAggregate>.self, from: data(named: name, bundle: bundle)).data
    }

    static func settleResponse(bundle: Bundle? = nil) throws -> SettleResponse {
        try JSONDecoder().decode(APIResponse<SettleResponse>.self, from: data(named: settleResponseName, bundle: bundle)).data
    }

    static func tenantOverview(bundle: Bundle? = nil) throws -> TenantOverview {
        try JSONDecoder().decode(APIResponse<TenantOverview>.self, from: data(named: tenantOverviewName, bundle: bundle)).data
    }

    static func paymentQueue(bundle: Bundle? = nil) throws -> [LeaseQueueItem] {
        try JSONDecoder().decode(APIListEnvelope<LeaseQueueItem>.self, from: data(named: paymentQueueName, bundle: bundle)).data
    }
}

/// `LeaseV2Service` backed by the contract fixtures, with the state transitions of the real
/// API imitated in memory (spec §2.1): the screen can be exercised end to end with no server.
///
/// - Every command checks `version` (`412` equivalent), the status machine, and validation,
///   applies the change, bumps `version`, recomputes the derived values, and returns the
///   whole aggregate.
/// - Money commands honour `Idempotency-Key`: same key + same body replays the stored
///   response, same key + another body throws `.idempotencyKeyReused`.
/// - `today` is fixed to the fixtures' `as_of` so the data stays deterministic.
final class MockLeaseV2Service: LeaseV2Service {
    /// Ids of the two fixture leases (active, pending signature).
    static let fixtureLeaseIds: [String] = [
        "7c1e2a40-5b3d-4f8e-9a61-2d4c8b1f0a01",
        "2d9f6b14-8a3c-4e71-b5d0-6c1e9a7f3b02",
    ]

    let today: String
    var latency: Duration

    /// Throw this from the next command (tests: network failure, 412...). Cleared after use.
    var failNextCommand: LeaseV2Error?
    /// Throw this from the next `settle` (tests: 409 TENANT_IIN_CONFLICT, 409 LEASE_OVERLAP...).
    var failNextSettle: SettleError?

    private(set) var leases: [String: LeaseAggregate]
    private(set) var commandLog: [String] = []
    /// Every `settle` that reached the service: the body and the `Idempotency-Key`.
    private(set) var settleCalls: [(request: SettleRequest, idempotencyKey: String)] = []
    private var replayStore: [String: (fingerprint: String, result: LeaseAggregate)] = [:]
    private var settleReplay: [String: (fingerprint: String, result: SettleResponse)] = [:]
    private var idCounter = 0

    init(leases: [LeaseAggregate], today: String = "2026-11-01", latency: Duration = .zero) {
        self.today = today
        self.latency = latency
        self.leases = Dictionary(uniqueKeysWithValues: leases.map { ($0.id, $0) })
    }

    /// Loads both aggregate fixtures from the app bundle.
    static func fromFixtures(bundle: Bundle? = nil, today: String = "2026-11-01", latency: Duration = .zero) throws -> MockLeaseV2Service {
        let active = try LeaseV2Fixtures.aggregate(named: LeaseV2Fixtures.activeName, bundle: bundle)
        let pending = try LeaseV2Fixtures.aggregate(named: LeaseV2Fixtures.pendingName, bundle: bundle)
        return MockLeaseV2Service(leases: [active, pending], today: today, latency: latency)
    }

    // MARK: Reads

    func fetchLease(id: String) async throws -> LeaseAggregate {
        try await simulateLatency()
        if let failure = failNextCommand {
            failNextCommand = nil
            throw failure
        }
        guard let lease = leases[id] else { throw LeaseV2Error.notFound }
        return lease
    }

    // MARK: Status machine (spec §2.1)

    func markSigned(leaseId: String, version: Int, request: MarkSignedRequest, scan: LeaseScanAttachment?) async throws -> LeaseAggregate {
        try await command("mark-signed", leaseId: leaseId, version: version, allowed: [.draft, .pendingSignature]) { lease in
            guard LeaseDay.isOnOrBefore(request.signedOn, self.today) else {
                throw LeaseV2Error.validation(message: "Дата подписания не может быть в будущем.")
            }
            if lease.status == .draft {
                lease.status = .pendingSignature
                lease.lifecycle.sentForSignatureAt = self.now
                lease.tenantSnapshot = self.snapshot(of: lease.tenant)
                lease.propertySnapshot = LeasePropertySnapshot(name: lease.property.name, address: lease.property.address, capturedAt: self.now)
            }
            lease.lifecycle.signedOn = request.signedOn
            var payload: [String: JSONValue] = ["signed_on": .string(request.signedOn)]
            if let scan {
                let file = LeaseFile(
                    id: self.nextId(),
                    filename: scan.fileName,
                    mimeType: scan.mimeType,
                    sizeBytes: scan.data.count,
                    uploadedAt: self.now
                )
                lease.documents.signedFile = file
                lease.documents.files.append(file)
                payload["signed_file_id"] = .string(file.id)
            }
            self.log(&lease, .signed, payload: .object(payload))
            if scan != nil {
                self.log(&lease, .signedScanUploaded, payload: .object(payload))
            }
        }
    }

    func activate(leaseId: String, version: Int, request: ActivateLeaseRequest) async throws -> LeaseAggregate {
        try await command("activate", leaseId: leaseId, version: version, allowed: [.draft, .pendingSignature]) { lease in
            let signedOn = request.signedOn ?? lease.lifecycle.signedOn
            guard let signedOn else {
                throw LeaseV2Error.validation(message: "Сначала отметьте договор подписанным и укажите дату подписания.")
            }
            guard LeaseDay.isOnOrBefore(signedOn, self.today) else {
                throw LeaseV2Error.validation(message: "Дата подписания не может быть в будущем.")
            }
            guard let limit = LeaseDay.addingDays(30, to: self.today), LeaseDay.isOnOrBefore(request.activationDate, limit) else {
                throw LeaseV2Error.validation(message: "Дата заселения не может быть позже чем через 30 дней.")
            }
            let wasSigned = lease.lifecycle.signedOn != nil
            lease.lifecycle.signedOn = signedOn
            lease.lifecycle.activatedAt = self.now
            if lease.tenantSnapshot == nil {
                lease.tenantSnapshot = self.snapshot(of: lease.tenant)
                lease.propertySnapshot = LeasePropertySnapshot(name: lease.property.name, address: lease.property.address, capturedAt: self.now)
            }
            lease.status = .active
            lease.activationDate = request.activationDate
            lease.nextPeriodStart = lease.chargesPreview.first { $0.kind == .rent && $0.periodStart > self.today }?.periodStart

            // Activation creates the deposit charge and the rent charges (spec §3.8, §3).
            var created = lease.chargesPreview
            for index in created.indices {
                created[index].id = self.nextId()
                created[index].state = .open
                if created[index].kind == .deposit {
                    created[index].periodStart = request.activationDate
                    created[index].periodEnd = request.activationDate
                    created[index].dueDate = request.activationDate
                    lease.deposit.chargeId = created[index].id
                }
            }
            lease.charges = created.sorted {
                if $0.periodStart != $1.periodStart { return $0.periodStart < $1.periodStart }
                return $0.kind.rank < $1.kind.rank
            }
            lease.chargesPreview = []
            lease.checklists = [LeaseChecklistSummary(kind: "move_in", status: "in_progress", done: 0, total: 6)]

            if !wasSigned {
                self.log(&lease, .signed, payload: .object(["signed_on": .string(signedOn)]))
            }
            self.log(&lease, .activated, payload: .object(["activation_date": .string(request.activationDate)]))
            self.log(&lease, .chargesGenerated, payload: .object([
                "count": .number(Double(created.count)),
                "generated_by": .string("activation"),
            ]))
        }
    }

    func cancel(leaseId: String, version: Int, request: CancelLeaseRequest) async throws -> LeaseAggregate {
        try await command("cancel", leaseId: leaseId, version: version, allowed: [.draft, .pendingSignature]) { lease in
            lease.status = .cancelled
            lease.lifecycle.cancelledAt = self.now
            lease.lifecycle.cancelReason = request.reason
            lease.chargesPreview = []
            self.log(&lease, .cancelled, payload: .object(["reason": .string(request.reason)]))
        }
    }

    func terminate(leaseId: String, version: Int, request: TerminateLeaseRequest) async throws -> LeaseAggregate {
        try await command("terminate", leaseId: leaseId, version: version, allowed: [.active]) { lease in
            let activation = lease.activationDate ?? lease.startDate
            guard request.moveOutDate >= activation else {
                throw LeaseV2Error.validation(message: "Дата выезда не может быть раньше даты заселения.")
            }
            guard let limit = LeaseDay.addingDays(30, to: self.today), request.moveOutDate <= limit else {
                throw LeaseV2Error.validation(message: "Дата выезда не может быть позже чем через 30 дней.")
            }
            let currency = lease.currency
            let early: Bool
            if let end = lease.endDate { early = request.moveOutDate < end } else { early = false }
            if !early && request.forfeitAmount != nil {
                throw LeaseV2Error.validation(message: "Удержание депозита возможно только при досрочном выезде.")
            }

            // Charges of periods starting after move-out are voided; the period containing
            // move-out stays whole (spec §3.7).
            let toVoid = lease.charges.filter { $0.state != .void && $0.periodStart > request.moveOutDate }.compactMap(\.id)
            for id in toVoid {
                if let index = lease.charges.firstIndex(where: { $0.id == id }) {
                    lease.charges[index].state = .void
                }
                LeaseV2MockEngine.moveAllocations(ofVoided: id, in: &lease, today: self.today)
                self.log(&lease, .chargeVoided, payload: .object(["charge_id": .string(id), "void_reason": .string("termination")]))
            }
            LeaseV2MockEngine.recalculate(&lease, today: self.today)

            if early {
                let held = lease.deposit.held
                let forfeit = request.forfeitAmount.map { Money(major: $0, currency: currency) } ?? held
                guard forfeit.minor >= 0, forfeit <= held else {
                    throw LeaseV2Error.depositBalanceExceeded(held: held)
                }
                if forfeit.isPositive {
                    lease.deposit.ledger.append(self.ledgerEntry(.forfeited, amount: forfeit, reason: request.reason))
                    self.log(&lease, .depositForfeited, payload: .object(["amount": .number(NSDecimalNumber(decimal: forfeit.major).doubleValue)]))
                }
            }
            lease.moveOutDate = request.moveOutDate
            lease.terminationReason = request.reason
            if early {
                lease.status = .terminated
                lease.lifecycle.terminatedAt = self.now
                self.log(&lease, .terminated, payload: .object(["move_out_date": .string(request.moveOutDate), "reason": .string(request.reason)]))
            } else {
                lease.status = .ended
                lease.lifecycle.endedAt = self.now
                self.log(&lease, .ended, payload: .object(["move_out_date": .string(request.moveOutDate)]))
            }
            lease.checklists.append(LeaseChecklistSummary(kind: "move_out", status: "in_progress", done: 0, total: 4))
        }
    }

    func amendRent(leaseId: String, version: Int, request: AmendRentRequest) async throws -> LeaseAggregate {
        try await command("amendments", leaseId: leaseId, version: version, allowed: [.active]) { lease in
            guard request.effectiveFrom >= lease.startDate else {
                throw LeaseV2Error.validation(message: "Дата вступления в силу не может быть раньше начала договора.")
            }
            guard request.rentAmount != nil || request.dueDay != nil else {
                throw LeaseV2Error.validation(message: "Укажите новую сумму аренды или день оплаты.")
            }
            if let rent = request.rentAmount, rent <= 0 {
                throw LeaseV2Error.validation(message: "Сумма аренды должна быть больше нуля.")
            }
            if let day = request.dueDay, !(1...31).contains(day) {
                throw LeaseV2Error.validation(message: "День оплаты — от 1 до 31.")
            }
            let currency = lease.currency
            let newRent = request.rentAmount.map { Money(major: $0, currency: currency) }
            if let day = request.dueDay { lease.dueDay = day }

            var voided: [JSONValue] = []
            var reissued: [JSONValue] = []
            var kept: [JSONValue] = []
            let affected = lease.charges.filter { $0.kind == .rent && $0.state != .void && $0.periodStart >= request.effectiveFrom }
            for old in affected.sorted(by: { $0.periodStart < $1.periodStart }) {
                guard let oldId = old.id else { continue }
                let amount = newRent ?? old.amount
                let dueDate = LeaseDay.dueDate(periodStart: old.periodStart, dueDay: lease.dueDay)
                if amount == old.amount && dueDate == old.dueDate { continue }
                // A charge with any allocation is never repriced (spec §3.6).
                if old.allocated.isPositive {
                    kept.append(.string(oldId))
                    continue
                }
                var fresh = old
                fresh.id = self.nextId()
                fresh.amount = amount
                fresh.dueDate = dueDate
                fresh.replacesChargeId = oldId
                if old.state == .waived { fresh.waivedAmount = amount }
                if let index = lease.charges.firstIndex(where: { $0.id == oldId }) {
                    lease.charges[index].state = .void
                }
                lease.charges.append(fresh)
                voided.append(.string(oldId))
                reissued.append(.string(fresh.id ?? ""))
            }
            lease.charges.sort {
                if $0.periodStart != $1.periodStart { return $0.periodStart < $1.periodStart }
                return $0.kind.rank < $1.kind.rank
            }
            let amendment = LeaseAmendment(
                id: self.nextId(),
                effectiveFrom: request.effectiveFrom,
                rentAmount: newRent,
                dueDay: request.dueDay,
                note: request.note,
                createdAt: self.now
            )
            lease.amendments.append(amendment)
            lease.amendments.sort { $0.effectiveFrom < $1.effectiveFrom }
            self.log(&lease, .amended, payload: .object([
                "amendment_id": .string(amendment.id),
                "effective_from": .string(request.effectiveFrom),
                "voided_charge_ids": .array(voided),
                "reissued_charge_ids": .array(reissued),
                "kept_charge_ids": .array(kept),
            ]))
            LeaseV2MockEngine.applyCredit(&lease, today: self.today)
        }
    }

    // MARK: Money commands (spec §3.8, §4, §5)

    func addExtraCharge(leaseId: String, version: Int, request: AddExtraChargeRequest, idempotencyKey: String) async throws -> LeaseAggregate {
        try await idempotent("extra-charges", leaseId: leaseId, request: request, key: idempotencyKey) {
            try await self.command("extra-charges", leaseId: leaseId, version: version, allowed: [.active, .ended, .terminated]) { lease in
                guard request.amount > 0 else {
                    throw LeaseV2Error.validation(message: "Сумма должна быть больше нуля.")
                }
                let description = request.description.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !description.isEmpty else {
                    throw LeaseV2Error.validation(message: "Опишите, за что начисление.")
                }
                let amount = Money(major: request.amount, currency: lease.currency)
                let charge = LeaseCharge(
                    id: self.nextId(),
                    kind: .extra,
                    periodStart: request.chargedOn,
                    periodEnd: request.chargedOn,
                    dueDate: request.dueDate ?? request.chargedOn,
                    amount: amount,
                    description: description
                )
                lease.charges.append(charge)
                lease.charges.sort {
                    if $0.periodStart != $1.periodStart { return $0.periodStart < $1.periodStart }
                    return $0.kind.rank < $1.kind.rank
                }
                self.log(&lease, .chargeAdded, payload: .object([
                    "charge_id": .string(charge.id ?? ""),
                    "kind": .string("extra"),
                    "amount": .number(NSDecimalNumber(decimal: request.amount).doubleValue),
                    "description": .string(description),
                ]))
                LeaseV2MockEngine.applyCredit(&lease, today: self.today)
            }
        }
    }

    func payCharge(leaseId: String, chargeId: String, request: PayChargeRequest, idempotencyKey: String) async throws -> LeaseAggregate {
        try await idempotent("lease-charges/\(chargeId)/payments", leaseId: leaseId, request: request, key: idempotencyKey) {
            try await self.command("payments", leaseId: leaseId, version: nil, allowed: [.active, .ended, .terminated]) { lease in
                guard let target = lease.charges.first(where: { $0.id == chargeId }) else { throw LeaseV2Error.notFound }
                guard target.state == .open, target.outstanding.isPositive else { throw LeaseV2Error.chargeNotPayable }
                let amount = request.amount.map { Money(major: $0, currency: lease.currency) } ?? target.outstanding
                guard amount.isPositive else {
                    throw LeaseV2Error.validation(message: "Сумма должна быть больше нуля.")
                }
                guard LeaseDay.isOnOrBefore(request.receivedOn, self.today) else {
                    throw LeaseV2Error.validation(message: "Дата оплаты не может быть в будущем.")
                }
                // Target first, then FIFO over every open charge including future ones; the
                // remainder becomes tenant credit (overpayment is never rejected).
                let result = LeaseV2MockEngine.allocate(amount: amount, target: target, among: lease.charges)
                var payment = LeasePayment(
                    id: self.nextId(),
                    receivedOn: request.receivedOn,
                    amount: amount,
                    method: request.method,
                    notes: request.notes,
                    allocations: result.lines
                )
                payment.unallocated = result.remainder
                lease.payments.insert(payment, at: 0)
                lease.payments.sort { $0.receivedOn > $1.receivedOn }

                let depositPart = result.lines.filter { $0.kind == .deposit }.reduce(Money.zero(lease.currency)) { $0 + $1.amount }
                if depositPart.isPositive {
                    lease.deposit.ledger.append(
                        self.ledgerEntry(.received, amount: depositPart, reason: "Депозит", entryDate: request.receivedOn, paymentId: payment.id)
                    )
                    self.log(&lease, .depositReceived, payload: .object(["payment_id": .string(payment.id)]))
                }
                self.log(&lease, .paymentRecorded, payload: .object([
                    "payment_id": .string(payment.id),
                    "amount": .number(NSDecimalNumber(decimal: amount.major).doubleValue),
                    "allocations": .array(result.lines.map {
                        .object([
                            "charge_id": .string($0.chargeId),
                            "amount": .number(NSDecimalNumber(decimal: $0.amount.major).doubleValue),
                        ])
                    }),
                ]))
                LeaseV2MockEngine.applyCredit(&lease, today: self.today)
            }
        }
    }

    func returnDeposit(leaseId: String, version: Int, request: ReturnDepositRequest, idempotencyKey: String) async throws -> LeaseAggregate {
        try await idempotent("deposit/return", leaseId: leaseId, request: request, key: idempotencyKey) {
            try await self.command("deposit/return", leaseId: leaseId, version: version, allowed: [.active, .ended, .terminated]) { lease in
                let currency = lease.currency
                let held = lease.deposit.held
                guard held.isPositive else {
                    throw LeaseV2Error.validation(message: "Нет удерживаемого депозита.")
                }
                let returned = request.amount.map { Money(major: $0, currency: currency) } ?? held
                let applied = request.applyToDebt.map { Money(major: $0, currency: currency) } ?? .zero(currency)
                guard returned.minor >= 0, applied.minor >= 0 else {
                    throw LeaseV2Error.validation(message: "Сумма не может быть отрицательной.")
                }
                guard (returned + applied) <= held else {
                    throw LeaseV2Error.depositBalanceExceeded(held: held)
                }
                guard LeaseDay.isOnOrBefore(request.returnedOn, self.today) else {
                    throw LeaseV2Error.validation(message: "Дата возврата не может быть в будущем.")
                }

                if applied.isPositive {
                    // Set-off against debt: a `source='deposit'` payment allocated FIFO to open
                    // rent and extra charges; never automatic (spec §5).
                    let result = LeaseV2MockEngine.allocate(
                        amount: applied,
                        target: nil,
                        among: lease.charges,
                        kinds: [ChargeKind.rent.rank, ChargeKind.extra.rank]
                    )
                    guard result.remainder.isZero else {
                        throw LeaseV2Error.validation(message: "Зачёт больше текущего долга.")
                    }
                    let payment = LeasePayment(
                        id: self.nextId(),
                        receivedOn: request.returnedOn,
                        amount: applied,
                        method: "deposit",
                        source: "deposit",
                        notes: request.notes,
                        allocations: result.lines,
                        canReverse: false
                    )
                    lease.payments.insert(payment, at: 0)
                    lease.payments.sort { $0.receivedOn > $1.receivedOn }
                    lease.deposit.ledger.append(
                        self.ledgerEntry(.appliedToDebt, amount: applied, reason: request.notes ?? "Зачёт в долг", entryDate: request.returnedOn, paymentId: payment.id)
                    )
                    self.log(&lease, .depositAppliedToDebt, payload: .object(["amount": .number(NSDecimalNumber(decimal: applied.major).doubleValue)]))
                }
                if returned.isPositive {
                    lease.deposit.ledger.append(
                        self.ledgerEntry(.returned, amount: returned, reason: request.notes ?? "Возврат депозита", entryDate: request.returnedOn)
                    )
                    self.log(&lease, .depositReturned, payload: .object(["amount": .number(NSDecimalNumber(decimal: returned.major).doubleValue)]))
                }
            }
        }
    }

    // MARK: Settle (spec §9.7)

    /// Moves a tenant in from the `settle-response` fixture: a new lease with a fresh id, the
    /// terms of the request, then the same transitions the API chains (signed, activated).
    /// Same key and body again replays the first answer; the same key with another body is
    /// `IDEMPOTENCY_KEY_REUSED`.
    func settle(_ request: SettleRequest, idempotencyKey: String) async throws -> SettleResponse {
        try await simulateLatency()
        commandLog.append("settle")
        settleCalls.append((request, idempotencyKey))
        if let failure = failNextSettle {
            failNextSettle = nil
            throw failure
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fingerprint = String(data: (try? encoder.encode(request)) ?? Data(), encoding: .utf8) ?? ""
        if let stored = settleReplay[idempotencyKey] {
            guard stored.fingerprint == fingerprint else { throw SettleError.other(.idempotencyKeyReused) }
            return stored.result
        }
        guard request.tenant != nil || request.tenantId != nil else {
            throw SettleError.validation(fields: [SettleFieldError(field: "tenant", message: "Укажите арендатора.")])
        }

        var response = try LeaseV2Fixtures.settleResponse()
        var lease = response.lease
        let currency = request.lease.rentCurrency
        lease.id = nextId()
        lease.version = 1
        lease.propertyId = request.propertyId
        lease.property.id = request.propertyId
        lease.replacedByLeaseId = nil
        lease.renewedFromLeaseId = request.replacesLeaseId
        lease.startDate = request.lease.startDate
        lease.endDate = request.lease.endDate
            ?? request.lease.termMonths.flatMap { SettleTerms.endDate(start: request.lease.startDate, months: $0) }
        lease.rentAmount = Money(major: request.lease.rentAmount, currency: currency)
        lease.currentRentAmount = lease.rentAmount
        lease.depositAmount = request.lease.depositAmount.map { Money(major: $0, currency: currency) }
        lease.dueDay = request.lease.dueDay ?? lease.dueDay
        lease.remindDaysBefore = request.lease.remindDaysBefore ?? lease.remindDaysBefore
        lease.utilitiesPaidBy = request.lease.utilitiesPaidBy
        lease.renewalReminderDays = request.lease.renewalReminderDays ?? lease.renewalReminderDays
        lease.notes = request.lease.notes
        for index in lease.chargesPreview.indices {
            switch lease.chargesPreview[index].kind {
            case .rent: lease.chargesPreview[index].amount = lease.rentAmount
            case .deposit: lease.chargesPreview[index].amount = lease.depositAmount ?? Money.zero(currency)
            default: break
            }
        }
        lease.lifecycle.createdAt = now

        var tenant = response.tenant
        if let input = request.tenant {
            tenant.id = nextId()
            tenant.firstName = input.firstName
            tenant.lastName = input.lastName
            tenant.middleName = input.middleName
            tenant.phone = input.phone
            tenant.email = input.email
            tenant.iin = input.iin
            tenant.documentType = input.documentType
            tenant.documentNumber = input.documentNumber
            tenant.documentIssuedBy = input.documentIssuedBy
            tenant.documentIssuedAt = input.documentIssuedAt
            tenant.birthDate = input.birthDate
            tenant.registrationAddress = input.registrationAddress
            tenant.notes = input.notes
            tenant.cohabitants = input.cohabitants
            response.tenantCreated = true
        } else if let tenantId = request.tenantId {
            tenant.id = tenantId
            response.tenantCreated = false
        }
        lease.tenantId = tenant.id
        lease.tenant = LeaseTenantCard(
            id: tenant.id,
            firstName: tenant.firstName,
            lastName: tenant.lastName,
            middleName: tenant.middleName,
            fullName: [tenant.lastName, tenant.firstName, tenant.middleName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "),
            phone: tenant.phone,
            email: tenant.email,
            iin: tenant.iin
        )

        // Draft first, then the transitions of the request (activate > signed_on > send).
        lease.status = .draft
        lease.lifecycle.sentForSignatureAt = nil
        lease.lifecycle.signedOn = nil
        lease.tenantSnapshot = nil
        lease.propertySnapshot = nil
        lease.events = []
        log(&lease, .created, payload: .object(["via": .string("workflows.settle")]))
        LeaseV2MockEngine.recalculate(&lease, today: today)
        leases[lease.id] = lease

        var result = lease
        // The mock calendar is fixed (`today`); a device date after it must not read as the future.
        let signedOn = request.signedOn.map { min($0, today) }
        if request.activate == true {
            let signed = signedOn ?? today
            _ = try await markSigned(leaseId: lease.id, version: result.version, request: MarkSignedRequest(signedOn: signed), scan: nil)
            result = try await activate(
                leaseId: lease.id,
                version: leases[lease.id]?.version ?? result.version,
                request: ActivateLeaseRequest(activationDate: request.activationDate ?? request.lease.startDate, signedOn: signed)
            )
        } else if let signedOn {
            result = try await markSigned(leaseId: lease.id, version: result.version, request: MarkSignedRequest(signedOn: signedOn), scan: nil)
        } else if request.sendForSignature == true {
            result = try await markSignedOrSend(leaseId: lease.id)
        }
        log(&result, .unknown("workflow.settled"), payload: .object([
            "source": .string(request.source),
            "tenant_created": .bool(response.tenantCreated),
        ]))
        leases[result.id] = result

        response.tenant = tenant
        response.lease = result
        settleReplay[idempotencyKey] = (fingerprint, response)
        return response
    }

    /// `send-for-signature` has no method on the service seam (the app has no button for it);
    /// the mock moves the draft to `pending_signature` itself.
    private func markSignedOrSend(leaseId: String) async throws -> LeaseAggregate {
        guard var lease = leases[leaseId] else { throw LeaseV2Error.notFound }
        lease.status = .pendingSignature
        lease.version += 1
        lease.lifecycle.sentForSignatureAt = now
        lease.tenantSnapshot = snapshot(of: lease.tenant)
        lease.propertySnapshot = LeasePropertySnapshot(name: lease.property.name, address: lease.property.address, capturedAt: now)
        log(&lease, .sentForSignature, payload: .object([:]))
        LeaseV2MockEngine.recalculate(&lease, today: today)
        leases[leaseId] = lease
        return lease
    }

    // MARK: Plumbing

    private var now: String { "\(today)T12:00:00+05:00" }

    private func simulateLatency() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
    }

    private func nextId() -> String {
        idCounter += 1
        return String(format: "00000000-0000-4000-8000-%012d", idCounter)
    }

    private func log(_ lease: inout LeaseAggregate, _ type: LeaseEventType, payload: JSONValue) {
        lease.events.insert(
            LeaseEvent(
                id: nextId(),
                at: now,
                type: type,
                actor: LeaseEventActor(id: "mock-user", name: "Вы"),
                payload: payload
            ),
            at: 0
        )
    }

    private func ledgerEntry(
        _ type: DepositEntryType,
        amount: Money,
        reason: String?,
        entryDate: String? = nil,
        paymentId: String? = nil
    ) -> DepositLedgerEntry {
        DepositLedgerEntry(
            id: nextId(),
            entryType: type,
            amount: amount,
            entryDate: entryDate ?? today,
            reason: reason,
            transactionId: nil,
            leasePaymentId: paymentId,
            reversesEntryId: nil,
            reversedByEntryId: nil,
            createdAt: now
        )
    }

    private func snapshot(of tenant: LeaseTenantCard) -> LeaseTenantSnapshot {
        LeaseTenantSnapshot(
            firstName: tenant.firstName,
            lastName: tenant.lastName,
            middleName: tenant.middleName,
            fullName: tenant.fullName,
            iin: tenant.iin,
            phone: tenant.phone,
            email: tenant.email,
            capturedAt: now
        )
    }

    /// Runs one command: latency, injected failure, lookup, `If-Match`, status check, mutate,
    /// `version += 1`, recompute, store.
    private func command(
        _ name: String,
        leaseId: String,
        version: Int?,
        allowed: Set<LeaseStatus>,
        mutate: (inout LeaseAggregate) throws -> Void
    ) async throws -> LeaseAggregate {
        try await simulateLatency()
        commandLog.append(name)
        if let failure = failNextCommand {
            failNextCommand = nil
            throw failure
        }
        guard var lease = leases[leaseId] else { throw LeaseV2Error.notFound }
        if let version, version != lease.version {
            throw LeaseV2Error.versionMismatch(currentVersion: lease.version)
        }
        guard allowed.contains(lease.status) else {
            throw LeaseV2Error.invalidStateTransition(command: name)
        }
        try mutate(&lease)
        lease.version += 1
        LeaseV2MockEngine.recalculate(&lease, today: today)
        leases[leaseId] = lease
        return lease
    }

    /// `Idempotency-Key` semantics of spec §0: replay on the same key and body, reject a
    /// reused key with a different body.
    private func idempotent<Body: Encodable>(
        _ route: String,
        leaseId: String,
        request: Body,
        key: String,
        run: () async throws -> LeaseAggregate
    ) async throws -> LeaseAggregate {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fingerprint = route + "|" + (String(data: (try? encoder.encode(request)) ?? Data(), encoding: .utf8) ?? "")
        let storeKey = "\(leaseId)|\(key)"
        if let stored = replayStore[storeKey] {
            guard stored.fingerprint == fingerprint else { throw LeaseV2Error.idempotencyKeyReused }
            try await simulateLatency()
            commandLog.append("replay:\(route)")
            return stored.result
        }
        let result = try await run()
        replayStore[storeKey] = (fingerprint, result)
        return result
    }
}
