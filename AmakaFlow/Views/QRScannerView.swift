import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.onCodeScanned = { code in
            onCodeScanned(code)
        }
        vc.onDismiss = {
            dismiss()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var onCodeScanned: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupOverlay()
    }

    private func setupCamera() {
        // Check camera permission
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("[QRScanner] Camera auth status = \(status.rawValue)")

        switch status {
        case .authorized:
            print("[QRScanner] Camera authorized")
            setupCaptureSession()
        case .notDetermined:
            print("[QRScanner] Requesting camera permission")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        print("[QRScanner] Camera permission granted")
                        self?.setupCaptureSession()
                    } else {
                        print("[QRScanner] Camera permission denied")
                        self?.showPermissionDenied()
                    }
                }
            }
        default:
            print("[QRScanner] Camera not authorized (status: \(status.rawValue))")
            showPermissionDenied()
        }
    }

    private func setupCaptureSession() {
        captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              let captureSession = captureSession,
              captureSession.canAddInput(videoInput) else {
            showCameraError()
            return
        }

        captureSession.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.frame = view.layer.bounds
        previewLayer?.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(previewLayer!, at: 0)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    private func setupOverlay() {
        // Semi-transparent overlay
        let overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlayView.isUserInteractionEnabled = false

        // Create cutout in center
        let scanSize: CGFloat = 250
        let scanRect = CGRect(
            x: (view.bounds.width - scanSize) / 2,
            y: (view.bounds.height - scanSize) / 2 - 50,
            width: scanSize,
            height: scanSize
        )

        let path = UIBezierPath(rect: overlayView.bounds)
        path.append(UIBezierPath(roundedRect: scanRect, cornerRadius: 12).reversing())

        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        overlayView.layer.mask = maskLayer

        view.addSubview(overlayView)

        // Add scan frame border
        let frameView = UIView(frame: scanRect)
        frameView.layer.borderColor = UIColor.white.cgColor
        frameView.layer.borderWidth = 3
        frameView.layer.cornerRadius = 12
        frameView.backgroundColor = .clear
        view.addSubview(frameView)

        // Add instructions label
        let label = UILabel()
        label.text = "Point camera at QR code"
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: frameView.bottomAnchor, constant: 24)
        ])

        // Add close button
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func closeTapped() {
        captureSession?.stopRunning()
        onDismiss?()
    }

    private func showPermissionDenied() {
        let alert = UIAlertController(
            title: "Camera Access Required",
            message: "Please enable camera access in Settings to scan QR codes.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.onDismiss?()
        })
        present(alert, animated: true)
    }

    private func showCameraError() {
        let alert = UIAlertController(
            title: "Camera Error",
            message: "Unable to access the camera. Please try again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.onDismiss?()
        })
        present(alert, animated: true)
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScanned,
              let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = metadataObject.stringValue else {
            return
        }

        hasScanned = true
        captureSession?.stopRunning()

        print("[QRScanner] Code scanned (\(code.count) chars)")

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        onCodeScanned?(code)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
}

#Preview {
    QRScannerView { code in
        print("Scanned: \(code)")
    }
}
