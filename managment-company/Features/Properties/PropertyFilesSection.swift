import SwiftUI

private struct PropertyFileRow: Codable {
    let id: String
    let fileType: String
    let originalName: String?
    let downloadURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fileType = "file_type"
        case originalName = "original_name"
        case downloadURL = "download_url"
    }

    var displayName: String {
        if let name = originalName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return fileType
    }
}

private struct FileListPayload: Decodable {
    let data: [PropertyFileRow]
}

struct PropertyFilesSection: View {
    let propertyId: String
    @EnvironmentObject var authManager: AuthManager
    @State private var files: [PropertyFileRow] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Files")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.warning)
                } else if files.isEmpty {
                    Text("Файлов пока нет. Загрузите их через веб-приложение, чтобы видеть здесь.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        ForEach(files, id: \.id) { file in
                            fileRow(file)
                        }
                    }
                }
            }
        }
        .task { await loadFiles() }
    }

    @ViewBuilder
    private func fileRow(_ file: PropertyFileRow) -> some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
            Image(systemName: "doc.text")
                .foregroundStyle(AppTheme.Colors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(file.fileType)
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
                }
                .accessibilityLabel("Share or open file")
            }
        }
        .padding(.vertical, 4)
    }

    private func loadFiles() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let path = "/v1/files?entity_type=property&entity_id=\(propertyId)"
        do {
            let payload: FileListPayload = try await APIClient.shared.request(
                path,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            files = payload.data
        } catch {
            errorMessage = "Could not load files."
        }
    }
}
