import Foundation

enum PropertyTenantRelationship: Equatable {
    case current
    case former
    case none
}

struct PropertyTenantSnippet: Equatable {
    let relationship: PropertyTenantRelationship
    let tenantId: String?
    let tenantName: String
    let relevantDate: String?
}

/// Коммуналка-сниппет показывает сумму последней квитанции, а не одну её строку.
/// Квитанция — это один документ за период; вода / свет / газ — её строки,
/// объединённые общим `sourceReceiptId`.
struct PropertyUtilitySnippet: Equatable {
    let amount: Double
    let currency: String
    let detail: String
    let receiptId: String?
    let lineCount: Int
}

struct PropertyListSnippetSummary {
    let tenant: PropertyTenantSnippet
    let payment: Transaction?
    let utility: PropertyUtilitySnippet?
}

enum PropertyListSnippetLogic {
    static func summary(
        property: Property,
        leases: [Lease],
        tenantsById: [String: Tenant],
        transactions: [Transaction],
        utilities: [PropertyUtility],
        today: String = isoDate(Date())
    ) -> PropertyListSnippetSummary {
        PropertyListSnippetSummary(
            tenant: tenantSnippet(
                property: property,
                leases: leases,
                tenantsById: tenantsById,
                today: today
            ),
            payment: latestIncome(transactions),
            utility: utilitySummary(utilities)
        )
    }

    static func tenantSnippet(
        property: Property,
        leases: [Lease],
        tenantsById: [String: Tenant],
        today: String
    ) -> PropertyTenantSnippet {
        let currentLease = leases
            .filter { isLeaseActive($0, today: today) }
            .sorted { leaseStart($0) > leaseStart($1) }
            .first

        // Occupancy is backend-owned. Lease dates only identify the tenant
        // attached to the status already returned on the property.
        if property.status.lowercased() != "vacant", let currentLease {
            return PropertyTenantSnippet(
                relationship: .current,
                tenantId: currentLease.tenantId,
                tenantName: tenantName(currentLease.tenantId, tenantsById: tenantsById),
                relevantDate: leaseStart(currentLease).nilIfBlank
            )
        }

        let lastLease = leases.sorted(by: latestLeaseFirst).first
        guard let lastLease else {
            return PropertyTenantSnippet(
                relationship: .none,
                tenantId: nil,
                tenantName: "Нет истории",
                relevantDate: nil
            )
        }

        return PropertyTenantSnippet(
            relationship: .former,
            tenantId: lastLease.tenantId,
            tenantName: tenantName(lastLease.tenantId, tenantsById: tenantsById),
            relevantDate: leaseEnd(lastLease)
        )
    }

    static func latestIncome(_ transactions: [Transaction]) -> Transaction? {
        transactions
            .filter { $0.type.lowercased() == "income" }
            .sorted {
                if $0.transactionDate == $1.transactionDate {
                    return $0.id > $1.id
                }
                return $0.transactionDate > $1.transactionDate
            }
            .first
    }

    static func latestUtility(_ utilities: [PropertyUtility]) -> PropertyUtility? {
        utilities.sorted {
            let leftPeriod = ($0.periodYear, $0.periodMonth)
            let rightPeriod = ($1.periodYear, $1.periodMonth)
            if leftPeriod != rightPeriod {
                return leftPeriod > rightPeriod
            }
            let leftDate = $0.paidAt ?? $0.dueDate ?? ""
            let rightDate = $1.paidAt ?? $1.dueDate ?? ""
            if leftDate == rightDate {
                return $0.id > $1.id
            }
            return leftDate > rightDate
        }.first
    }

    /// Сумма последней квитанции (всех её строк), а не одной записи. Строки
    /// группируются по `sourceReceiptId` и суммируются в валюте квитанции.
    /// Запись без квитанции (ручной ввод) показывается как одна строка.
    static func utilitySummary(_ utilities: [PropertyUtility]) -> PropertyUtilitySnippet? {
        guard let latest = latestUtility(utilities) else { return nil }

        let period = utilityPeriodLabel(year: latest.periodYear, month: latest.periodMonth)
        let receiptId = latest.sourceReceiptId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank

        if let receiptId {
            let lines = utilities.filter { utility in
                let id = utility.sourceReceiptId?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfBlank
                return id == receiptId && utility.currency == latest.currency
            }
            let total = lines.reduce(0) { $0 + $1.amount }
            let providers = Set(
                lines.compactMap {
                    $0.provider?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                }
            )
            let provider = providers.count == 1 ? providers.first : nil
            let detail: String
            if lines.count == 1 {
                let type = utilityTypeLabel(latest.utilityType)
                detail = provider.map { "\(type) · \($0) · \(period)" } ?? "\(type) · \(period)"
            } else {
                detail = provider.map { "\($0) · \(period)" } ?? period
            }
            return PropertyUtilitySnippet(
                amount: total,
                currency: latest.currency,
                detail: detail,
                receiptId: receiptId,
                lineCount: lines.count
            )
        }

        let type = utilityTypeLabel(latest.utilityType)
        let provider = latest.provider?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
        let detail = provider.map { "\(type) · \($0) · \(period)" } ?? "\(type) · \(period)"
        return PropertyUtilitySnippet(
            amount: latest.amount,
            currency: latest.currency,
            detail: detail,
            receiptId: nil,
            lineCount: 1
        )
    }

    static func utilityTypeLabel(_ type: String) -> String {
        switch type {
        case "utilities": return "Коммуналка"
        case "electricity": return "Электричество"
        case "cold_water": return "Холодная вода"
        case "hot_water": return "Горячая вода"
        case "water": return "Вода"
        case "water_disposal": return "Водоотведение"
        case "gas": return "Газ"
        case "heating": return "Отопление"
        case "maintenance": return "Содержание"
        case "elevator": return "Лифт"
        case "garbage", "waste": return "Вывоз мусора"
        case "internet": return "Интернет"
        case "other": return "Другое"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func utilityPeriodLabel(year: Int, month: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return String(format: "%02d.%d", month, year)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }

    private static func isLeaseActive(_ lease: Lease, today: String) -> Bool {
        let status = lease.status.lowercased()
        if status == "active" { return true }
        if ["terminated", "expired", "ended", "cancelled"].contains(status) { return false }
        let start = leaseStart(lease)
        let end = leaseEnd(lease)
        return !start.isEmpty && start <= today && (end == nil || end! >= today)
    }

    private static func latestLeaseFirst(_ left: Lease, _ right: Lease) -> Bool {
        let leftEnd = leaseEnd(left) ?? ""
        let rightEnd = leaseEnd(right) ?? ""
        if leftEnd != rightEnd { return leftEnd > rightEnd }
        return leaseStart(left) > leaseStart(right)
    }

    private static func leaseStart(_ lease: Lease) -> String {
        lease.moveInDate ?? lease.startDate
    }

    private static func leaseEnd(_ lease: Lease) -> String? {
        lease.terminatedAt ?? lease.endDate
    }

    private static func tenantName(
        _ tenantId: String,
        tenantsById: [String: Tenant]
    ) -> String {
        guard let tenant = tenantsById[tenantId], !tenant.displayName.isEmpty else {
            return "Арендатор"
        }
        return tenant.displayName
    }

    nonisolated private static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
