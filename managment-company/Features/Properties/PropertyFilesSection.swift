import SwiftUI
import UniformTypeIdentifiers

struct EntityFileType: Hashable {
    let value: String
    let label: String
}

private struct EntityFileRow: Codable, Identifiable {
    let id: String
    let entityType: String
    let entityId: String
    let fileType: String
    let originalName: String?
    let mimeType: String?
    let sizeBytes: Int64?
    let downloadURL: String?
    let downloadURLExpiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case entityType = "entity_type"
        case entityId = "entity_id"
        case fileType = "file_type"
        case originalName = "original_name"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case downloadURL = "download_url"
        case downloadURLExpiresAt = "download_url_expires_at"
    }

    var displayName: String {
        if let name = originalName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return fileType
    }
}

struct PropertyFilesSection: View {
    let propertyId: String

    var body: some View {
        EntityFilesSection(
            entityType: "property",
            entityId: propertyId,
            title: "Файлы объекта"
        )
    }
}

struct EntityFilesSection: View {
    let entityType: String
    let entityId: String
    var title: String = "Файлы"
    var isEmbedded: Bool = false
    var fileTypes: [EntityFileType] = [
        EntityFileType(value: "document", label: "Документ"),
        EntityFileType(value: "photo", label: "Фото"),
        EntityFileType(value: "receipt", label: "Квитанция")
    ]

    @EnvironmentObject private var authManager: AuthManager
    @State private var files: [EntityFileRow] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isUploading = false
    @State private var showFileImporter = false
    @State private var selectedFileType: String
    @State private var fileToDelete: EntityFileRow?

    init(
        entityType: String,
        entityId: String,
        title: String = "Файлы",
        isEmbedded: Bool = false,
        fileTypes: [EntityFileType] = [
            EntityFileType(value: "document", label: "Документ"),
            EntityFileType(value: "photo", label: "Фото"),
            EntityFileType(value: "receipt", label: "Квитанция")
        ]
    ) {
        self.entityType = entityType
        self.entityId = entityId
        self.title = title
        self.isEmbedded = isEmbedded
        self.fileTypes = fileTypes
        _selectedFileType = State(initialValue: fileTypes.first?.value ?? "document")
    }

    var body: some View {
        Group {
            if isEmbedded {
                fileContent
                    .padding(.vertical, AppTheme.Spacing.sm)
            } else {
                SurfaceCard {
                    fileContent
                }
            }
        }
        .task(id: "\(entityType)-\(entityId)") { await loadFiles() }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await upload(fileURL: url) }
            case .failure:
                errorMessage = "Не удалось открыть файл."
            }
        }
        .confirmationDialog(
            "Удалить файл?",
            isPresented: Binding(
                get: { fileToDelete != nil },
                set: { if !$0 { fileToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let file = fileToDelete {
                    Task { await delete(file) }
                }
            }
            Button("Отмена", role: .cancel) {
                fileToDelete = nil
            }
        } message: {
            Text("Вложение будет удалено из записи.")
        }
    }

    private var fileContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .textCase(.uppercase)
                            .tracking(1.1)
                            .foregroundStyle(AppTheme.Colors.textSecondary)

                        Text("Загружайте договоры, квитанции и подтверждающие документы рядом с записью.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Spacer()

                    Button {
                        showFileImporter = true
                    } label: {
                        Image(systemName: "arrow.up.doc")
                            .font(.headline)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.Colors.accent)
                    .disabled(isUploading)
                    .accessibilityLabel("Загрузить файл")
                }

                Picker("Категория файла", selection: $selectedFileType) {
                    ForEach(fileTypes, id: \.value) { type in
                        Text(type.label).tag(type.value)
                    }
                }
                .pickerStyle(.segmented)

                if isUploading {
                    ProgressView("Загружаем файл...")
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.warning)
                } else if files.isEmpty {
                    Text("Файлов пока нет.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        ForEach(files) { file in
                            fileRow(file)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private func fileRow(_ file: EntityFileRow) -> some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
            Image(systemName: file.mimeType?.hasPrefix("image/") == true ? "photo" : "doc.text")
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(fileTypeLabel(file.fileType))
                    if let size = file.sizeBytes {
                        Text("· \(Self.fileSizeLabel(size))")
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer()

            if let path = file.downloadURL,
               let url = APIURLBuilder.absoluteDownloadURL(base: AppEnvironment.apiBaseURL, downloadPath: path) {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Открыть или поделиться файлом")
            }

            Button(role: .destructive) {
                fileToDelete = file
            } label: {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.danger)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Удалить файл")
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func loadFiles() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let encodedEntityType = entityType.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? entityType
        let encodedEntityId = entityId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? entityId
        let path = "/v1/files?entity_type=\(encodedEntityType)&entity_id=\(encodedEntityId)"

        do {
            let data = try await APIClient.shared.requestData(
                path,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            let payload = try JSONDecoder().decode(APIListEnvelope<EntityFileRow>.self, from: data)
            files = payload.data
        } catch {
            files = []
            errorMessage = "Не удалось загрузить файлы."
        }
    }

    private func upload(fileURL: URL) async {
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        let access = fileURL.startAccessingSecurityScopedResource()
        defer {
            if access {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let fileData = try Data(contentsOf: fileURL)
            _ = try await APIClient.shared.uploadMultipart(
                "/v1/files",
                fields: [
                    "entity_type": entityType,
                    "entity_id": entityId,
                    "file_type": selectedFileType
                ],
                fileFieldName: "file",
                fileData: fileData,
                fileName: fileURL.lastPathComponent,
                mimeType: Self.mimeType(for: fileURL),
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            ) as EntityFileRow
            await loadFiles()
        } catch APIError.httpStatus(let code) {
            errorMessage = code == 413 ? "Файл слишком большой." : "Не удалось загрузить файл."
        } catch {
            errorMessage = "Не удалось загрузить файл."
        }
    }

    private func delete(_ file: EntityFileRow) async {
        do {
            _ = try await APIClient.shared.requestData(
                "/v1/files/\(file.id)",
                method: "DELETE",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            fileToDelete = nil
            await loadFiles()
        } catch {
            errorMessage = "Не удалось удалить файл."
        }
    }

    private func fileTypeLabel(_ raw: String) -> String {
        fileTypes.first(where: { $0.value == raw })?.label ?? raw.replacingOccurrences(of: "_", with: " ")
    }

    private static func fileSizeLabel(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return "application/pdf"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "heic", "heif":
            return "image/heic"
        default:
            return "application/octet-stream"
        }
    }
}
