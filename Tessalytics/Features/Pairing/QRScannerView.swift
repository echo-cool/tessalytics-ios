import AVFoundation
import SwiftUI

/// The camera, looking for one QR code.
///
/// `AVCaptureSession` rather than `DataScannerViewController`: this has to read a
/// single symbol off a car's screen, which is the one thing the plain metadata
/// output does well on every device, with no text-recognition entitlement and no
/// Neural Engine requirement.
///
/// Reports the first payload it recognises and then stops. A scanner that keeps
/// firing while a confirmation sheet is being read is a scanner that re-enters the
/// flow behind the sheet.
struct QRScannerView: UIViewControllerRepresentable {
    /// Called on the main actor with the raw payload string.
    let onScan: @MainActor (String) -> Void
    /// Called when the camera cannot be used at all, with something to show.
    let onUnavailable: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onScan = onScan
        controller.onUnavailable = onUnavailable
        return controller
    }

    func updateUIViewController(_ controller: QRScannerViewController, context: Context) {
        controller.onScan = onScan
        controller.onUnavailable = onUnavailable
    }
}

@MainActor
final class QRScannerViewController: UIViewController {
    var onScan: (@MainActor (String) -> Void)?
    var onUnavailable: (@MainActor (String) -> Void)?

    private let scanner = ScannerSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    /// One payload per presentation. See the note above.
    private var hasReported = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let layer = AVCaptureVideoPreviewLayer(session: scanner.captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        Task { await start() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Nothing here is worth leaving a camera running for.
        scanner.stop()
    }

    private func start() async {
        guard await Self.cameraIsPermitted() else {
            onUnavailable?(
                "Camera access is off for Tessalytics. Turn it on in Settings → Tessalytics, or enter the code by hand."
            )
            return
        }

        scanner.start(
            onScan: { [weak self] payload in
                Task { @MainActor in
                    guard let self, !self.hasReported else { return }
                    self.hasReported = true
                    self.scanner.stop()
                    self.onScan?(payload)
                }
            },
            onUnavailable: { [weak self] message in
                Task { @MainActor in self?.onUnavailable?(message) }
            }
        )
    }

    private static func cameraIsPermitted() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }
}

/// Owns the capture session, and the queue that is allowed to touch it.
///
/// The unchecked conformance is load-bearing rather than convenient. AVFoundation's
/// session types are not `Sendable` and configuring or starting one blocks, so it
/// must not happen on the main thread — a sheet's presentation animation stalls
/// visibly if it does. Every access below goes through `queue`, which is what makes
/// the claim true; the one exception is `captureSession`, read on the main actor to
/// build the preview layer, which AVFoundation supports and the compiler cannot see.
private final class ScannerSession: @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.echocool.Tessalytics.scanner")
    /// Held so the metadata output's weak delegate reference stays alive.
    private var coordinator: ScanCoordinator?

    var captureSession: AVCaptureSession { session }

    func start(
        onScan: @escaping @Sendable (String) -> Void,
        onUnavailable: @escaping @Sendable (String) -> Void
    ) {
        queue.async { [self] in
            guard !session.isRunning else { return }

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device)
            else {
                // The simulator has no camera, and this is also what a hardware
                // fault looks like. Either way there is a way forward that is not
                // the camera.
                onUnavailable("No camera is available here. Enter the code shown beside the QR symbol instead.")
                return
            }

            let output = AVCaptureMetadataOutput()
            let coordinator = ScanCoordinator(onScan: onScan)
            self.coordinator = coordinator

            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(coordinator, queue: queue)
                // QR only. Every other symbology is a way for a barcode on a
                // parcel in the back seat to enter this flow.
                output.metadataObjectTypes = [.qr]
            }
            session.commitConfiguration()
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

/// Bridges the capture delegate's callback to the caller.
private final class ScanCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private let onScan: @Sendable (String) -> Void

    init(onScan: @escaping @Sendable (String) -> Void) {
        self.onScan = onScan
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            let payload = metadataObjects
                .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
                .compactMap(\.stringValue)
                .first
        else { return }
        onScan(payload)
    }
}

/// The viewfinder's frame, drawn over the preview.
///
/// A car's screen is large and glossy, and without a target people hold the phone
/// too close for the symbol to fit in frame at all.
struct ScannerReticle: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * 0.72
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .shadow(radius: 8)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
