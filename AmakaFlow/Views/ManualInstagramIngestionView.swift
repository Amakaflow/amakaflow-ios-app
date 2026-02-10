//
//  ManualInstagramIngestionView.swift
//  AmakaFlow
//
//  Manual Instagram workout import: paste caption text + optional URL,
//  parsed via the /ingest/text endpoint.
//

import SwiftUI

struct ManualInstagramIngestionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var captionText: String = ""
    @State private var instagramURL: String = ""
    @State private var state: IngestionState = .idle

    let apiService: APIServiceProviding

    enum IngestionState: Equatable {
        case idle
        case loading
        case success(title: String)
        case error(message: String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $captionText)
                        .frame(minHeight: 120)
                        .font(.body)
                        .accessibilityIdentifier("instagram_caption_editor")
                } header: {
                    Text("Paste the workout caption")
                } footer: {
                    Text("Copy the workout description from the Instagram post and paste it here.")
                }

                Section {
                    TextField("Instagram URL (optional)", text: $instagramURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .textContentType(.URL)
                } header: {
                    Text("Source Link")
                }

                Section {
                    Button(action: ingest) {
                        HStack {
                            if state == .loading {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(buttonLabel)
                        }
                    }
                    .disabled(!canSubmit)
                }

                if case .error(let message) = state {
                    Section {
                        Text(message)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                if case .success(let title) = state {
                    Section {
                        Label(title, systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("Import from Instagram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay(alignment: .top) {
                Text(" ")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("manual_instagram_sheet")
            }
        }
    }

    private var buttonLabel: String {
        switch state {
        case .loading: return "Importing..."
        default: return "Import Workout"
        }
    }

    private var canSubmit: Bool {
        let hasText = !captionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch state {
        case .idle, .error:
            return hasText
        case .loading, .success:
            return false
        }
    }

    private func ingest() {
        state = .loading
        Task {
            do {
                let source = instagramURL.isEmpty ? "instagram" : instagramURL
                let response = try await apiService.ingestText(text: captionText, source: source)
                state = .success(title: response.name ?? "Workout imported")
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                dismiss()
            } catch {
                state = .error(message: error.localizedDescription)
            }
        }
    }
}
