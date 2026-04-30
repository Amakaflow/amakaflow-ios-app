//
//  DeepLinkImportView.swift
//  AmakaFlow
//
//  Import preview UI shown when the app is opened via a Universal Link or custom URL scheme.
//  Reuses patterns from ShareExtensionView (AMA-1257) and APIService ingestion methods.
//  AMA-1259: Deep link import on iOS
//

import SwiftUI
import Combine

/// ViewModel for the deep link import flow
@MainActor
class DeepLinkImportViewModel: ObservableObject {

    @Published var state: DeepLinkImportState = .ready
    @Published var importResponse: DeepLinkIngestResponse?
    @Published var importTrigger: UUID?

    let urlString: String
    let platform: DeepLinkPlatform

    init(urlString: String) {
        self.urlString = urlString
        self.platform = DeepLinkImportViewModel.detectPlatform(from: urlString)
    }

    /// Request an import — sets a trigger that the view's .task(id:) picks up
    func requestImport() {
        importTrigger = UUID()
    }

    /// Start the import by calling POST /ingest/{source}
    func startImport() async {
        state = .importing

        do {
            let response = try await performImport()
            importResponse = response
            state = .success(response.title ?? "Workout imported")
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Networking

    private func performImport() async throws -> DeepLinkIngestResponse {
        let ingestorURL = AppEnvironment.current.ingestorAPIURL
        let source = platform.ingestSource
        guard let endpoint = URL(string: "\(ingestorURL)/ingest/\(source)") else {
            throw DeepLinkImportError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        // Auth headers — Clerk session token
        var headers = ["Content-Type": "application/json"]
        do {
            if let token = try await AuthViewModel.shared.token() {
                headers["Authorization"] = "Bearer \(token)"
            } else {
                throw DeepLinkImportError.unauthorized
            }
        } catch {
            print("[DeepLinkImport] Failed to get Clerk token: \(error.localizedDescription)")
            throw DeepLinkImportError.unauthorized
        }

        request.allHTTPHeaderFields = headers

        let body: [String: Any] = ["url": urlString]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        #if DEBUG
        print("[DeepLinkImport] POST \(endpoint) for URL: \(urlString)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepLinkImportError.invalidResponse
        }

        #if DEBUG
        print("[DeepLinkImport] Status: \(httpResponse.statusCode)")
        #endif

        if httpResponse.statusCode == 401 {
            throw DeepLinkImportError.unauthorized
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DeepLinkImportError.serverError(httpResponse.statusCode, body)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(DeepLinkIngestResponse.self, from: data)
    }

    // MARK: - Platform Detection (mirrors PlatformDetector from AMA-1257)

    static func detectPlatform(from urlString: String) -> DeepLinkPlatform {
        let lowered = urlString.lowercased()

        if lowered.contains("youtube.com") || lowered.contains("youtu.be") {
            return .youtube
        }
        if lowered.contains("instagram.com") || lowered.contains("instagr.am") {
            return .instagram
        }
        if lowered.contains("tiktok.com") {
            return .tiktok
        }
        if lowered.contains("pinterest.com") || lowered.contains("pin.it") {
            return .pinterest
        }
        if lowered.contains("twitter.com") || lowered.contains("x.com") || lowered.contains("t.co/") {
            return .twitter
        }
        if lowered.contains("facebook.com") || lowered.contains("fb.watch") || lowered.contains("fb.com") {
            return .facebook
        }
        if lowered.contains("reddit.com") || lowered.contains("redd.it") {
            return .reddit
        }

        return .web
    }
}

// MARK: - Supporting Types

enum DeepLinkImportState: Equatable {
    case ready
    case importing
    case success(String)
    case error(String)
}

struct DeepLinkIngestResponse: Codable {
    let title: String?
    let workoutType: String?
    let source: String?
    let needsClarification: Bool?
}

enum DeepLinkPlatform: String, CaseIterable {
    case youtube, instagram, tiktok, pinterest, twitter, facebook, reddit, web

    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .pinterest: return "Pinterest"
        case .twitter: return "X / Twitter"
        case .facebook: return "Facebook"
        case .reddit: return "Reddit"
        case .web: return "Web Link"
        }
    }

    var iconSystemName: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .instagram: return "camera.fill"
        case .tiktok: return "music.note"
        case .pinterest: return "pin.fill"
        case .twitter: return "at"
        case .facebook: return "person.2.fill"
        case .reddit: return "bubble.left.fill"
        case .web: return "safari.fill"
        }
    }

    var accentColorHex: String {
        switch self {
        case .youtube: return "#FF0000"
        case .instagram: return "#E4405F"
        case .tiktok: return "#000000"
        case .pinterest: return "#E60023"
        case .twitter: return "#1DA1F2"
        case .facebook: return "#1877F2"
        case .reddit: return "#FF4500"
        case .web: return "#007AFF"
        }
    }

    var ingestSource: String {
        switch self {
        case .youtube: return "youtube"
        case .instagram: return "instagram_reel"
        case .tiktok: return "tiktok"
        case .pinterest: return "pinterest"
        default: return "url"
        }
    }
}

enum DeepLinkImportError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid server response"
        case .unauthorized: return "Not signed in. Open AmakaFlow and sign in first."
        case .serverError(let code, let body):
            return "Server error (\(code)): \(String(body.prefix(200)))"
        }
    }
}

// MARK: - View

/// Import preview sheet shown when the app opens via a deep link
struct DeepLinkImportView: View {
    @StateObject private var viewModel: DeepLinkImportViewModel
    let onDismiss: () -> Void

    init(urlString: String, onDismiss: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: DeepLinkImportViewModel(urlString: urlString))
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Platform card
                VStack(spacing: 16) {
                    // Platform icon + name
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.platform.iconSystemName)
                            .font(.title2)
                            .foregroundColor(platformColor)
                            .frame(width: 44, height: 44)
                            .background(platformColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.platform.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(viewModel.urlString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                                .truncationMode(.middle)
                        }

                        Spacer()
                    }
                    .padding(.top, 8)

                    // State-dependent content
                    switch viewModel.state {
                    case .ready:
                        Button {
                            viewModel.requestImport()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Import Workout")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                    case .importing:
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Importing...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    case .success(let title):
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)
                                Text(title)
                                    .font(.subheadline.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            Button("Done") {
                                onDismiss()
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                    case .error(let message):
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("Import Failed")
                                    .font(.subheadline.weight(.medium))
                            }
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            Button("Try Again") {
                                viewModel.requestImport()
                            }
                            .font(.subheadline.weight(.medium))
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)

                Spacer()
            }
            .navigationTitle("Import Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
        .task(id: viewModel.importTrigger) {
            guard viewModel.importTrigger != nil else { return }
            await viewModel.startImport()
        }
        .onAppear {
            // Auto-start import when the sheet appears
            viewModel.requestImport()
        }
    }

    /// Parse the hex color for the platform accent
    private var platformColor: Color {
        let hex = viewModel.platform.accentColorHex
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        return Color(
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
    }
}
