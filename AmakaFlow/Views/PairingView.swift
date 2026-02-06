import SwiftUI

struct PairingView: View {
    @EnvironmentObject var pairingService: PairingService
    @State private var manualCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showScanner = false

    // E2E Testing bypass (DEBUG only, non-production)
    #if DEBUG
    @State private var showE2EDialog = false
    @State private var e2eAuthSecret = TestAuthStore.shared.authSecret ?? ""
    @State private var e2eUserId = TestAuthStore.shared.userId ?? ""
    #endif

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
                .padding(.bottom, 16)

                // E2E Testing bypass button (DEBUG only, non-production)
                #if DEBUG
                if AppEnvironment.current != .production {
                    Button {
                        showE2EDialog = true
                    } label: {
                        Text("Skip for E2E Testing")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .accessibilityIdentifier("e2e_skip_button")
                    .padding(.bottom, 16)
                }
                #endif
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showScanner) {
                QRScannerView { code in
                    showScanner = false
                    Task { await pair(with: code) }
                }
            }
            #if DEBUG
            .sheet(isPresented: $showE2EDialog) {
                E2ETestingDialog(
                    authSecret: $e2eAuthSecret,
                    userId: $e2eUserId,
                    onCancel: {
                        showE2EDialog = false
                        e2eAuthSecret = ""
                        e2eUserId = ""
                    },
                    onEnable: {
                        pairingService.enableTestMode(authSecret: e2eAuthSecret, userId: e2eUserId)
                        showE2EDialog = false
                    }
                )
                .presentationDetents([.medium])
                .onAppear {
                    // Auto-submit if fields were pre-filled from env vars (AMA-545)
                    if !e2eAuthSecret.isEmpty && !e2eUserId.isEmpty {
                        print("[E2ETestingDialog] Auto-submitting with pre-filled credentials")
                        pairingService.enableTestMode(authSecret: e2eAuthSecret, userId: e2eUserId)
                        showE2EDialog = false
                    }
                }
            }
            #endif
            #if DEBUG
            .onAppear {
                // Log env var state for E2E debugging (AMA-545)
                let hasAuthSecret = TestAuthStore.shared.authSecret != nil
                let hasUserId = TestAuthStore.shared.userId != nil
                print("[PairingView] onAppear - hasAuthSecret=\(hasAuthSecret), hasUserId=\(hasUserId), env=\(AppEnvironment.current)")

                // Auto-enable E2E test mode if env vars are present (AMA-545)
                // This handles cases where PairingService.init() didn't pick up env vars
                if AppEnvironment.current != .production,
                   let authSecret = TestAuthStore.shared.authSecret,
                   let userId = TestAuthStore.shared.userId,
                   !authSecret.isEmpty, !userId.isEmpty {
                    print("[PairingView] Auto-enabling E2E test mode from env vars")
                    pairingService.enableTestMode(authSecret: authSecret, userId: userId)
                }
            }
            #endif
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

// MARK: - E2E Testing Dialog (DEBUG only)
#if DEBUG
struct E2ETestingDialog: View {
    @Binding var authSecret: String
    @Binding var userId: String
    let onCancel: () -> Void
    let onEnable: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enable E2E Test Mode")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Enter test credentials to bypass authentication for E2E testing.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auth Secret")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Auth Secret", text: $authSecret)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("e2e_auth_secret")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("User ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("User ID", text: $userId)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("e2e_user_id")
                    }
                }

                Spacer()

                HStack(spacing: 16) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(.red)

                    Spacer()

                    Button("Enable & Skip Pairing") {
                        onEnable()
                    }
                    .accessibilityIdentifier("e2e_enable_button")
                    .disabled(authSecret.isEmpty || userId.isEmpty)
                }
            }
            .padding()
            .navigationBarHidden(true)
        }
    }
}
#endif

#Preview {
    PairingView()
        .environmentObject(PairingService.shared)
}
