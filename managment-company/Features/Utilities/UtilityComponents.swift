import PDFKit
import SwiftUI
import UIKit

// Small flat pieces shared by the utility screens (D2: sentence case, hairline borders, no
// uppercase tracking, no glass on content).

struct UtilitySectionTitle: View {
    let text: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Spacer(minLength: AppTheme.Spacing.sm)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }
}

/// Status of a bill: the symbol of its tone and the label from the meta.
struct UtilityStatusLabel: View {
    let text: String
    let tone: StatusTone
    var identifier: String?

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: tone.systemImage)
                .font(.system(size: 9, weight: .heavy))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tone.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tone.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .modifier(OptionalIdentifier(identifier: identifier))
    }
}

/// Outlined secondary action of the review sheet and the flow.
struct UtilitySecondaryButtonStyle: ButtonStyle {
    var tone: Color = AppTheme.Colors.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tone)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tone.opacity(configuration.isPressed ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tone.opacity(0.25), lineWidth: 1)
            )
    }
}

/// A message under the content: quiet, with the symbol of its tone.
struct UtilityBanner: View {
    let text: String
    var tone: StatusTone = .danger
    var identifier: String

    var body: some View {
        SettleNotice(text: text, tone: tone, identifier: identifier)
    }
}

// MARK: - Share

/// `UIActivityViewController` for the text of a message (the share sheet).
struct UtilityActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - File preview

/// Preview of the bill's document: an image or the first pages of a PDF, fetched through the signed
/// download URL. Without the network or a URL the file shows as a plain tile.
struct UtilityFilePreview: View {
    let file: UtilityBillFile
    var height: CGFloat = 240

    @State private var image: UIImage?
    @State private var document: PDFDocument?
    @State private var didFail = false

    private var url: URL? {
        guard let path = file.downloadUrl else { return nil }
        return APIURLBuilder.absoluteDownloadURL(base: AppEnvironment.apiBaseURL, downloadPath: path)
    }

    var body: some View {
        Group {
            if let document {
                UtilityPDFView(document: document)
                    .accessibilityLabel("Документ PDF")
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Фото документа")
            } else {
                tile
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(AppTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.Colors.border, lineWidth: 1)
        )
        .task(id: file.id) { await load() }
    }

    private var tile: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if url != nil && !didFail {
                ProgressView()
            } else {
                Image(systemName: file.isPDF ? "doc.text" : "photo")
                    .font(.largeTitle)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
            Text(file.originalName ?? "Документ")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)
            if let size = file.sizeBytes, size > 0 {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            if didFail || url == nil {
                Text("Предпросмотр недоступен")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .padding(AppTheme.Spacing.md)
    }

    private func load() async {
        guard let url, image == nil, document == nil else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true else {
                didFail = true
                return
            }
            if file.isPDF || RecognitionUploadBuilder.isPDF(data) {
                document = PDFDocument(data: data)
                didFail = document == nil
            } else {
                image = UIImage(data: data)
                didFail = image == nil
            }
        } catch {
            didFail = true
        }
    }
}

struct UtilityPDFView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}

/// `accessibilityIdentifier` only when there is one: an empty identifier would hide the parent's.
struct OptionalIdentifier: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier { content.accessibilityIdentifier(identifier) } else { content }
    }
}

extension View {
    /// An identifier for a whole block that keeps the identifiers of its children: a plain
    /// `accessibilityIdentifier` on a container would replace theirs.
    func accessibilityContainer(_ identifier: String) -> some View {
        accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
    }
}
