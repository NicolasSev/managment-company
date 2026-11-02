//
//  TenantsTabTests.swift
//  managment-companyTests
//
//  L13: typed API errors, the live lease service mapping, the tenant overview screen state,
//  the tenant edit round trip (PUT replaces the whole record) and the property lease card.
//  Canonical source: apps/ios/PropManager/Tests (mirrored by `make ios-sync`).
//

import Foundation
import Testing
@testable import managment_company

private func json(_ text: String) -> Data { Data(text.utf8) }

@MainActor
private final class FakeTenantClient: TenantClient {
    var overview: TenantOverview?
    var stored: Tenant?
    var overviewError: Error?
    var saveError: Error?
    var overviewCalls = 0
    var saved: [(id: String?, body: TenantUpsertBody)] = []
    var deleted: [String] = []
    var deleteError: Error?

    func fetchOverview(tenantId: String, months: Int) async throws -> TenantOverview {
        overviewCalls += 1
        if let overviewError { throw overviewError }
        return overview!
    }

    func fetchTenant(id: String) async throws -> Tenant {
        guard let stored else { throw APIError.httpStatus(404) }
        return stored
    }

    func saveTenant(id: String?, body: TenantUpsertBody) async throws -> Tenant {
        if let saveError { throw saveError }
        saved.append((id, body))
        return stored!
    }

    func deleteTenant(id: String) async throws {
        if let deleteError { throw deleteError }
        deleted.append(id)
    }
}

private func fullTenant() -> Tenant {
    Tenant(
        id: "a52d7e19-0c64-4f1b-8e3a-9b7f2c6d4e21",
        firstName: "Айгерим",
        lastName: "Касымова",
        phone: "+7 701 555 12 34",
        email: "aigerim@example.kz",
        cohabitants: "Супруг",
        notes: nil,
        middleName: "Нурлановна",
        iin: "950312401236",
        documentType: "id_card",
        documentNumber: "041177203",
        documentIssuedBy: "МВД РК",
        documentIssuedAt: "2020-01-10",
        birthDate: "1995-03-12",
        registrationAddress: "г. Алматы, мкр. Орбита-1, д. 12"
    )
}

// MARK: - Typed API errors

@Suite(.serialized)
struct APIErrorBodyTests {

