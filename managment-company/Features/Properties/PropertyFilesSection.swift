import SwiftUI
import PhotosUI

private struct PropertyFileRow: Codable, Identifiable {
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

// MARK: - Photo Section

struct PropertyPhotoSection: View {
    let propertyId: String
    @EnvironmentObject var authManager: AuthManager

    @State private var photos: [PropertyFileRow] = []
    @State private var isLoading = true
    @State private var isUploading = false
    @State private var photoToDelete: PropertyFileRow?
    @State private var selectedItem: PhotosPickerItem?
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Фотографии")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .textCase(.uppercase)
                            .tracking(1.1)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Text("Первое фото отображается на карточке в списке объектов.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    Spacer()
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: isUploading ? "arrow.up.circle" : "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(isUploading ? AppTheme.Colors.textSecondary : AppTheme.Colors.accent)
                    }
                    .disabled(isUploading)
                    .accessibilityLabel("Загрузить фото")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.danger)
                }

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppTheme.Spacing.md)
                } else if photos.isEmpty {
                    Button {
                    } label: {
                        PhotosPicker(
                            selection: $selectedItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.title3)
                                    .foregroundStyle(AppTheme.Colors.textTertiary)
                                Text("Нажмите чтобы загрузить фото")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.Spacing.lg)
                            .background(AppTheme.Colors.backgroundSecondary.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AppTheme.Colors.textTertiary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            )
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { idx, photo in
                            photoCell(photo, isMain: idx == 0)
                        }
                    }

                    if isUploading {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ProgressView()
                            Text("Загружаем фото…")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                }
            }
        }
        .task { await loadPhotos() }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task { await handlePickedPhoto(item) }
        }
        .alert("Удалить фото?", isPresented: Binding(
            get: { photoToDelete != nil },
            set: { if !$0 { photoToDelete = nil } }
        )) {
            Button("Удалить", role: .destructive) {
                if let photo = photoToDelete {
                    Task { await deletePhoto(photo) }
                }
            }
            Button("Отмена", role: .cancel) { photoToDelete = nil }
        } message: {
            Text("Фотография будет удалена безвозвратно.")
        }
    }

    @ViewBuilder
    private func photoCell(_ photo: PropertyFileRow, isMain: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            if let urlString = photo.downloadURL,
               let url = APIURLBuilder.absoluteDownloadURL(base: AppEnvironment.apiBaseURL, downloadPath: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(4/3, contentMode: .fill)
                    case .failure:
                        placeholderCell
                    case .empty:
                        Color(AppTheme.Colors.backgroundSecondary)
                            .overlay(ProgressView())
                            .aspectRatio(4/3, contentMode: .fill)
                    @unknown default:
                        placeholderCell
                    }
                }
                .aspectRatio(4/3, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                placeholderCell
            }

            if isMain {
                Text("Главное")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppTheme.Colors.accent.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(6)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        photoToDelete = photo
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
                Spacer()
            }
        }
    }

    private var placeholderCell: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(AppTheme.Colors.backgroundSecondary)
            .aspectRatio(4/3, contentMode: .fill)
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            )
    }

    private func loadPhotos() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let path = "/v1/files?entity_type=property&entity_id=\(propertyId)"
        do {
            let payload: FileListPayload = try await APIClient.shared.requestRoot(
                path,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            photos = payload.data.filter { $0.fileType == "photo" }
        } catch {
            errorMessage = "Не удалось загрузить фото."
        }
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
        selectedItem = nil
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Не удалось прочитать изображение."
                return
            }
            let uploaded: PropertyFileRow = try await APIClient.shared.uploadMultipartWithFields(
                "/v1/files",
                fileFieldName: "file",
                fileData: data,
                fileName: "photo.jpg",
                mimeType: "image/jpeg",
                fields: [
                    "entity_type": "property",
                    "entity_id": propertyId,
                    "file_type": "photo",
                ],
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            photos.append(uploaded)
        } catch {
            errorMessage = "Не удалось загрузить фото."
        }
    }

    private func deletePhoto(_ photo: PropertyFileRow) async {
        do {
            _ = try await APIClient.shared.requestData(
                "/v1/files/\(photo.id)",
                method: "DELETE",
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            photos.removeAll { $0.id == photo.id }
            photoToDelete = nil
        } catch {
            errorMessage = "Не удалось удалить фото."
            photoToDelete = nil
        }
    }
}

// MARK: - General Files Section

struct PropertyFilesSection: View {
    let propertyId: String
    @EnvironmentObject var authManager: AuthManager
    @State private var files: [PropertyFileRow] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    private var nonPhotoFiles: [PropertyFileRow] {
        files.filter { $0.fileType != "photo" }
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            PropertyPhotoSection(propertyId: propertyId)
                .environmentObject(authManager)

            if !nonPhotoFiles.isEmpty || isLoading {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Файлы")
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
                        } else {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                                ForEach(nonPhotoFiles) { file in
                                    fileRow(file)
                                }
                            }
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
                .accessibilityLabel("Поделиться или открыть файл")
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
            let payload: FileListPayload = try await APIClient.shared.requestRoot(
                path,
                tokenProvider: { await MainActor.run { authManager.accessToken } },
                refreshAndRetry: { await authManager.refreshToken() }
            )
            files = payload.data
        } catch {
            errorMessage = "Не удалось загрузить файлы."
        }
    }
}
