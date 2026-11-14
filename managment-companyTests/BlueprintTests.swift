import Foundation
import SwiftUI
import Testing
@testable import managment_company

/// Blueprint design language: glyph mapping, status tones and chart labels.
@MainActor
struct BlueprintTests {
    private func property(
        type: String,
        status: String = "occupied",
        floor: Int? = nil,
        rooms: Int? = nil,
        archivedAt: String? = nil
    ) throws -> Property {
        var object: [String: Any] = [
            "id": "p1", "name": "Объект", "property_type": type, "status": status,
        ]
        if let floor { object["floor"] = floor }
        if let rooms { object["rooms"] = rooms }
        if let archivedAt { object["archived_at"] = archivedAt }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Property.self, from: data)
    }

    @Test func apartmentWithFloorMarksItsStorey() throws {
        let spec = IsometricBuildingSpec(property: try property(type: "apartment", floor: 6, rooms: 2))
        #expect(spec.kind == .tower)
        #expect(spec.floors == 7)
        #expect(spec.unitFloor == 6)
        #expect(spec.windows == 2)
        #expect(spec.isOccupied)
    }

    @Test func highFloorIsCappedAtTheDrawnHeight() throws {
        let spec = IsometricBuildingSpec(property: try property(type: "apartment", floor: 23, rooms: 9))
        #expect(spec.floors == 9)
        #expect(spec.unitFloor == 9)
        #expect(spec.windows == 4)
    }

    @Test func unknownFloorIsNotInvented() throws {
        let spec = IsometricBuildingSpec(property: try property(type: "apartment", status: "vacant"))
        #expect(spec.unitFloor == nil)
        #expect(spec.windows == 0)
        #expect(!spec.isOccupied)
    }

    @Test func kindsFollowThePropertyType() throws {
        #expect(IsometricBuildingSpec(property: try property(type: "house")).kind == .house)
        #expect(IsometricBuildingSpec(property: try property(type: "commercial")).kind == .commercial)
        #expect(IsometricBuildingSpec(property: try property(type: "land")).kind == .land)
        #expect(IsometricBuildingSpec(property: try property(type: "garage")).kind == .block)
    }

    @Test func archivedPropertyIsMuted() throws {
        let spec = IsometricBuildingSpec(
            property: try property(type: "house", archivedAt: "2026-10-01T00:00:00Z")
        )
        #expect(spec.isMuted)
    }

    @Test func typeTitlesAreRussian() throws {
        #expect(try property(type: "apartment").typeTitle == "Квартира")
        #expect(try property(type: "commercial").typeTitle == "Коммерция")
    }

    @Test func redIsReservedForAttention() {
        #expect(StatusBadge.tone("overdue") == .danger)
        #expect(StatusBadge.tone("urgent") == .danger)
        #expect(StatusBadge.tone("vacant") == .neutral)
        #expect(StatusBadge.tone("expense") == .neutral)
        #expect(StatusBadge.tone("terminated") == .neutral)
        #expect(StatusBadge.tone("paid") == .success)
    }

    @Test func compactChartLabels() {
        #expect(BlueprintChartFormat.compact(0) == "0")
        #expect(BlueprintChartFormat.compact(243_000) == "243 тыс")
        #expect(BlueprintChartFormat.compact(1_250_000) == "1,3 млн")
        #expect(BlueprintChartFormat.compact(-200_000) == "−200 тыс")
    }

    @Test func buildDelayIsCappedAndOffUnderReduceMotion() {
        #expect(AppTheme.Motion.buildDelay(index: 0) == 0)
        #expect(AppTheme.Motion.buildDelay(index: 100) == AppTheme.Motion.buildDelay(index: AppTheme.Motion.staggerLimit))
        #expect(AppTheme.Motion.buildDelay(index: 3, reduceMotion: true) == 0)
    }
}