    @Test func parsesTheErrorEnvelope() {
        let body = APIErrorBody.parse(json(#"{"error":{"code":"VERSION_MISMATCH","message":"stale","details":{"current_version":7}}}"#))
        #expect(body?.code == "VERSION_MISMATCH")
        #expect(body?.message == "stale")
        #expect(body?.detail("current_version") == .number(7))
    }

    @Test func rejectsBodiesThatAreNotTheEnvelope() {
        #expect(APIErrorBody.parse(Data()) == nil)
        #expect(APIErrorBody.parse(json("<html>502</html>")) == nil)
        #expect(APIErrorBody.parse(json(#"{"data":{}}"#)) == nil)
    }

    @Test func fieldValidationDetails() {
        let body = APIErrorBody.parse(json(#"{"error":{"code":"VALIDATION_ERROR","message":"validation failed","details":[{"field":"iin","message":"bad checksum"}]}}"#))
        #expect(body?.firstFieldError?.field == "iin")
        #expect(body?.firstFieldError?.message == "bad checksum")
    }

    @Test func typedErrorsAreOptIn() {
        let data = json(#"{"error":{"code":"USE_AMENDMENT","message":"m"}}"#)
        guard case .httpStatus(422) = APIError.make(status: 422, body: data, typed: false) else {
            Issue.record("legacy callers must keep receiving .httpStatus")
            return
        }
        guard case .server(let status, let body) = APIError.make(status: 422, body: data, typed: true) else {
            Issue.record("typed callers must receive .server")
            return
        }
        #expect(status == 422)
        #expect(body.code == "USE_AMENDMENT")
    }

    @Test func typedRequestFallsBackToTheStatusWithoutAnEnvelope() {
        guard case .httpStatus(502) = APIError.make(status: 502, body: json("bad gateway"), typed: true) else {
            Issue.record("a non-envelope body must stay .httpStatus")
            return
        }
    }

    @Test func statusCodeCoversBothCases() {
        #expect(APIError.httpStatus(409).statusCode == 409)
        #expect(APIError.server(status: 412, error: APIErrorBody(code: "VERSION_MISMATCH", message: nil, details: nil)).statusCode == 412)
        #expect(APIError.unauthorized.statusCode == nil)
    }
}

// MARK: - Live lease service mapping

@Suite(.serialized)
struct LiveLeaseV2MappingTests {

    private func server(_ status: Int, _ code: String, details: JSONValue? = nil) -> LeaseV2Error {
        LiveLeaseV2Service.map(APIError.server(status: status, error: APIErrorBody(code: code, message: nil, details: details)))
    }

    @Test func versionMismatchCarriesTheCurrentVersion() {
        #expect(server(412, "VERSION_MISMATCH", details: .object(["current_version": .number(9)])) == .versionMismatch(currentVersion: 9))
    }

    @Test func invalidTransitionCarriesTheCommand() {
        let mapped = server(422, "INVALID_STATE_TRANSITION", details: .object(["command": .string("terminate")]))
        #expect(mapped == .invalidStateTransition(command: "terminate"))
    }

    @Test func domainCodes() {
        #expect(server(409, "LEASE_OVERLAP") != .conflict(message: "Действие конфликтует с текущим состоянием договора."))
        if case .conflict = server(409, "LEASE_OVERLAP") {} else { Issue.record("LEASE_OVERLAP is a conflict") }
        if case .validation = server(422, "USE_AMENDMENT") {} else { Issue.record("USE_AMENDMENT is a validation error") }
        #expect(server(422, "AMOUNT_EXCEEDS_OUTSTANDING") == .chargeNotPayable)
        #expect(server(422, "CHARGE_NOT_OPEN") == .chargeNotPayable)
        #expect(server(422, "IDEMPOTENCY_KEY_REUSED") == .idempotencyKeyReused)
        #expect(server(422, "DEPOSIT_BALANCE_EXCEEDED") == .depositBalanceExceeded(held: nil))
    }

    @Test func unknownCodeFallsBackToTheStatus() {
        #expect(server(412, "SOMETHING_NEW") == .versionMismatch(currentVersion: nil))
        #expect(server(404, "SOMETHING_NEW") == .notFound)
        #expect(server(503, "SOMETHING_NEW") == .transport)
    }

    @Test func plainStatusStillMaps() {
        #expect(LiveLeaseV2Service.map(APIError.httpStatus(412)) == .versionMismatch(currentVersion: nil))
        #expect(LiveLeaseV2Service.map(APIError.unauthorized) == .unauthorized)
        #expect(LiveLeaseV2Service.map(URLError(.notConnectedToInternet)) == .transport)
    }

    @MainActor
    @Test func liveServiceIsTheDefaultAndMocksAreOptIn() {
        let saved = LeaseV2ServiceProvider.useMocks
        defer { LeaseV2ServiceProvider.useMocks = saved }
        let auth = AuthManager()

        LeaseV2ServiceProvider.useMocks = false
        #expect(LeaseV2ServiceProvider.makeService(authManager: auth) is LiveLeaseV2Service)

        LeaseV2ServiceProvider.useMocks = true
        #expect(LeaseV2ServiceProvider.makeService(authManager: auth) is MockLeaseV2Service)
    }
}

// MARK: - Tenant edit (round trip)

@Suite(.serialized)
struct TenantEditTests {

    @Test func untouchedFormSendsEveryStoredField() {
        let body = TenantEditForm(tenant: fullTenant()).body()
        #expect(body.iin == "950312401236")
        #expect(body.documentType == "id_card")
        #expect(body.documentNumber == "041177203")
        #expect(body.documentIssuedBy == "МВД РК")
        #expect(body.documentIssuedAt == "2020-01-10")
        #expect(body.birthDate == "1995-03-12")
        #expect(body.registrationAddress == "г. Алматы, мкр. Орбита-1, д. 12")
        #expect(body.middleName == "Нурлановна")
        #expect(body.cohabitants == "Супруг")
    }

    @Test func bodyEncodesTheWireKeys() throws {
        let data = try JSONEncoder().encode(TenantEditForm(tenant: fullTenant()).body())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["first_name", "middle_name", "iin", "document_type", "document_number",
                    "document_issued_by", "document_issued_at", "birth_date", "registration_address"] {
            #expect(object[key] != nil, "missing \(key)")
        }
    }

    @Test func clearingAFieldOmitsIt() {
        var form = TenantEditForm(tenant: fullTenant())
        form.phone = "   "
        #expect(form.body().phone == nil)
        #expect(form.body().iin == "950312401236")
    }

    @Test func firstNameIsRequired() {
        var form = TenantEditForm(tenant: fullTenant())
        form.firstName = " "
        #expect(!form.canSubmit)
    }

    @MainActor
    @Test func saveSendsPutWithTheFullBody() async {
        let client = FakeTenantClient()
        client.stored = fullTenant()
        let viewModel = TenantEditViewModel(tenant: fullTenant())
        viewModel.form.phone = "+7 700 000 00 00"

        #expect(await viewModel.save(client: client))
        #expect(client.saved.count == 1)
        #expect(client.saved[0].id == fullTenant().id)
        #expect(client.saved[0].body.phone == "+7 700 000 00 00")
        #expect(client.saved[0].body.iin == "950312401236")
        #expect(client.saved[0].body.documentIssuedBy == "МВД РК")
    }

    @MainActor
    @Test func createUsesNoId() async {
        let client = FakeTenantClient()
        client.stored = fullTenant()
        let viewModel = TenantEditViewModel(tenant: nil)
        viewModel.form.firstName = "Новый"
        #expect(await viewModel.save(client: client))
        #expect(client.saved[0].id == nil)
    }

    @MainActor
    @Test func serverValidationErrorNamesTheField() async {
        let client = FakeTenantClient()
        client.saveError = APIError.server(
            status: 400,
            error: APIErrorBody(
                code: "VALIDATION_ERROR",
                message: "validation failed",
                details: .array([.object(["field": .string("iin"), "message": .string("bad")])])
            )
        )
        let viewModel = TenantEditViewModel(tenant: fullTenant())
        #expect(await viewModel.save(client: client) == false)
        #expect(viewModel.errorMessage?.contains("ИИН") == true)
    }

    @MainActor
    @Test func duplicateIinIsExplained() async {
        let client = FakeTenantClient()
        client.saveError = APIError.server(status: 409, error: APIErrorBody(code: "CONFLICT", message: nil, details: nil))
        let viewModel = TenantEditViewModel(tenant: fullTenant())
        #expect(await viewModel.save(client: client) == false)
        #expect(viewModel.errorMessage == "Арендатор с таким ИИН уже есть.")
    }

    @Test func documentLine() {
        #expect(TenantDetailView.documentLine(type: "passport", number: "N1", issuedBy: "МВД", issuedAt: nil) == "Паспорт N1, выдан МВД")
        #expect(TenantDetailView.documentLine(type: nil, number: nil, issuedBy: nil, issuedAt: nil) == nil)
    }
}

// MARK: - Tenant screen state

@Suite(.serialized)
struct TenantDetailViewModelTests {

    @MainActor
    private func makeLoaded() async throws -> (TenantDetailViewModel, FakeTenantClient) {
        let client = FakeTenantClient()
        client.overview = try LeaseV2Fixtures.tenantOverview()
        client.stored = fullTenant()
        let viewModel = TenantDetailViewModel(tenantId: fullTenant().id, client: client)
        await viewModel.load()
        return (viewModel, client)
    }

    @MainActor
    @Test func loadsTheOverview() async throws {
        let (viewModel, _) = try await makeLoaded()
        let overview = try #require(viewModel.overview)
        #expect(overview.currentLease?.status == .active)
        #expect(viewModel.displayName == overview.tenant.fullName)
        #expect(viewModel.tenant?.documentIssuedBy == "МВД РК")
        #expect(viewModel.activeLeaseCount == 1)
    }

    @MainActor
    @Test func monthsWithoutChargesAreHiddenAndNewestFirst() async throws {
        let (viewModel, _) = try await makeLoaded()
        let periods = viewModel.monthRows.map(\.month.period)
        #expect(!periods.contains("2027-02"))
        #expect(periods.first == "2027-01")
        #expect(periods == periods.sorted(by: >))
    }

    @MainActor
    @Test func historyExcludesTheCurrentLease() async throws {
        let (viewModel, _) = try await makeLoaded()
        #expect(viewModel.historyLeases.isEmpty)
    }

    @MainActor
    @Test func totalsFollowTheCurrentLeaseCurrency() async throws {
        let (viewModel, _) = try await makeLoaded()
        #expect(viewModel.primaryTotals?.currency == "KZT")
        #expect(viewModel.primaryTotals?.outstanding.isPositive == true)
    }

    @MainActor
    @Test func firstLoadFailureShowsTheError() async {
        let client = FakeTenantClient()
        client.overviewError = URLError(.notConnectedToInternet)
        let viewModel = TenantDetailViewModel(tenantId: "x", client: client)
        await viewModel.load()
        #expect(viewModel.state == .error("Не удалось загрузить арендатора."))
    }

    @MainActor
    @Test func reloadFailureKeepsTheScreenAndShowsABanner() async throws {
        let (viewModel, client) = try await makeLoaded()
        client.overviewError = URLError(.timedOut)
        await viewModel.load()
        #expect(viewModel.overview != nil)
        #expect(viewModel.banner != nil)
    }

    @MainActor
    @Test func editingStartsFromAFreshRecord() async throws {
        let (viewModel, client) = try await makeLoaded()
        var changed = fullTenant()
        changed.documentIssuedBy = "Новый орган"
        client.stored = changed
        let tenant = await viewModel.tenantForEditing()
        #expect(tenant?.documentIssuedBy == "Новый орган")
    }

    @MainActor
    @Test func editingFailsWithABannerWhenTheRecordIsUnavailable() async throws {
        let (viewModel, client) = try await makeLoaded()
        client.stored = nil
        #expect(await viewModel.tenantForEditing() == nil)
        #expect(viewModel.banner != nil)
    }

    @MainActor
    @Test func deleteCallsTheClient() async throws {
        let (viewModel, client) = try await makeLoaded()
        #expect(await viewModel.delete())
        #expect(client.deleted == [fullTenant().id])
    }

    @MainActor
    @Test func deleteFailureKeepsTheScreen() async throws {
        let (viewModel, client) = try await makeLoaded()
        client.deleteError = APIError.httpStatus(500)
        #expect(await viewModel.delete() == false)
        #expect(viewModel.banner == "Не удалось удалить арендатора.")
    }

    @Test func monthTitleIsRussian() {
        #expect(TenantDetailView.monthTitle("2026-10") == "Октябрь 2026")
        #expect(TenantDetailView.monthTitle("bad") == "bad")
    }
}

// MARK: - Property lease card

@MainActor
@Suite(.serialized)
struct PropertyCurrentLeaseTests {

    private func card(_ id: String, _ status: String, start: String) throws -> LeaseCard {
        let text = """
        {"id":"\(id)","status":"\(status)","property":{"id":"p1","name":"Квартира"},
         "tenant":{"id":"t1","first_name":"Анна","last_name":null,"middle_name":null,"full_name":"Анна","phone":null,"email":null,"iin":null},
         "start_date":"\(start)","end_date":null,"activation_date":null,"move_out_date":null,
         "current_rent_amount":100000,"rent_currency":"KZT","due_day":1,"prolongation_count":0,
         "ends_in_days":null,"is_ending_soon":false,
         "balance":{"currency":"KZT","outstanding":0,"overdue":0,"tenant_credit":0,"next_charge":null},
         "deposit":{"amount":0,"held":0,"status":"none"},"available_actions":[]}
        """
        return try JSONDecoder().decode(LeaseCard.self, from: json(text))
    }

    @Test func summaryDecodesAsALeaseCardWithItsTenant() throws {
        let lease = try card("l1", "active", start: "2026-01-01")
        #expect(lease.tenant?.fullName == "Анна")
    }

    @Test func activeWinsOverPendingAndDraft() throws {
        let leases = [
            try card("draft", "draft", start: "2026-09-01"),
            try card("pending", "pending_signature", start: "2026-08-01"),
            try card("active", "active", start: "2026-01-01"),
        ]
        #expect(PropertyCurrentLeaseViewModel.current(from: leases)?.id == "active")
    }

    @Test func latestStartWinsInsideAStatus() throws {
        let leases = [
            try card("old", "active", start: "2025-01-01"),
            try card("new", "active", start: "2026-01-01"),
        ]
        #expect(PropertyCurrentLeaseViewModel.current(from: leases)?.id == "new")
    }

    @Test func closedLeasesAreNotCurrent() throws {
        let leases = [try card("done", "ended", start: "2024-01-01")]
        #expect(PropertyCurrentLeaseViewModel.current(from: leases) == nil)
    }

    @MainActor
    @Test func viewModelLoadsAndKeepsTheCardOnAFailedRefresh() async throws {
        final class Client: PropertyLeasesClient {
            var leases: [LeaseCard] = []
            var fail = false
            func fetchOpenLeases(propertyId: String) async throws -> [LeaseCard] {
                if fail { throw URLError(.timedOut) }
                return leases
            }
        }
        let client = Client()
        client.leases = [try card("l1", "active", start: "2026-01-01")]
        let viewModel = PropertyCurrentLeaseViewModel(propertyId: "p1", client: client)
        await viewModel.load()
        #expect(viewModel.lease?.id == "l1")

        client.fail = true
        await viewModel.load()
        #expect(viewModel.lease?.id == "l1")
    }

    @MainActor
    @Test func firstFailureShowsTheError() async {
        struct Failing: PropertyLeasesClient {
            func fetchOpenLeases(propertyId: String) async throws -> [LeaseCard] { throw URLError(.timedOut) }
        }
        let viewModel = PropertyCurrentLeaseViewModel(propertyId: "p1", client: Failing())
        await viewModel.load()
        #expect(viewModel.state == .error)
    }
}
