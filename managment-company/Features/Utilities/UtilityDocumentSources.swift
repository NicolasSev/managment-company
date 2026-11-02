import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

// The three ways to give the app a utility document: the document camera, the photo library and
// Files (same as the move-in wizard). Whatever the owner picks becomes a `RecognitionUpload`:
// a JPEG under 10 MB, or a PDF.

/// Builds the upload of a scan, a photo or a file.
enum UtilityDocumentBuilder {
    /// The PDF limit of the endpoint.
    static let maxPages = 5
    private static let pageSize = CGSize(width: 595, height: 842)

    /// Pages of the document camera: one page is a JPEG, several are one PDF (the first five).
    static func upload(fromScan pages: [UIImage]) -> RecognitionUpload? {
        guard let first = pages.first else { return nil }
        if pages.count == 1 {
            return RecognitionUploadBuilder.upload(from: first, fileName: "utility-bill.jpg")
        }
        return pdf(from: Array(pages.prefix(maxPages)))
    }

    /// A picked photo or file: a PDF goes through untouched, an image becomes a JPEG.
    static func upload(fromData data: Data, fileName: String?) -> RecognitionUpload? {
        RecognitionUploadBuilder.upload(fromData: data, fileName: fileName ?? "utility-bill.jpg")
    }

    private static func pdf(from pages: [UIImage]) -> RecognitionUpload? {
        for quality in [0.7, 0.5, 0.35] as [CGFloat] {
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
            let data = renderer.pdfData { context in
                for page in pages {
                    context.beginPage()
                    let image = compressed(page, quality: quality)
                    let ratio = min(pageSize.width / image.size.width, pageSize.height / image.size.height)
                    let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                    image.draw(in: CGRect(
                        x: (pageSize.width - size.width) / 2,
                        y: (pageSize.height - size.height) / 2,
                        width: size.width,
                        height: size.height
                    ))
                }
            }
            if data.count <= RecognitionUpload.maxBytes {
                return RecognitionUpload(data: data, fileName: "utility-bill.pdf", mimeType: "application/pdf")
            }
        }
        return nil
    }

    private static func compressed(_ image: UIImage, quality: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let ratio = longest > 1800 ? 1800 / longest : 1
        let size = CGSize(width: (image.size.width * ratio).rounded(), height: (image.size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = scaled.jpegData(compressionQuality: quality), let result = UIImage(data: jpeg) else { return scaled }
        return result
    }
}

/// The document scanner with every page (a bill often has two). Not available in the simulator
/// (`isSupported == false`): the camera item is then hidden.
struct UtilityScanCamera: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void
    let onFailure: (Error) -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel, onFailure: onFailure)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScan: ([UIImage]) -> Void
        private let onCancel: () -> Void
        private let onFailure: (Error) -> Void

        init(onScan: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void, onFailure: @escaping (Error) -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
            self.onFailure = onFailure
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else {
                onCancel()
                return
            }
            onScan((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFailure(error)
        }
    }
}

/// Owns the three pickers and hands the result up as one `RecognitionUpload`. Wrap any label:
///
///     UtilityDocumentMenu(identifier: "utilities.grid.upload", onPicked: { … }, onUnreadable: { … }) { Label(…) }
///
/// The identifiers are `<identifier>.scan`, `.photos` and `.files`.
struct UtilityDocumentMenu<MenuLabel: View>: View {
    let identifier: String
    let onPicked: (RecognitionUpload) -> Void
    let onUnreadable: () -> Void
    @ViewBuilder var label: () -> MenuLabel

    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        Menu {
            if UtilityScanCamera.isSupported {
                Button { showCamera = true } label: {
                    Label("Сканировать", systemImage: "camera.viewfinder")
                }
                .accessibilityIdentifier("\(identifier).scan")
            }
            Button { showPhotos = true } label: {
                Label("Из Фото", systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("\(identifier).photos")
            Button { showFiles = true } label: {
                Label("Из Файлов", systemImage: "folder")
            }
            .accessibilityIdentifier("\(identifier).files")
        } label: {
            label()
        }
        .accessibilityIdentifier(identifier)
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images, photoLibrary: .shared())
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await handlePhoto(item) }
        }
        .fileImporter(
            isPresented: $showFiles,
            allowedContentTypes: [.jpeg, .png, .heic, .pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFile(result)
        }
        .fullScreenCover(isPresented: $showCamera) {
            UtilityScanCamera(
                onScan: { pages in
                    showCamera = false
                    if let upload = UtilityDocumentBuilder.upload(fromScan: pages) {
                        onPicked(upload)
                    } else {
                        onUnreadable()
                    }
                },
                onCancel: { showCamera = false },
                onFailure: { _ in
                    showCamera = false
                    onUnreadable()
                }
            )
            .ignoresSafeArea()
            .accessibilityIdentifier("\(identifier).camera")
        }
    }

    private func handlePhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let upload = UtilityDocumentBuilder.upload(fromData: data, fileName: nil) else {
            onUnreadable()
            return
        }
        onPicked(upload)
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let upload = UtilityDocumentBuilder.upload(fromData: data, fileName: url.lastPathComponent) else {
            onUnreadable()
            return
        }
        onPicked(upload)
    }
}
