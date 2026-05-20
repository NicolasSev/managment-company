#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit
import AppIntents

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
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(amountString(context.attributes))
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.propertyName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("\(context.attributes.tenantName) · \(context.attributes.periodLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.status == "paid" {
                        Label("Оплачено", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline.weight(.semibold))
                    } else {
                        HStack {
                            Button(intent: MarkRentNotPaidIntent(scheduleId: context.attributes.scheduleId)) {
                                Label("Не оплачено", systemImage: "clock")
                            }
                            .buttonStyle(.bordered)
                            Spacer()
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
            } compactLeading: {
                Image(systemName: "house.fill")
            } compactTrailing: {
                Text(amountString(context.attributes))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "house.fill")
            }
        }
    }

    private func amountString(_ attrs: RentPaymentAttributes) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let amount = formatter.string(from: NSNumber(value: attrs.amount)) ?? "\(Int(attrs.amount))"
        return "\(amount) \(attrs.currency)"
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<RentPaymentAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: что и за какой период
            VStack(alignment: .leading, spacing: 4) {
                Text("ОПЛАТА АРЕНДЫ · \(context.attributes.periodLabel)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(context.attributes.propertyName)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.attributes.tenantName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Сумма + дедлайн
            HStack(alignment: .firstTextBaseline) {
                Text(amountString)
                    .font(.title2.monospacedDigit().weight(.semibold))
                Spacer()
                Text("до \(context.attributes.dueDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if context.state.status == "paid" {
                Label("Оплачено", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                HStack(spacing: 6) {
                    Button(intent: MarkRentNotPaidIntent(scheduleId: context.attributes.scheduleId)) {
                        Label("Не оплачено", systemImage: "clock")
                            .labelStyle(.iconOnly)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Link(destination: URL(string: "propmanager://schedule/\(context.attributes.scheduleId)/preview")!) {
                        Label("Просмотреть", systemImage: "eye")
                            .labelStyle(.iconOnly)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .background(Color.gray.opacity(0.2), in: .rect(cornerRadius: 8))

                    Button(intent: MarkRentPaidIntent(
                        scheduleId: context.attributes.scheduleId,
                        amount: context.attributes.amount,
                        currency: context.attributes.currency
                    )) {
                        Label("Оплачено", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .padding(14)
    }

    private var amountString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let amount = formatter.string(from: NSNumber(value: context.attributes.amount)) ?? "\(Int(context.attributes.amount))"
        return "\(amount) \(context.attributes.currency)"
    }
}
#endif
