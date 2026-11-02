import Foundation
import UIKit
import UniformTypeIdentifiers

/// Turns what the owner picked (a camera page, a photo, a file) into the upload the recognition
/// endpoint takes: JPEG under 10 MB, or the PDF as it is.
enum RecognitionUploadBuilder {
    /// Longest side after downscaling; a document photo stays readable at this size.
    static let maxDimension: CGFloat = 2400

    /// A scanned page or photo as JPEG, downscaled and recompressed until it fits the limit.
    static func upload(from image: UIImage, fileName: String = "identity-document.jpg") -> RecognitionUpload? {
        let scaled = downscaled(image)
        for quality in [0.82, 0.6, 0.4] as [CGFloat] {
            if let data = scaled.jpegData(compressionQuality: quality), data.count <= RecognitionUpload.maxBytes {
                return RecognitionUpload(data: data, fileName: fileName, mimeType: "image/jpeg")
            }
        }
        return nil
    }

    /// Bytes of a picked photo or file. A PDF goes through untouched (the API checks pages);
    /// everything else is decoded as an image (HEIC included) and sent as JPEG.
    /// `nil` when the bytes are neither, or too large even after recompression.
    static func upload(fromData data: Data, fileName: String?) -> RecognitionUpload? {
        if isPDF(data) {
            guard data.count <= RecognitionUpload.maxBytes else { return nil }
            return RecognitionUpload(data: data, fileName: pdfName(fileName), mimeType: "application/pdf")
        }
        guard let image = UIImage(data: data) else { return nil }
        return upload(from: image, fileName: jpegName(fileName))
    }

    static func isPDF(_ data: Data) -> Bool {
        data.prefix(5) == Data("%PDF-".utf8)
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let ratio = longest > maxDimension ? maxDimension / longest : 1
        let size = CGSize(width: (image.size.width * ratio).rounded(), height: (image.size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        // Redrawing also bakes the orientation into the pixels, which the server does not read.
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func jpegName(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "identity-document.jpg" }
        return (name as NSString).deletingPathExtension + ".jpg"
    }

    private static func pdfName(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "identity-document.pdf" }
        return name.lowercased().hasSuffix(".pdf") ? name : (name as NSString).deletingPathExtension + ".pdf"
    }
}
