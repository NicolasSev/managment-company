import SwiftUI

/// «Загрузить квитанцию» from the money tab and the quick actions: pick the document, follow the
/// recognition, check the bill. The property comes from the personal account on the receipt; the
/// grid of a property uploads for a month of that property.
struct UtilityQuickUploadSheet: View {
    private let service: UtilityBillsService
    private let timeZoneIdentifier: String
    private let onFinished: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var notificationRouter: NotificationDeepLinkRouter
    @State private var uploadRequest: UtilityUploadRequest?
    @State private var reviewRoute: UtilityBillRoute?
    @State private var unreadable = false
    @State private var showOverview = false
    private let authManager: AuthManager

    init(authManager: AuthManager, onFinished: @escaping () async -> Void = {}) {
        self.authManager = authManager
        self.service = UtilityBillsServiceProvider.makeService(authManager: authManager)
        self.timeZoneIdentifier = authManager.user?.timezone ?? "Asia/Almaty"
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                UtilitySectionTitle(text: "Квитанция по коммуналке")
                                Text("Сфотографируйте квитанцию или выберите файл. Объект и месяц определятся по лицевому счёту; суммы появятся в счетах после вашего подтверждения.")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                UtilityDocumentMenu(
                                    identifier: "utilities.quick.upload",
                                    onPicked: { upload in
                                        uploadRequest = UtilityUploadRequest(upload: upload, target: UtilityUploadTarget())
                                    },
                                    onUnreadable: { unreadable = true }
                                ) {
                                    Label("Загрузить квитанцию", systemImage: "arrow.up.doc")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .foregroundStyle(.white)
                                        .background(AppTheme.Colors.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                if unreadable {
                                    UtilityBanner(text: "Не удалось прочитать файл. Выберите JPEG, PNG, HEIC или PDF.", identifier: "utilities.quick.unreadable")
                                }
                            }
                        }
                        Button { showOverview = true } label: {
                            Label("Открыть коммуналку", systemImage: "square.grid.3x3")
                        }
                        .buttonStyle(UtilitySecondaryButtonStyle())
                        .accessibilityIdentifier("utilities.quick.overview")
                    }
                    .padding(AppTheme.Spacing.md)
                }
            }
            .navigationTitle("Коммуналка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .accessibilityIdentifier("utilities.quick.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .utilityBillReview(route: $reviewRoute, service: service, timeZoneIdentifier: timeZoneIdentifier) {
            await onFinished()
        }
        .utilityUploadFlow(
            request: $uploadRequest,
            service: service,
            onOpenBill: { id in reviewRoute = UtilityBillRoute(billId: id) },
            onGoToRent: {
                dismiss()
                notificationRouter.selectTab = .payments
            },
            onFinished: { await onFinished() }
        )
        .sheet(isPresented: $showOverview) {
            UtilitiesOverviewView(authManager: authManager)
                .environmentObject(authManager)
                .environmentObject(notificationRouter)
        }
        .accessibilityContainer("utilities.quick")
    }
}
