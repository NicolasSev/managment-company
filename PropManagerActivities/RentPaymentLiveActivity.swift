#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit
import AppIntents

/// Accent color tying the period badge + key figures together. Picked to read
/// well on both Lock Screen and the Dynamic Island over arbitrary wallpapers.
private let rentAccent = Color(red: 0.20, green: 0.55, blue: 0.98)

/// Lock Screen + Dynamic Island UI for the rent payment Live Activity.
struct RentPaymentLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RentPaymentAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "house.fill")
                        .font(.title2)
                        .foregroundStyle(rentAccent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PeriodBadge(label: context.attributes.periodLabel)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.propertyName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(context.attributes.tenantName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(amountString(context.attributes))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                        Spacer()
                        if context.state.status == "paid" {
                            Label("Оплачено", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline.weight(.semibold))
                        } else {
                            HStack(spacing: 8) {
                                Button(intent: MarkRentNotPaidIntent(scheduleId: context.attributes.scheduleId)) {
                                    Image(systemName: "clock")
                                }
                                .buttonStyle(.bordered)
                                Button(intent: MarkRentPaidIntent(
                                    scheduleId: context.attributes.scheduleId,
                                    amount: context.attributes.amount,
                                    currency: context.attributes.currency
                                )) {
                                    Label("Оплачено", systemImage: "checkmark.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "house.fill")
                    .foregroundStyle(rentAccent)
            } compactTrailing: {
                Text(amountString(context.attributes))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "house.fill")
                    .foregroundStyle(rentAccent)
            }
        }
    }

    private func amountString(_ attrs: RentPaymentAttributes) -> String {
        RentFormatting.amount(attrs.amount, currency: attrs.currency)
    }
}

/// Tinted capsule that makes the rent period the primary visual accent.
private struct PeriodBadge: View {
    let label: String

    var body: some View {
        Text(label.uppercased())
            .font(.caption.weight(.bold))
            .tracking(0.5)
            .foregroundStyle(rentAccent)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(rentAccent.opacity(0.16), in: Capsule())
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<RentPaymentAttributes>

    var body: some View {
        // Lock Screen Live Activities are capped at ~160pt tall and overflow is
        // clipped, so the layout stays to three tight rows:
        //   1. object + tenant  ·  period badge (the primary accent)
        //   2. amount  ·  due date
        //   3. actions
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.propertyName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.attributes.tenantName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                PeriodBadge(label: context.attributes.periodLabel)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(RentFormatting.amount(context.attributes.amount, currency: context.attributes.currency))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("СРОК")
                    .font(.system(size: 9).weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text(RentFormatting.dueDate(context.attributes.dueDate))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            actionRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var actionRow: some View {
        if context.state.status == "paid" {
            Label("Оплачено", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.15), in: .rect(cornerRadius: 10))
        } else {
            HStack(spacing: 8) {
                Button(intent: MarkRentNotPaidIntent(scheduleId: context.attributes.scheduleId)) {
                    Image(systemName: "clock")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .frame(width: 56)

                Link(destination: URL(string: "propmanager://schedule/\(context.attributes.scheduleId)/preview")!) {
                    Image(systemName: "eye")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .frame(width: 56)
                .background(Color.gray.opacity(0.2), in: .rect(cornerRadius: 8))

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
                .tint(.green)
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
