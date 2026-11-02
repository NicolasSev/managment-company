//
//  LeaseV2ContractTests.swift
//  managment-companyTests
//
//  Lease v2 (tasks L8, L8b): the hand-written Codable models are checked against the generated contract
//  (packages/api-contracts/openapi.ios-codegen.json, built from the Go swag annotations by
//  `make contracts`; `make ios-contract-fixtures` copies it next to the fixtures).
//
//  Swift codegen is not adopted (AGENTS_CONTRACT.md: curated Core/Models stay), so this is the
//  guard that keeps them identical to the contract:
//    1. the fixtures conform to the schemas (keys, required, nullability, enums, formats);
//    2. every wire field of a fixture is read by the model, except the ones listed in
//       `intentionallyIgnored` (deprecated v1 aliases and similar) - found by mutating each leaf
//       of the fixture and checking that the decoded value changes;
//    3. the enum cases the app knows are exactly the values of the contract enums.
//
//  L8b adds the settle answer and the contract generation payloads (templates, landlord profile,
//  generate answer, the 422 CONTRACT_DATA_INCOMPLETE body) to the same checks. The settle request
//  has no Swift model yet (T3c / L14): its fixture is only checked against the schema.
//

import Foundation
import Testing
@testable import managment_company

// MARK: - Schema access

private final class ContractBundleToken {}

private enum Contract {
    static let schemas: [String: Any] = {
        let bundles = [Bundle(for: ContractBundleToken.self), Bundle.main] + Bundle.allBundles
        for bundle in bundles {
            for subdirectory in [nil, "Fixtures"] as [String?] {
                if let url = bundle.url(forResource: "openapi.ios-codegen", withExtension: "json", subdirectory: subdirectory),
                   let data = try? Data(contentsOf: url),
                   let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let components = root["components"] as? [String: Any],
                   let schemas = components["schemas"] as? [String: Any] {
                    return schemas
                }
            }
        }
        return [:]
    }()

    static func schema(_ name: String) -> [String: Any] {
        schemas[name] as? [String: Any] ?? [:]
    }

    /// Follows `$ref` and merges `allOf` (the generator wraps nullable refs in `allOf`).
    static func resolve(_ node: [String: Any]) -> [String: Any] {
        var merged: [String: Any] = [:]
        if let ref = node["$ref"] as? String, let name = ref.split(separator: "/").last {
            merged = resolve(schema(String(name)))
        }
        for part in node["allOf"] as? [[String: Any]] ?? [] {
            for (key, value) in resolve(part) {
                if key == "properties", let new = value as? [String: Any], let old = merged[key] as? [String: Any] {
                    merged[key] = old.merging(new) { $1 }
                } else if key == "required", let new = value as? [String], let old = merged[key] as? [String] {
                    merged[key] = old + new
                } else {
                    merged[key] = value
                }
            }
        }
        for (key, value) in node where key != "$ref" && key != "allOf" {
            merged[key] = value
        }
        return merged
    }

    static func enumValues(_ name: String) -> Set<String> {
        Set(schema(name)["enum"] as? [String] ?? [])
    }

    /// Values of an inline enum: `schema.properties.<property>`.
    static func propertyEnum(_ name: String, _ property: String) -> Set<String> {
        let properties = resolve(schema(name))["properties"] as? [String: Any] ?? [:]
        let node = resolve(properties[property] as? [String: Any] ?? [:])
        return Set(node["enum"] as? [String] ?? [])
    }
}

// MARK: - 1. Fixtures conform to the schemas

private func isBool(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
}

private func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

