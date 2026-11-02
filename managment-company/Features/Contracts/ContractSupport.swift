import PDFKit
import QuickLook
import SwiftUI
import UIKit

// UIKit seams of the contract screens: temp files for sharing, the PDF viewer, print, the
// share sheet and QuickLook.

/// A file written to the temp folder, ready to hand to the share sheet or QuickLook.
struct ContractTempFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

/// Per-screen temp folder. Contracts carry personal data, so the folder is removed with the screen.
final class ContractTempFiles {
    let directory: URL

    init(directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("contract-\(UUID().uuidString)", isDirectory: true)) {
        self.directory = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Writes `file` under its own name and returns the URL.
    func write(_ file: ContractFile) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(LiveContractService.safeFilename(file.filename))
        try? FileManager.default.removeItem(at: url)
        try file.data.write(to: url, options: .atomic)
        return url
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// `PDFKit.PDFView` over PDF bytes: continuous scroll, fits the width.
struct ContractPDFView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        // Replace the document only when the bytes changed, so the scroll position survives redraws.
        if context.coordinator.data != data {
            context.coordinator.data = data
            view.document = PDFDocument(data: data)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(data: data) }

    final class Coordinator {
        var data: Data
        init(data: Data) { self.data = data }
    }
}

/// `UIActivityViewController` for a file: "Save to Files", AirDrop, mail.
struct ContractActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// QuickLook preview of one file (DOCX and PDF templates).
struct ContractQuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

/// AirPrint of PDF bytes through `UIPrintInteractionController`.
enum ContractPrinter {
    static var isAvailable: Bool { UIPrintInteractionController.isPrintingAvailable }

    /// Presents the system print panel. Returns false when printing is not available.
    @discardableResult
    static func printPDF(_ data: Data, jobName: String, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard isAvailable else { return false }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true) { _, completed, _ in
            completion?(completed)
        }
        return true
    }
}
