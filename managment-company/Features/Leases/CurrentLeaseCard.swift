import SwiftUI

/// Compact card of a lease (tenant screen, property screen). Shows who or what the lease is
/// about, its status, the rent, the next payment and the debt. Tapping it opens
/// `LeaseDetailView` (the caller wraps it in `LeaseNavigationLink`).
struct CurrentLeaseCard: View {
    enum Subject {
        /// Headline is the property (tenant screen).
        case property
        /// Headline is the tenant (property screen).
        case tenant
    }

    let lease: LeaseCard
    var subject: Subject = .property
    /// Prefix of the accessibility identifiers (`<prefix>.status`, `.debt`, ...).
    var identifier: String = "lease.card"

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Текущий договор")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Text(headline)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .multilineTextAlignment(.leading)
                            .accessibilityIdentifier("\(identifier).headline")
                        if let sub = subheadline {
                            Text(sub)
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                    Spacer(minLength: AppTheme.Spacing.sm)
                    LeaseStatusBadge(status: lease.status)
                        .accessibilityIdentifier("\(identifier).status")
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    LeaseMetricTile(
                        title: "Аренда",
                        value: lease.currentRentAmount.formatted(),
                        identifier: "\(identifier).rent"
                    )
                    LeaseMetricTile(
                        title: "Ближайший платёж",
                        value: nextPaymentText,
                        identifier: "\(identifier).next"
                    )
                    LeaseMetricTile(
                        title: "Долг",
                        value: debt.formatted(),
                        color: debt.isPositive ? AppTheme.Colors.danger : AppTheme.Colors.textPrimary,
                        identifier: "\(identifier).debt"
                    )
                }

                HStack {
                    Text("Открыть договор")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(AppTheme.Colors.accent)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var headline: String {
        switch subject {
        case .property: return lease.property.name
        case .tenant: return lease.tenant?.fullName ?? lease.property.name
        }
    }

    private var subheadline: String? {
        switch subject {
        case .property: return lease.property.address
        case .tenant: return lease.tenant?.phone
        }
    }

    /// Overdue part of the balance (charges not yet due are not debt).
    var debt: Money { lease.balance.overdue }

    var nextPaymentText: String {
        guard let next = lease.balance.nextCharge else { return "Нет" }
        return "\(LeaseDay.display(next.dueDate)) · \(next.outstanding.formatted())"
    }
}

/// Pushes `LeaseDetailView` on the lease service the app is configured for (live by default).
struct LeaseNavigationLink<Label: View>: View {
    let leaseId: String
    var identifier: String?
    @ViewBuilder var label: () -> Label

    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        NavigationLink {
            LeaseDetailView(
                leaseId: leaseId,
                service: LeaseV2ServiceProvider.makeService(authManager: authManager)
            )
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .leaseIdentifier(identifier)
    }
}
