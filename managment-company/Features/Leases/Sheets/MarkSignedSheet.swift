import SwiftUI
import UniformTypeIdentifiers

/// «Подписан»: the date written on the paper plus an optional scan of the signed contract.
struct MarkSignedSheet: View {
    @ObservedObject var viewModel: LeaseDetailViewModel
    let lease: LeaseAggregate

    @State private var signedOn: String
    @State private var scan: LeaseScanAttachment?
    @State private var showImporter = false
    @State private var importError: String?

    init(viewModel: LeaseDetailViewModel, lease: LeaseAggregate) {
        self.viewModel = viewModel
        self.lease = lease
        _signedOn = State(initialValue: viewModel.todayDay)
    }

    var body: some View {
        LeaseSheetContainer(
            title: "Договор подписан",
            name: "mark_signed",
            submitTitle: "Сохранить",
            isSubmitting: viewModel.isSubmitting,
            errorMessage: viewModel.sheetError ?? importError,
            onCancel: { viewModel.dismissSheet() },
            onSubmit: { Task { await viewModel.submitMarkSigned(signedOn: signedOn, scan: scan) } }
        ) {
            Section {
                DatePicker(
                    "Дата подписания",
                    selection: leaseDayBinding($signedOn),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .accessibilityIdentifier("lease.detail.sheet.mark_signed.signed_on")
            } footer: {
                Text("Дата, проставленная в бумажном договоре. Не может быть в будущем.")
            }

            Section("Скан подписанного договора (необязательно)") {
                if let scan {
                    HStack {
                        Label(scan.fileName, systemImage: "doc.fill")
                            .lineLimit(1)
                        Spacer()
                        Button("Убрать") { self.scan = nil }
                            .accessibilityIdentifier("lease.detail.sheet.mark_signed.scan.remove")
                    }
                } else {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Прикрепить файл", systemImage: "paperclip")
                    }
                    .accessibilityIdentifier("lease.detail.sheet.mark_signed.scan.pick")
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .image]) { result in
            handleImport(result)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        importError = nil
        guard case .success(let url) = result else {
            if case .failure = result { importError = "Не удалось выбрать файл." }
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importError = "Не удалось прочитать файл."
            return
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        scan = LeaseScanAttachment(fileName: url.lastPathComponent, mimeType: mime, data: data)
    }
}
