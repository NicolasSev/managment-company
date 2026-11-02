import Foundation

// `GET /v1/analytics/utilities/comparison` (year over year). Money is in the base currency.

struct UtilityComparisonTotals: Codable, Hashable {
    let current: Decimal
    let previous: Decimal
    let deltaAbs: Decimal
    let deltaPct: Double?
    let mixedUnits: Bool?
    let unit: String?

    enum CodingKeys: String, CodingKey {
        case current, previous, unit
        case deltaAbs = "delta_abs"
        case deltaPct = "delta_pct"
        case mixedUnits = "mixed_units"
    }
}

struct UtilityComparisonRow: Codable, Hashable, Identifiable {
    let key: String
    let current: Decimal
    let previous: Decimal
    let deltaAbs: Decimal
    let deltaPct: Double?
    let unit: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, current, previous, unit
        case deltaAbs = "delta_abs"
        case deltaPct = "delta_pct"
    }
}

struct UtilityComparisonCoverage: Codable, Hashable {
    let monthsWithBill: Int
    let missingMonths: [String]

    enum CodingKeys: String, CodingKey {
        case monthsWithBill = "months_with_bill"
        case missingMonths = "missing_months"
    }
}

struct UtilityComparisonProperty: Codable, Hashable, Identifiable {
    let propertyId: String
    let propertyName: String
    let areaSqm: Double?
    let totals: UtilityComparisonTotals
    let rows: [UtilityComparisonRow]
    let typeRows: [UtilityComparisonRow]
    let coverage: UtilityComparisonCoverage

    var id: String { propertyId }

    enum CodingKeys: String, CodingKey {
        case totals, rows, coverage
        case propertyId = "property_id"
        case propertyName = "property_name"
        case areaSqm = "area_sqm"
        case typeRows = "type_rows"
    }
}

struct UtilityComparison: Codable, Hashable {
    let baseCurrency: String
    let year: Int
    let compareYear: Int
    let groupBy: String
    let metric: String
    let perSqm: Bool
    let totals: UtilityComparisonTotals
    let rows: [UtilityComparisonRow]
    let typeRows: [UtilityComparisonRow]
    let coverage: UtilityComparisonCoverage
    let byProperty: [UtilityComparisonProperty]
    let unconvertedLines: Int

    enum CodingKeys: String, CodingKey {
        case year, metric, totals, rows, coverage
        case baseCurrency = "base_currency"
        case compareYear = "compare_year"
        case groupBy = "group_by"
        case perSqm = "per_sqm"
        case typeRows = "type_rows"
        case byProperty = "by_property"
        case unconvertedLines = "unconverted_lines"
    }
}
