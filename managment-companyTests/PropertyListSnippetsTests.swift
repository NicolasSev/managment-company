import Foundation
import Testing
@testable import managment_company

@MainActor
@Suite(.serialized)
struct PropertyListSnippetsTests {
    @Test func propertyArchiveLifecycleDecodesWithoutChangingOperationalStatus() throws {
        let active = try JSONDecoder().decode(
            Property.self,
            from: Data(#"{"id":"active","name":"Active","property_type":"apartment","status":"occupied","archived_at":null}"#.utf8)
        )
        let archived = try JSONDecoder().decode(
            Property.self,
            from: Data(#"{"id":"archived","name":"Archived","property_type":"apartment","status":"occupied","archived_at":"2026-06-13T10:00:00Z"}"#.utf8)
        )
        let legacy = try JSONDecoder().decode(
            Property.self,
            from: Data(#"{"id":"legacy","name":"Legacy","property_type":"apartment","status":"archived"}"#.utf8)
        )

        #expect(active.isArchived == false)
        #expect(archived.isArchived)
        #expect(archived.status == "occupied")
        #expect(legacy.isArchived)
    }

    @Test func occupiedPropertyUsesActiveLeaseAsCurrentTenant() {
        let tenant = makeTenant(id: "tenant-a", firstName: "Анна")
        let snippet = PropertyListSnippetLogic.tenantSnippet(
            property: makeProperty(status: "occupied"),
            leases: [makeLease(tenantId: tenant.id, status: "active")],
            tenantsById: [tenant.id: tenant],
            today: "2026-06-12"
        )

        #expect(snippet.relationship == .current)
        #expect(snippet.tenantId == tenant.id)
        #expect(snippet.tenantName == "Анна")
        #expect(snippet.relevantDate == "2026-05-01")
    }

    @Test func vacantPropertyNeverPromotesStaleActiveLeaseToCurrent() {
        let tenant = makeTenant(id: "tenant-a", firstName: "Анна")
        let snippet = PropertyListSnippetLogic.tenantSnippet(
            property: makeProperty(status: "vacant"),
            leases: [makeLease(tenantId: tenant.id, status: "active")],
            tenantsById: [tenant.id: tenant],
            today: "2026-06-12"
        )

        #expect(snippet.relationship == .former)
        #expect(snippet.tenantId == tenant.id)
        #expect(snippet.tenantName == "Анна")
    }

    @Test func latestPaymentUsesNewestIncomeAndKeepsTargetId() {
        let transactions = [
            makeTransaction(id: "income-old", type: "income", date: "2026-05-10", amount: 100),
            makeTransaction(id: "expense-new", type: "expense", date: "2026-06-12", amount: 999),
            makeTransaction(id: "income-new", type: "income", date: "2026-06-11", amount: 200),
        ]

        let payment = PropertyListSnippetLogic.latestIncome(transactions)

        #expect(payment?.id == "income-new")
        #expect(payment?.amount == 200)
    }

    @Test func latestUtilityUsesPeriodThenDateAndKeepsReceiptTarget() {
        let utilities = [
            makeUtility(
                id: "may",
                year: 2026,
                month: 5,
                paidAt: "2026-06-30",
                receiptId: "receipt-old"
            ),
            makeUtility(
                id: "june-early",
                year: 2026,
                month: 6,
                paidAt: "2026-06-05",
                receiptId: nil
            ),
            makeUtility(
                id: "june-late",
                year: 2026,
                month: 6,
                paidAt: "2026-06-10",
                receiptId: "receipt-new"
            ),
        ]

        let utility = PropertyListSnippetLogic.latestUtility(utilities)

        #expect(utility?.id == "june-late")
        #expect(utility?.sourceReceiptId == "receipt-new")
        #expect(PropertyListSnippetLogic.utilityTypeLabel("cold_water") == "Холодная вода")
    }

    @Test func utilitySummarySumsAllLinesOfLatestReceipt() {
        let utilities = [
            makeUtility(
                id: "may", year: 2026, month: 5, paidAt: "2026-05-30",
                receiptId: "receipt-may", amount: 9999, utilityType: "utilities"
            ),
            makeUtility(
                id: "june-water", year: 2026, month: 6, paidAt: "2026-06-10",
                receiptId: "receipt-june", amount: 1155, utilityType: "cold_water"
            ),
            makeUtility(
                id: "june-power", year: 2026, month: 6, paidAt: "2026-06-09",
                receiptId: "receipt-june", amount: 8200, utilityType: "electricity"
            ),
            makeUtility(
                id: "june-gas", year: 2026, month: 6, paidAt: "2026-06-08",
                receiptId: "receipt-june", amount: 1300, utilityType: "gas"
            ),
        ]

        let summary = PropertyListSnippetLogic.utilitySummary(utilities)

        #expect(summary?.receiptId == "receipt-june")
        #expect(summary?.amount == 10_655.0)
        #expect(summary?.lineCount == 3)
        #expect(summary?.detail == "Алсеко · июнь 2026")
    }

    @Test func utilitySummaryKeepsTypeDetailForSingleLineReceipt() {
        let utilities = [
            makeUtility(
                id: "june", year: 2026, month: 6, paidAt: "2026-06-10",
                receiptId: "receipt-june", amount: 15253,
                utilityType: "utilities", provider: "АЛСЕКО"
            ),
        ]

        let summary = PropertyListSnippetLogic.utilitySummary(utilities)

        #expect(summary?.amount == 15253)
        #expect(summary?.receiptId == "receipt-june")
        #expect(summary?.lineCount == 1)
        #expect(summary?.detail == "Коммуналка · АЛСЕКО · июнь 2026")
    }

    @Test func utilitySummaryShowsSingleLineForManualRecordWithoutReceipt() {
        let utilities = [
            makeUtility(
                id: "june", year: 2026, month: 6, paidAt: "2026-06-10",
                receiptId: nil, amount: 4200,
                utilityType: "electricity", provider: "АЖК"
            ),
        ]

        let summary = PropertyListSnippetLogic.utilitySummary(utilities)

        #expect(summary?.amount == 4200)
        #expect(summary?.receiptId == nil)
        #expect(summary?.lineCount == 1)
        #expect(summary?.detail == "Электричество · АЖК · июнь 2026")
    }

    @Test func utilitySummaryIsNilWhenNoRecords() {
        #expect(PropertyListSnippetLogic.utilitySummary([]) == nil)
    }

    private func makeProperty(status: String) -> Property {
        Property(
            id: "property-a",
            name: "Квартира",
            propertyType: "apartment",
            country: "KZ",
            city: "Almaty",
            address: "Абая 1",
            district: nil,
            areaSqm: 50,
            rooms: 2,
            floor: 3,
            purchaseDate: nil,
            purchasePrice: nil,
            purchaseCurrency: nil,
            currentValue: nil,
            currentValueCurrency: nil,
            status: status,
            notes: nil,
            tags: nil,
            utilityAccountNumber: nil,
            wifiLogin: nil,
            wifiPassword: nil
        )
    }

    private func makeTenant(id: String, firstName: String) -> Tenant {
        Tenant(
            id: id,
            firstName: firstName,
            lastName: nil,
            phone: nil,
            email: nil,
            cohabitants: nil,
            notes: nil
        )
    }

    private func makeLease(tenantId: String, status: String) -> Lease {
        Lease(
            id: "lease-a",
            propertyId: "property-a",
            propertyName: "Квартира",
            tenantId: tenantId,
            startDate: "2026-05-01",
            endDate: nil,
            moveInDate: nil,
            rentAmount: 100,
            rentCurrency: "KZT",
            depositAmount: nil,
            depositCurrency: nil,
            paymentDay: 5,
            paymentWindowStartDay: nil,
            paymentWindowEndDay: nil,
            paymentDueDay: 5,
            status: status,
            terminatedAt: nil,
            terminationReason: nil,
            notes: nil,
            renewalReminderDays: nil,
            autoRenew: nil,
            utilitiesPaidBy: nil
        )
    }

    private func makeTransaction(
        id: String,
        type: String,
        date: String,
        amount: Double
    ) -> Transaction {
        Transaction(
            id: id,
            propertyId: "property-a",
            type: type,
            categoryId: "category-a",
            amount: amount,
            currency: "KZT",
            amountBase: amount,
            exchangeRate: nil,
            transactionDate: date,
            periodYear: 2026,
            periodMonth: 6,
            description: nil,
            tenantId: nil,
            leaseId: nil
        )
    }

    private func makeUtility(
        id: String,
        year: Int,
        month: Int,
        paidAt: String?,
        receiptId: String?,
        amount: Double = 5000,
        utilityType: String = "cold_water",
        provider: String? = "Алсеко",
        currency: String = "KZT"
    ) -> PropertyUtility {
        PropertyUtility(
            id: id,
            propertyId: "property-a",
            propertyName: "Квартира",
            leaseId: nil,
            periodYear: year,
            periodMonth: month,
            utilityType: utilityType,
            provider: provider,
            amount: amount,
            currency: currency,
            dueDate: "2026-06-15",
            paidAt: paidAt,
            status: "paid",
            notes: nil,
            receiptFileId: nil,
            sourceReceiptId: receiptId,
            ocrStatus: nil,
            ocrConfidence: nil,
            ocrRawText: nil,
            ocrProcessedAt: nil
        )
    }
}
