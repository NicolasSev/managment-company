#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit
import AppIntents

/// Glass palette: the Lock Screen card is a light translucent tint over the
/// wallpaper, so everything is drawn in white ink with a soft shadow and
/// translucent white tiles rather than opaque system fills.
private enum RentGlass {
    static let background = Color.white.opacity(0.2)
    static let ink = Color.white
    static let muted = Color.white.opacity(0.72)
    static let faint = Color.white.opacity(0.55)
    static let tile = Color.white.opacity(0.18)
    static let tileStroke = Color.white.opacity(0.28)
    static let paid = Color(red: 0.36, green: 0.86, blue: 0.52)
    static let shadow = Color.black.opacity(0.28)
}

private extension View {
    /// Soft drop shadow that keeps white ink legible over bright wallpapers.
    func inkShadow() -> some View {
        shadow(color: RentGlass.shadow, radius: 2, x: 0, y: 1)
    }
}

/// Lock Screen + Dynamic Island UI for the rent payment Live Activity.
struct RentPaymentLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RentPaymentAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(RentGlass.background)
                .activitySystemActionForegroundColor(RentGlass.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IconTile(size: 36)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PeriodChip(label: context.attributes.periodLabel)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.propertyName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(RentGlass.ink)
                            .lineLimit(1)
                        Text(context.attributes.tenantName)
                            .font(.caption)
                            .foregroundStyle(RentGlass.muted)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(amountString(context.attributes))
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(RentGlass.ink)
                            Text("до \(RentFormatting.dueDate(context.attributes.dueDate))")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(RentGlass.muted)
                        }
                        Spacer()
                        if context.state.status == "paid" {
                            PaidChip()
                        } else {
                            HStack(spacing: 8) {
                                Button(intent: MarkRentNotPaidIntent(scheduleId: context.attributes.scheduleId)) {
                                    Image(systemName: "clock")
                                }
                                .buttonStyle(.bordered)
                                .tint(RentGlass.ink)
                                Button(intent: MarkRentPaidIntent(
                                    scheduleId: context.attributes.scheduleId,
                                    amount: context.attributes.amount,
                                    currency: context.attributes.currency
                                )) {
                                    Label("Оплачено", systemImage: "checkmark.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(RentGlass.paid)
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "house.fill")
                    .foregroundStyle(RentGlass.ink)
            } compactTrailing: {
                Text(amountString(context.attributes))
                    .monospacedDigit()
                    .foregroundStyle(RentGlass.ink)
            } minimal: {
                Image(systemName: "house.fill")
                    .foregroundStyle(RentGlass.ink)
            }
        }
    }

    private func amountString(_ attrs: RentPaymentAttributes) -> String {
        RentFormatting.amount(attrs.amount, currency: attrs.currency)
    }
}

/// Translucent rounded tile holding the house glyph.
private struct IconTile: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "house.fill")
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(RentGlass.ink)
            .frame(width: size, height: size)
            .background(RentGlass.tile, in: .rect(cornerRadius: size * 0.3))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3)
                    .strokeBorder(RentGlass.tileStroke, lineWidth: 0.5)
            )
    }
}

/// Translucent capsule carrying the rent period.
private struct PeriodChip: View {
    let label: String

    var body: some View {
        Text(label.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .foregroundStyle(RentGlass.ink)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RentGlass.tile, in: Capsule())
            .overlay(Capsule().strokeBorder(RentGlass.tileStroke, lineWidth: 0.5))
    }
}

/// Status chip shown once the schedule is paid.
private struct PaidChip: View {
    var body: some View {
        Label("Оплачено", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(RentGlass.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RentGlass.paid.opacity(0.35), in: Capsule())
            .overlay(Capsule().strokeBorder(RentGlass.paid.opacity(0.6), lineWidth: 0.5))
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<RentPaymentAttributes>

    var body: some View {
        // Lock Screen Live Activities are capped at ~160pt tall and overflow is
        // clipped, so the layout stays to three tight rows:
        //   1. icon tile · object + tenant  ·  period chip
        //   2. amount  ·  due date chip
        //   3. actions (or paid status)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                IconTile(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.attributes.propertyName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(RentGlass.ink)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                        Text(context.attributes.tenantName)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    .foregroundStyle(RentGlass.muted)
                }
                Spacer(minLength: 8)
                PeriodChip(label: context.attributes.periodLabel)
            }
            .inkShadow()

            HStack(alignment: .center, spacing: 8) {
                Text(RentFormatting.amount(context.attributes.amount, currency: context.attributes.currency))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(RentGlass.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text("СРОК")
                        .font(.system(size: 9).weight(.semibold))
                        .foregroundStyle(RentGlass.faint)
                    Text(RentFormatting.dueDate(context.attributes.dueDate))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RentGlass.ink)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(RentGlass.tile, in: Capsule())
            }
            .inkShadow()

            actionRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var actionRow: some View {
        if context.state.status == "paid" {
            PaidChip()
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            HStack(spacing: 8) {
                Button(intent: MarkRentNotPaidIntent(scheduleId: context.attributes.scheduleId)) {
                    Image(systemName: "clock")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(RentGlass.ink)
                .frame(width: 56)

                Link(destination: URL(string: "propmanager://schedule/\(context.attributes.scheduleId)/preview")!) {
                    Image(systemName: "eye")
                        .foregroundStyle(RentGlass.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .frame(width: 56)
                .background(RentGlass.tile, in: .rect(cornerRadius: 8))

                Button(intent: MarkRentPaidIntent(
                    scheduleId: context.attributes.scheduleId,
                    amount: context.attributes.amount,
                    currency: context.attributes.currency
                )) {
                    Label("Оплачено", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(RentGlass.paid)
            }
        }
    }
}

/// Shared formatting so the Lock Screen, Dynamic Island, and compact views all
/// render the amount and due date identically.
private enum RentFormatting {
    static func amount(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(number) \(symbol(for: currency))"
    }

    static func symbol(for code: String) -> String {
        switch code.uppercased() {
        case "KZT": return "₸"
        case "USD": return "$"
        case "EUR": return "€"
        case "RUB": return "₽"
        default: return code
        }
    }

    static func dueDate(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.calendar = Calendar(identifier: .iso8601)
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = parser.date(from: raw) else { return raw }
        let out = DateFormatter()
        out.locale = Locale(identifier: "ru_RU")
        out.dateFormat = "d MMM"
        out.timeZone = TimeZone(secondsFromGMT: 0)
        return out.string(from: date)
    }
}
#endif