/// Returns the list of violations of `value` against `node` (an OpenAPI 3.0 schema).
private func violations(of value: Any, against node: [String: Any], path: String) -> [String] {
    let schema = Contract.resolve(node)
    if value is NSNull {
        return (schema["nullable"] as? Bool) == true ? [] : ["\(path): null where the contract is not nullable"]
    }
    let type = schema["type"] as? String
    var issues: [String] = []

    if let allowed = schema["enum"] as? [String] {
        if let text = value as? String, !allowed.contains(text) {
            issues.append("\(path): \"\(text)\" is not one of \(allowed)")
        }
    }

    switch type {
    case "object":
        guard let object = value as? [String: Any] else { return ["\(path): expected an object"] }
        if let properties = schema["properties"] as? [String: Any] {
            for (key, child) in object {
                guard let childSchema = properties[key] as? [String: Any] else {
                    issues.append("\(path).\(key): field is not in the contract")
                    continue
                }
                issues += violations(of: child, against: childSchema, path: "\(path).\(key)")
            }
            for key in schema["required"] as? [String] ?? [] where object[key] == nil {
                issues.append("\(path).\(key): required by the contract, missing")
            }
        }
    case "array":
        guard let array = value as? [Any] else { return ["\(path): expected an array"] }
        if let items = schema["items"] as? [String: Any] {
            for (index, element) in array.enumerated() {
                issues += violations(of: element, against: items, path: "\(path)[\(index)]")
            }
        }
    case "string":
        guard let text = value as? String else { return ["\(path): expected a string"] }
        switch schema["format"] as? String {
        case "date":
            if !matches(text, #"^\d{4}-\d{2}-\d{2}$"#) { issues.append("\(path): \"\(text)\" is not a date") }
        case "date-time":
            if !matches(text, #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"#) {
                issues.append("\(path): \"\(text)\" is not an RFC 3339 time")
            }
        default:
            break
        }
    case "integer":
        guard let number = value as? NSNumber, !isBool(value), number.doubleValue == number.doubleValue.rounded() else {
            return ["\(path): expected an integer"]
        }
    case "number":
        guard let number = value as? NSNumber, !isBool(value) else { return ["\(path): expected a number"] }
        if schema["format"] as? String == "decimal" {
            let cents = number.doubleValue * 100
            if abs(cents - cents.rounded()) > 1e-6 { issues.append("\(path): money with more than 2 decimals") }
        }
    case "boolean":
        if !isBool(value) { issues.append("\(path): expected a boolean") }
    default:
        break
    }
    return issues
}

// MARK: - 2. Models read every contract field

/// One decodable fixture: where it lives, the contract schema of the response and how to decode it.
private struct ContractCase {
    let fixture: String
    let schema: String
    /// Decodes the whole HTTP body; the result must change when a field the model reads changes.
    let decode: (Data) throws -> AnyHashable
    /// Wire paths (indices as `[]`, `*` = whole subtree) the app does not read on purpose.
    let intentionallyIgnored: Set<String>
}

/// Deprecated v1 aliases of the aggregate (spec §9.3): the flat v2 fields carry the same data.
private let deprecatedAggregateAliases: Set<String> = [
    "data.property_name", "data.move_in_date", "data.payment_day", "data.payment_due_day",
    "data.payment_window_start_day", "data.payment_window_end_day", "data.terminated_at", "data.auto_renew",
]

private let aggregateIgnored = aggregateIgnoredPaths(under: "data")

/// The exceptions of a lease aggregate that sits at `prefix` (the lease answer is `data`, the settle
/// and generate answers carry it at `data.lease`).
private func aggregateIgnoredPaths(under prefix: String) -> Set<String> {
    Set(aggregateIgnoredRelativeToData.map { prefix + $0.dropFirst("data".count) })
}

private let aggregateIgnoredRelativeToData = deprecatedAggregateAliases.union([
    // Free-form payloads: the app reads the keys it renders and ignores the rest (spec §2.3).
    "data.events[].payload.*",
    // Informational copies of the property / tenant at signing time, rendered partially.
    "data.tenant_snapshot.*", "data.property_snapshot.*",
    // Not shown by the lease screen: file ids/sizes of the attachment list, actor ids.
    "data.documents.files[].*",
])

private let cases: [ContractCase] = [
    ContractCase(
        fixture: "lease-aggregate.active",
        schema: "LeaseAggregateEnvelope",
        decode: { AnyHashable(try JSONDecoder().decode(APIResponse<LeaseAggregate>.self, from: $0).data) },
        intentionallyIgnored: aggregateIgnored
    ),
    ContractCase(
        fixture: "lease-aggregate.pending",
        schema: "LeaseAggregateEnvelope",
        decode: { AnyHashable(try JSONDecoder().decode(APIResponse<LeaseAggregate>.self, from: $0).data) },
        intentionallyIgnored: aggregateIgnored
    ),
    ContractCase(
        fixture: "settle-response",
        schema: "SettleEnvelope",
        decode: { AnyHashable(try JSONDecoder().decode(APIResponse<SettleResponse>.self, from: $0).data) },
        intentionallyIgnored: aggregateIgnoredPaths(under: "data.lease")
    ),
    ContractCase(
        fixture: "generate-response",
        schema: "ContractGeneratedEnvelope",
        decode: { AnyHashable(try JSONDecoder().decode(APIResponse<ContractGenerateResponse>.self, from: $0).data) },
        intentionallyIgnored: aggregateIgnoredPaths(under: "data.lease")
    ),
    ContractCase(
        fixture: "templates-list",
        schema: "DocumentTemplateListEnvelope",
        decode: { AnyHashable(try JSONDecoder().decode(APIResponse<[DocumentTemplate]>.self, from: $0).data) },
        intentionallyIgnored: []
    ),
    ContractCase(
        fixture: "landlord-profile",
        schema: "LandlordProfileEnvelope",
        decode: { AnyHashable(try JSONDecoder().decode(APIResponse<LandlordProfile>.self, from: $0).data) },
        intentionallyIgnored: []
    ),
    ContractCase(
        fixture: "contract-data-incomplete",
        schema: "ContractErrorEnvelope",
        decode: { AnyHashable(try JSONDecoder().decode(ContractErrorEnvelope.self, from: $0)) },
        intentionallyIgnored: []
    ),
    ContractCase(
        fixture: "tenant-overview",
        schema: "TenantOverviewEnvelope",
        decode: { AnyHashable(try JSONDecoder().decode(APIResponse<TenantOverview>.self, from: $0).data) },
        intentionallyIgnored: []
    ),
    ContractCase(
        fixture: "payment-queue",
        schema: "PaymentQueueEnvelope",
        decode: {
            let page = try JSONDecoder().decode(APIListEnvelope<LeaseQueueItem>.self, from: $0)
            return AnyHashable([AnyHashable(page.data), AnyHashable(page.page), AnyHashable(page.perPage), AnyHashable(page.total)])
        },
        // The v1 PaymentQueueItem fields that the v2 row repeats under new names (spec §9.6).
        intentionallyIgnored: [
            "data[].period_start_date", "data[].period_end_date", "data[].expected_amount", "data[].actual_payment_id",
            "data[].actual_amount", "data[].paid_to_date", "data[].remaining_amount", "data[].allocation_count",
            "data[].transaction_id", "data[].status",
        ]
    ),
]

/// Request bodies: no Swift model yet, checked against the schema only.
private let requestFixtures: [(fixture: String, schema: String)] = [
    ("settle-request", "SettleRequest"),
]

/// The lease v2 fixtures are bundled with the app; the contract/* ones only with the tests
/// (`make ios-contract-fixtures`), so the lookup also walks every loaded bundle.
private func fixtureData(_ name: String) throws -> Data {
    if let data = try? LeaseV2Fixtures.data(named: name) { return data }
    for bundle in [Bundle(for: ContractBundleToken.self), Bundle.main] + Bundle.allBundles {
        for subdirectory in [nil, "Fixtures"] as [String?] {
            if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: subdirectory) {
                return try Data(contentsOf: url)
            }
        }
    }
    throw LeaseV2Error.notFound
}

