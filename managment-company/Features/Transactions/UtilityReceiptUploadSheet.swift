import SwiftUI
import UniformTypeIdentifiers

struct UtilityReceiptUploadSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    var onCompleted: () -> Void

    @State private var properties: [Property] = []
    @State private var showFileImporter = false
    @State private var isUploading = false
    @State private var isConfirming = false
    @State private var errorMessage: String?
    @State private var receipt: UtilityReceiptPayload?
    @State private var pollTask: Task<Void, Never>?
    @State private var pickedFileLabel: String?
    @State private var manualPropertySelection: String = ""
    @State private var amountEdits: [String: String] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        if let errorMessage {
                            SurfaceCard(padding: AppTheme.Spacing.md) {
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Colors.danger)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if properties.isEmpty, !isUploading {
                            Text("Добавьте объект, чтобы выбрать квартиру для ручного сопоставления квитанции.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }

                        SurfaceCard {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                                Text("Файл")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .textCase(.uppercase)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)

                                PrimaryButton(
                                    title: receipt == nil
                                        ? (isUploading ? "Отправляем…" : "Выбрать PDF или фото")
                                        : "Выбрать другой файл",
                                    action: { showFileImporter = true },
                                    isDisabled: isUploading || isConfirming || properties.isEmpty
                                )

                                if let pickedFileLabel {
                                    Text(pickedFileLabel)
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                }

                                if isUploading {
                                    ProgressView("Загрузка…")
                                        .frame(maxWidth: .infinity)
                                }

                                pollStatusBanner
                                failedReceiptBody
                                parsedReceiptBody
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.lg)
                }
            }
            .navigationTitle("Квитанция ЖКХ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf, .jpeg, .png, .heic, .image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await uploadReceipt(fileURL: url) }
                case .failure:
                    errorMessage = "Не удалось открыть файл."
                }
            }
            .task {
                await loadProperties()
            }
            .onDisappear {
                pollTask?.cancel()
            }
            .interactiveDismissDisabled(isUploading || isConfirming)
        }
    }

    @ViewBuilder
    private var pollStatusBanner: some View {
        if let receipt, receipt.status == "queued" || receipt.status == "processing" {
            SurfaceCard(padding: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ProgressView()
                    Text("Распознаём квитанцию… Обычно 15–30 секунд.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var failedReceiptBody: some View {
        if let receipt, receipt.status == "failed" {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Распознавание не удалось.")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.danger)
                Text(receipt.failureReason ?? "Загрузите другое изображение или PDF.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var parsedReceiptBody: some View {
        if let receipt, receipt.status == "parsed" {
            if let confidence = receipt.extractionConfidence, confidence < 0.8 {
                Text("Проверьте суммы: уверенность распознавания \(Int((confidence * 100).rounded()))%.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.warning)
                    .padding(.bottom, AppTheme.Spacing.sm)
            }

            if receipt.propertyId == nil {
                Text("Не удалось сопоставить объект по лицевому счёту — выберите квартиру вручную.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Picker("Объект", selection: $manualPropertySelection) {
                    Text("Выберите объект").tag("")
                    ForEach(properties) { property in
                        Text(property.name).tag(property.id)
                    }
                }
                .pickerStyle(.navigationLink)
            } else if let pid = receipt.propertyId, let match = properties.first(where: { $0.id == pid }) {
                Label("Объект: \(match.name)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.success)
            }

            if let items = receipt.items, !items.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("Начисления")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    ForEach(items) { item in
                        HStack {
                            Text(utilityReceiptLineTitle(item))
                                .font(.subheadline)
                                .foregroundStyle(item.amount == 0 ? AppTheme.Colors.textTertiary : AppTheme.Colors.textPrimary)
                            Spacer()
                            TextField("Сумма", text: bindingAmount(item))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                PrimaryButton(
                    title: isConfirming ? "Сохраняем…" : "Подтвердить",
                    action: { Task { await confirmReceipt(original: receipt) } },
                    isLoading: isConfirming,
                    isDisabled: !canConfirm(receipt: receipt) || isConfirming,
                    systemImage: "checkmark.circle"
                )
            } else {
                Text("Строк начислений не найдено.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    private func bindingAmount(_ item: UtilityReceiptItemPayload) -> Binding<String> {
        Binding(
            get: {
                if let edited = amountEdits[item.id] { return edited }
                return Self.formatAmount(item.amount)
            },
            set: { amountEdits[item.id] = $0 }
        )
    }

    private static func formatAmount(_ value: Double) -> String {
        let asInt = Int(value)
        if Double(asInt) == value {
            return "\(asInt)"
        }
        return String(format: "%.2f", value)
    }

    private func utilityReceiptLineTitle(_ item: UtilityReceiptItemPayload) -> String {
        let base = UtilityReceiptLabels.title(for: item.utilityType)
        if let raw = item.labelRaw, !raw.isEmpty {
            return "\(base) (\(raw))"
        }
        return base
    }

    private func canConfirm(receipt remote: UtilityReceiptPayload) -> Bool {
        if remote.propertyId != nil {
            return true
        }
        return !manualPropertySelection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadProperties() async {
        await MainActor.run { errorMessage = nil }
        do {
            let loaded: [Property] = try await APIClient.shared.request(
                "/v1/properties",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            await MainActor.run {
                properties = loaded
                if loaded.isEmpty {
                    errorMessage = "Объектов пока нет — добавьте квартиру в разделе «Объекты»."
                }
            }
        } catch {
            await MainActor.run {
                properties = []
                errorMessage = "Не удалось загрузить список объектов."
            }
        }
    }

    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "application/pdf"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "heic", "heif":
            return "image/heic"
        default:
            return "application/octet-stream"
        }
    }

    private func uploadReceipt(fileURL: URL) async {
        await MainActor.run {
            errorMessage = nil
            receipt = nil
            amountEdits = [:]
            manualPropertySelection = ""
            pickedFileLabel = fileURL.lastPathComponent
            isUploading = true
        }

        let access = fileURL.startAccessingSecurityScopedResource()
        defer {
            if access {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let fileData = try Data(contentsOf: fileURL)
            let queued: UtilityReceiptPayload = try await APIClient.shared.uploadMultipartUnwrapped(
                "/v1/utility-receipts",
                fieldName: "file",
                fileData: fileData,
                fileName: fileURL.lastPathComponent,
                mimeType: mimeType(for: fileURL),
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            await MainActor.run {
                receipt = queued
                syncAmountEditsFromReceipt()
            }
            startPolling(receiptId: queued.id)
        } catch APIError.httpStatus(let code) {
            await MainActor.run {
                errorMessage = "Ошибка сервера (код \(code))."
            }
        } catch {
            await MainActor.run {
                errorMessage = "Не удалось загрузить файл."
            }
        }

        await MainActor.run {
            isUploading = false
        }
    }

    private func syncAmountEditsFromReceipt() {
        guard let items = receipt?.items else { return }
        var next = amountEdits
        for item in items where next[item.id] == nil {
            next[item.id] = Self.formatAmount(item.amount)
        }
        amountEdits = next
    }

    private func startPolling(receiptId: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let latest: UtilityReceiptPayload = try await APIClient.shared.request(
                        "/v1/utility-receipts/\(receiptId)",
                        tokenProvider: { await MainActor.run { authManager.accessToken } },
                        refreshAndRetry: { await authManager.refreshToken() }
                    )
                    await MainActor.run {
                        receipt = latest
                        syncAmountEditsFromReceipt()
                        errorMessage = nil
                    }
                    if ["parsed", "failed", "confirmed"].contains(latest.status) {
                        return
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Не удалось получить статус распознавания."
                    }
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    @MainActor
    private func confirmReceipt(original: UtilityReceiptPayload) async {
        let manualChoice = manualPropertySelection.trimmingCharacters(in: .whitespacesAndNewlines)
        let assignedId: String?
        if let pid = original.propertyId {
            assignedId = pid
        } else if manualChoice.isEmpty {
            assignedId = nil
        } else {
            assignedId = manualChoice
        }

        guard let chosen = assignedId, !chosen.isEmpty else {
            errorMessage = "Выберите объект."
            return
        }

        errorMessage = nil
        isConfirming = true
        defer { isConfirming = false }

        let editsPayload = editsForConfirm(items: original.items ?? [])

        do {
            let body = UtilityReceiptConfirmBody(
                propertyId: original.propertyId == nil ? chosen : nil,
                edits: editsPayload
            )

            _ = try await APIClient.shared.request(
                "/v1/utility-receipts/\(original.id)/confirm",
                method: "POST",
                body: body,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            ) as UtilityReceiptPayload

            dismiss()
            onCompleted()
        } catch APIError.httpStatus(let code) {
            errorMessage = "Не удалось сохранить (\(code))."
        } catch {
            errorMessage = "Не удалось сохранить квитанцию."
        }
    }

    private func editsForConfirm(items: [UtilityReceiptItemPayload]) -> [ReceiptItemAmountEdit]? {
        var edits: [ReceiptItemAmountEdit] = []
        for item in items {
            guard let raw = amountEdits[item.id]?.replacingOccurrences(of: ",", with: ".") else { continue }
            guard let parsed = Double(raw) else { continue }
            if abs(parsed - item.amount) > 0.009 {
                edits.append(ReceiptItemAmountEdit(itemId: item.id, amount: parsed))
            }
        }
        return edits.isEmpty ? nil : edits
    }

    init(onCompleted: @escaping () -> Void) {
        self.onCompleted = onCompleted
    }
}

private enum UtilityReceiptLabels {
    static func title(for type: String) -> String {
        switch type {
        case "electricity": return "Электричество"
        case "cold_water": return "Холодная вода"
        case "hot_water": return "Горячая вода"
        case "water_disposal": return "Водоотведение"
        case "gas": return "Газ"
        case "heating": return "Отопление"
        case "common_area": return "МОП"
        case "waste": return "Вывоз отходов"
        case "elevator": return "Лифт"
        case "intercom": return "Домофон"
        case "internet": return "Интернет"
        case "tv": return "ТВ"
        case "capital_repair": return "Капремонт"
        default:
            return type.replacingOccurrences(of: "_", with: " ")
        }
    }
}
