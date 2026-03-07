//
//  AIImportView.swift
//  AmakaFlow
//
//  AI-powered workout import via the MCP backend proxy (AMA-849)
//

import SwiftUI

struct AIImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sourceURL: String = ""
    @State private var message: String = ""
    @State private var events: [String] = []
    @State private var state: ImportState = .idle
    @State private var importTask: Task<Void, Never>?

    enum ImportState: Equatable {
        case idle
        case streaming
        case done
        case error(String)
    }

    private var baseURL: String {
        AppEnvironment.current.mcpAPIURL
    }

    /// Auth headers matching APIService.authHeaders, covering E2E and production.
    private var authHeaders: [String: String] {
        var headers = [String: String]()
        #if DEBUG
        if let testAuthSecret = TestAuthStore.shared.authSecret,
           let testUserId = TestAuthStore.shared.userId,
           !testAuthSecret.isEmpty {
            headers["X-Test-Auth"] = testAuthSecret
            headers["X-Test-User-Id"] = testUserId
            return headers
        }
        #endif
        if let token = PairingService.shared.getToken() {
            headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }

    private var profileId: String {
        #if DEBUG
        if let testUserId = TestAuthStore.shared.userId, !testUserId.isEmpty {
            return testUserId
        }
        #endif
        return PairingService.shared.userProfile?.id ?? "unknown"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Workout URL (optional)", text: $sourceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("ai_import_url_field")

                    TextField("What do you want to import?", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("ai_import_message_field")
                } header: {
                    Text("AI Import")
                } footer: {
                    Text("Claude will detect, map, and import your workout automatically.")
                }

                Section {
                    Button(action: startImport) {
                        HStack {
                            if case .streaming = state {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                            }
                            Text(state == .streaming ? "Importing…" : "Start AI Import")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || state == .streaming)
                    .accessibilityIdentifier("ai_import_button")
                }

                if case .error(let msg) = state {
                    Section {
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if !events.isEmpty {
                    Section("Events") {
                        ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                            Text(event)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("AI Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("ai_import_cancel_button")
                }
                if case .done = state {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("ai_import_done_button")
                    }
                }
            }
            .onDisappear {
                importTask?.cancel()
            }
        }
    }

    private func startImport() {
        events = []
        state = .streaming
        importTask = Task {
            do {
                try await streamImport()
                state = .done
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    private func streamImport() async throws {
        guard let url = URL(string: "\(baseURL)/api/v1/ai/import") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var body: [String: String] = [
            "profile_id": profileId,
            "message": message,
        ]
        if !sourceURL.trimmingCharacters(in: .whitespaces).isEmpty {
            body["source_url"] = sourceURL
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard httpResponse.statusCode == 200 else {
            var bodyData = Data()
            for try await byte in bytes { bodyData.append(byte) }
            let detail = String(data: bodyData, encoding: .utf8)?.prefix(200) ?? ""
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(detail)"
            ])
        }

        // SSE parsing: buffer event name and data, flush on blank line.
        var pendingEvent = ""
        var pendingData = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.hasPrefix("event: ") {
                pendingEvent = String(line.dropFirst(7))
                if pendingEvent == "done" { break }
            } else if line.hasPrefix("data: ") {
                pendingData = String(line.dropFirst(6))
            } else if line.isEmpty {
                // Blank line = dispatch the event
                let eventName = pendingEvent.isEmpty ? "message" : pendingEvent
                if !pendingData.isEmpty {
                    let display = "[\(eventName)] \(pendingData)"
                    await MainActor.run { events.append(display) }
                }
                pendingEvent = ""
                pendingData = ""
            }
        }
    }
}

#Preview {
    AIImportView()
}
