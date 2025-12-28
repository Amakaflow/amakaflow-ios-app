import SwiftUI

struct PairingView: View {
    @ObservedObject private var pairingService = PairingService.shared
    @State private var manualCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showScanner = false

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                Spacer()

                // App Icon
                Image("AppIcon")
                    .resizable()
                    .frame(width: 100, height: 100)
                    .cornerRadius(22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                VStack(spacing: 8) {
                    Text("Connect to AmakaFlow")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Scan the QR code or enter the 6-character code from the AmakaFlow web app")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // QR Scanner Button
                Button {
                    showScanner = true
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)

                // Divider
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("or")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.secondary.opacity(0.3))
                }
                .padding(.horizontal, 32)

                // Manual Code Entry
                VStack(spacing: 16) {
                    TextField("Enter 6-character code", text: $manualCode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.title3, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .onChange(of: manualCode) { _, newValue in
                            // Filter to alphanumeric and limit to 6 chars
                            let filtered = newValue.uppercased().filter { $0.isLetter || $0.isNumber }
                            manualCode = String(filtered.prefix(6))
                        }

                    Button {
                        Task { await pair(with: manualCode) }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Connect")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .background(manualCode.count == 6 ? Color.blue : Color.gray.opacity(0.5))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(manualCode.count != 6 || isLoading)
                }
                .padding(.horizontal, 32)

                // Error Message
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // Help text
                VStack(spacing: 4) {
                    Text("To get a pairing code:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("amakaflow.com → Settings → Mobile App")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 32)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showScanner) {
                QRScannerView { code in
                    showScanner = false
                    Task { await pair(with: code) }
                }
            }
        }
    }

    private func pair(with code: String) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        print("[PairingView] Pairing started with code length: \(code.count)")

        do {
            // Try to parse QR code JSON if it looks like JSON
            var pairingCode = code
            if code.hasPrefix("{") {
                print("[PairingView] Parsing QR code JSON")
                if let data = code.data(using: .utf8),
                   let json = try? JSONDecoder().decode(QRCodeData.self, from: data) {
                    pairingCode = json.token
                    print("[PairingView] Extracted token from QR JSON")
                }
            }

            _ = try await pairingService.pair(code: pairingCode)
            print("[PairingView] Pairing successful!")
            // Success - isPaired will update and trigger navigation
        } catch {
            print("[PairingView] Pairing failed: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }
}

// QR code JSON structure from web app
struct QRCodeData: Codable {
    let type: String
    let version: Int
    let token: String
    let apiUrl: String

    enum CodingKeys: String, CodingKey {
        case type, version, token
        case apiUrl = "api_url"
    }
}

#Preview {
    PairingView()
}
