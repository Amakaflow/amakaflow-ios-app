//
//  BarcodeScannerView.swift
//  AmakaFlow
//
//  AVFoundation barcode scanner for food lookup (AMA-1294).
//  Scans UPC/EAN barcodes and calls GET /nutrition/barcode/{code}.
//

import SwiftUI
import AVFoundation

struct BarcodeScannerView: View {
    @ObservedObject var viewModel: FoodLoggingViewModel
    @State private var scannedCode: String?
    @State private var isScanning = true
    @State private var manualCode = ""

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                // Scanner area
                if isScanning && scannedCode == nil {
                    scannerArea
                }

                // Manual entry fallback
                manualEntrySection

                // Error
                if let error = viewModel.errorMessage, viewModel.selectedTab == .barcode {
                    ErrorBanner(message: error)
                }

                // Result
                if let result = viewModel.barcodeResult {
                    barcodeResultView(result)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
    }

    // MARK: - Scanner

    private var scannerArea: some View {
        VStack(spacing: Theme.Spacing.sm) {
            BarcodeScannerUIView(scannedCode: $scannedCode)
                .frame(height: 250)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.Colors.accentBlue.opacity(0.3), lineWidth: 2)
                )

            Text("Point camera at a barcode")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .onChange(of: scannedCode) { code in
            guard let code, !code.isEmpty else { return }
            isScanning = false
            Task {
                await viewModel.lookupBarcode(code: code)
            }
        }
    }

    // MARK: - Manual Entry

    private var manualEntrySection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("Or enter barcode manually")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)

            HStack(spacing: Theme.Spacing.sm) {
                TextField("Barcode number", text: $manualCode)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.surface)
                    .cornerRadius(8)
                    .keyboardType(.numberPad)

                Button {
                    guard !manualCode.isEmpty else { return }
                    scannedCode = manualCode
                    isScanning = false
                    Task {
                        await viewModel.lookupBarcode(code: manualCode)
                    }
                } label: {
                    Text("Look Up")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentBlue)
                        .cornerRadius(8)
                }
                .disabled(manualCode.isEmpty || viewModel.isLoading)
            }
        }
    }

    // MARK: - Result

    private func barcodeResultView(_ result: BarcodeNutritionAPIResponse) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Product header
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(result.productName)
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                if let brand = result.brand {
                    Text(brand)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                if let serving = result.servingSize {
                    Text("Serving: \(serving)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }

            // Macro grid
            MacroTotalsBar(totals: MacroTotalsResponse(
                calories: result.calories,
                proteinG: result.proteinG,
                carbsG: result.carbsG,
                fatG: result.fatG
            ))

            // Extra info
            if result.fiberG != nil || result.sugarG != nil {
                HStack(spacing: Theme.Spacing.lg) {
                    if let fiber = result.fiberG {
                        MacroLabel(label: "Fiber", value: fiber, unit: "g")
                    }
                    if let sugar = result.sugarG {
                        MacroLabel(label: "Sugar", value: sugar, unit: "g")
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
            }

            // Scan again
            Button {
                scannedCode = nil
                viewModel.barcodeResult = nil
                viewModel.errorMessage = nil
                isScanning = true
                manualCode = ""
            } label: {
                Text("Scan Another")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.accentBlue)
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.Colors.accentBlue.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .cornerRadius(12)
    }
}

// MARK: - AVFoundation Barcode Scanner

struct BarcodeScannerUIView: UIViewControllerRepresentable {
    @Binding var scannedCode: String?

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let controller = BarcodeScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, BarcodeScannerDelegate {
        let parent: BarcodeScannerUIView

        init(_ parent: BarcodeScannerUIView) {
            self.parent = parent
        }

        func didScanBarcode(_ code: String) {
            DispatchQueue.main.async {
                self.parent.scannedCode = code
            }
        }
    }
}

protocol BarcodeScannerDelegate: AnyObject {
    func didScanBarcode(_ code: String)
}

class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: BarcodeScannerDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var metadataOutput: AVCaptureMetadataOutput?
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScanner()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let session = captureSession, !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cleanup()
    }

    deinit {
        cleanup()
    }

    private let sessionQueue = DispatchQueue(label: "com.amakaflow.barcode.session")

    private func cleanup() {
        metadataOutput?.setMetadataObjectsDelegate(nil, queue: nil)
        sessionQueue.sync {
            if let session = captureSession, session.isRunning {
                session.stopRunning()
            }
            captureSession?.outputs.forEach { captureSession?.removeOutput($0) }
            captureSession?.inputs.forEach { captureSession?.removeInput($0) }
        }
        captureSession = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        metadataOutput = nil
    }

    private func setupScanner() {
        let session = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            showNoCameraUI()
            return
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .code39]
        }
        self.metadataOutput = metadataOutput

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)

        self.captureSession = session
        self.previewLayer = preview

        sessionQueue.async {
            session.startRunning()
        }
    }

    private func showNoCameraUI() {
        let label = UILabel()
        label.text = "Camera not available"
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasScanned,
              let metadataObject = metadataObjects.first,
              let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
              let stringValue = readableObject.stringValue else { return }

        hasScanned = true
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        captureSession?.stopRunning()
        delegate?.didScanBarcode(stringValue)
    }
}