private func fixtureJSON(_ name: String) throws -> Any {
    try JSONSerialization.jsonObject(with: try fixtureData(name))
}

/// Leaf locations of a JSON value as key paths (`String` = object key, `Int` = array index).
private func leafPaths(_ value: Any, prefix: [Any] = []) -> [[Any]] {
    if let object = value as? [String: Any] {
        return object.keys.sorted().flatMap { leafPaths(object[$0]!, prefix: prefix + [$0]) }
    }
    if let array = value as? [Any] {
        return array.enumerated().flatMap { leafPaths($0.element, prefix: prefix + [$0.offset]) }
    }
    return [prefix]
}

private func normalized(_ path: [Any]) -> String {
    var text = ""
    for component in path {
        if let key = component as? String {
            text += text.isEmpty ? key : ".\(key)"
        } else {
            text += "[]"
        }
    }
    return text
}

private func mutated(_ root: Any, at path: ArraySlice<Any>) -> Any {
    guard let head = path.first else {
        if root is NSNull { return "~" }
        if isBool(root) { return !(root as! Bool) }
        if let number = root as? NSNumber { return number.doubleValue + 7 }
        if let text = root as? String { return text + "~" }
        return root
    }
    if let key = head as? String, var object = root as? [String: Any] {
        object[key] = mutated(object[key] as Any, at: path.dropFirst())
        return object
    }
    if let index = head as? Int, var array = root as? [Any] {
        array[index] = mutated(array[index], at: path.dropFirst())
        return array
    }
    return root
}

