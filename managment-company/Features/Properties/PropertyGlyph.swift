import SwiftUI

extension IsometricBuildingSpec {
    /// Glyph of a property, derived from its type, floor, rooms and status. Unknown floor or
    /// rooms are not invented: the glyph then marks the whole volume.
    init(property: Property) {
        let isOccupied = property.status.lowercased() == "occupied"
        let isMuted = property.isArchived
        switch property.propertyType.lowercased() {
        case "apartment":
            if let floor = property.floor, floor > 0 {
                let floors = min(max(floor + 1, 4), 9)
                self.init(
                    kind: .tower,
                    floors: floors,
                    unitFloor: min(floor, floors),
                    windows: min(max(property.rooms ?? 0, 0), 4),
                    isOccupied: isOccupied,
                    isMuted: isMuted
                )
            } else {
                self.init(
                    kind: .tower,
                    floors: 5,
                    unitFloor: nil,
                    windows: min(max(property.rooms ?? 0, 0), 4),
                    isOccupied: isOccupied,
                    isMuted: isMuted
                )
            }
        case "house":
            self.init(kind: .house, isOccupied: isOccupied, isMuted: isMuted)
        case "commercial":
            self.init(kind: .commercial, isOccupied: isOccupied, isMuted: isMuted)
        case "land":
            self.init(kind: .land, isOccupied: isOccupied, isMuted: isMuted)
        default:
            self.init(kind: .block, isOccupied: isOccupied, isMuted: isMuted)
        }
    }
}

extension Property {
    /// Russian title of the property type.
    var typeTitle: String {
        switch propertyType.lowercased() {
        case "apartment": return "Квартира"
        case "house": return "Дом"
        case "commercial": return "Коммерция"
        case "land": return "Земля"
        case "other": return "Другое"
        default: return propertyType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// The glyph of one property at a fixed size, rising on first appearance.
struct PropertyGlyph: View {
    let property: Property
    var height: CGFloat = 64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBuilt = false

    var body: some View {
        let spec = IsometricBuildingSpec(property: property)
        IsometricBuilding(spec: spec, progress: (isBuilt || reduceMotion) ? 1 : 0)
            .frame(
                width: IsometricStreet.width(of: spec, height: height),
                height: IsometricStreet.height(of: spec, height: height)
            )
            .frame(width: height * 0.74, height: height, alignment: .bottom)
            .animation(AppTheme.Motion.build, value: isBuilt)
            .onAppear { isBuilt = true }
    }
}
