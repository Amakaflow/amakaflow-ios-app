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

    enum ImportState {
        case idle
        case streaming
        case done
        case error(String)
    }

    private var baseURL: String {
        AppEnvironment.current.mcpAPIURL
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

                if !events.isEmpty {
                    Section("Events") {
                        ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                            Text(event)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if case .error(let msg) = state {
                    Section {
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("AI Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if case .done = state {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private func startImport() {
        events = []
        state = .streaming

        Task {
            do {
                try await streamImport()
                state = .done
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

        var body: [String: String] = [
            "profile_id": "current_user",
            "message": message,
        ]
        if !sourceURL.trimmingCharacters(in: .whitespaces).isEmpty {
            body["source_url"] = sourceURL
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        var dataBuffer = ""
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                dataBuffer = String(line.dropFirst(6))
            } else if line.hasPrefix("event: ") {
                let eventName = String(line.dropFirst(7))
                if eventName == "done" { break }
                if !dataBuffer.isEmpty {
                    let display = "[\(eventName)] \(dataBuffer)"
                    await MainActor.run { events.append(display) }
                    dataBuffer = ""
                }
            }
        }
    }
}

#Preview {
    AIImportView()
}