private func isCovered(_ path: String, by ignored: Set<String>) -> Bool {
    ignored.contains { entry in
        entry.hasSuffix(".*") ? path.hasPrefix(entry.dropLast(1)) : path == entry
    }
}

// MARK: - Tests

@MainActor
@Suite(.serialized)
struct LeaseV2ContractTests {
    @Test func schemaBundleIsPresent() {
        #expect(!Contract.schemas.isEmpty, "openapi.ios-codegen.json is missing: run `make ios-contract-fixtures`")
        #expect(Contract.schemas["LeaseAggregate"] != nil)
    }

    @Test func fixturesConformToContractSchemas() throws {
        for item in cases {
            let json = try fixtureJSON(item.fixture)
            let issues = violations(of: json, against: ["$ref": "#/components/schemas/\(item.schema)"], path: item.fixture)
            #expect(issues.isEmpty, "\(item.fixture) vs \(item.schema):\n\(issues.joined(separator: "\n"))")
        }
    }

    @Test func requestFixturesConformToContractSchemas() throws {
        for item in requestFixtures {
            let json = try fixtureJSON(item.fixture)
            let issues = violations(of: json, against: ["$ref": "#/components/schemas/\(item.schema)"], path: item.fixture)
            #expect(issues.isEmpty, "\(item.fixture) vs \(item.schema):\n\(issues.joined(separator: "\n"))")
        }
    }

    @Test func modelsReadEveryContractField() throws {
        for item in cases {
            let json = try fixtureJSON(item.fixture)
            let original = try item.decode(try JSONSerialization.data(withJSONObject: json))
            var ignoredByModel = Set<String>()
            for path in leafPaths(json) {
                let changed = mutated(json, at: path[...])
                let data = try JSONSerialization.data(withJSONObject: changed)
                // A decode failure after the change also means the model reads the field.
                if let result = try? item.decode(data), result == original {
                    ignoredByModel.insert(normalized(path))
                }
            }
            let unexpected = ignoredByModel.filter { !isCovered($0, by: item.intentionallyIgnored) }.sorted()
            #expect(
                unexpected.isEmpty,
                "\(item.fixture): the model does not read these contract fields (add them to the model or to intentionallyIgnored):\n\(unexpected.joined(separator: "\n"))"
            )
            // A stale exception would hide a real regression later.
            let stale = item.intentionallyIgnored
                .filter { !$0.hasSuffix(".*") && !ignoredByModel.contains($0) }
                .sorted()
            #expect(stale.isEmpty, "\(item.fixture): intentionallyIgnored entries the model now reads (remove them):\n\(stale.joined(separator: "\n"))")
        }
    }

    @Test func knownEnumCasesAreExactlyTheContractValues() {
        func known<E: FallbackStringEnum>(_: E.Type) -> Set<String> {
            Set(E.knownMapping.map { $0.1 })
        }
        #expect(known(LeaseStatus.self) == Contract.enumValues("LeaseStatus"))
        #expect(known(ChargeKind.self) == Contract.enumValues("LeaseChargeKind"))
        #expect(known(ChargeState.self) == Contract.enumValues("LeaseChargeState"))
        #expect(known(ChargePaymentStatus.self) == Contract.enumValues("LeaseChargePaymentStatus"))
        #expect(known(DepositStatus.self) == Contract.enumValues("LeaseDepositStatus"))
        #expect(known(DepositEntryType.self) == Contract.enumValues("DepositEntryType"))
        #expect(known(PaymentDirection.self) == Contract.enumValues("LeasePaymentDirection"))
        #expect(known(UtilitiesPaidBy.self) == Contract.enumValues("LeaseUtilitiesPaidBy"))
        #expect(known(DocumentTemplateKind.self) == Contract.propertyEnum("DocumentTemplate", "kind"))
        #expect(known(ContractFileType.self) == Contract.propertyEnum("ContractGeneratedFile", "file_type"))
        #expect(known(LandlordGender.self) == Contract.propertyEnum("LandlordProfile", "gender"))
        #expect(known(ContractMissingEntity.self) == Contract.propertyEnum("ContractMissingField", "entity"))
    }
}
