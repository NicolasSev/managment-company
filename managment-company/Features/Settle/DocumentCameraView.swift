import SwiftUI
import VisionKit

/// The document scanner of the system (`VNDocumentCameraViewController`): the owner frames the
/// identity card, VisionKit crops and flattens it. The first page goes to the wizard as an image.
///
/// Not available in the simulator (`isSupported == false`): the wizard hides the camera button
/// there and offers the photo library and Files only.
struct DocumentCameraView: UIViewControllerRepresentable {
    let onScan: (UIImage) -> Void
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
        private let onScan: (UIImage) -> Void
        private let onCancel: () -> Void
        private let onFailure: (Error) -> Void

        init(onScan: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void, onFailure: @escaping (Error) -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
            self.onFailure = onFailure
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // An identity card is one page; a second one (the back side) is not read.
            guard scan.pageCount > 0 else {
                onCancel()
                return
            }
            onScan(scan.imageOfPage(at: 0))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFailure(error)
        }
    }
}
