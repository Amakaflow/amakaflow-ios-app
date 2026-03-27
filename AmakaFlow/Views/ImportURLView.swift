//
//  ImportURLView.swift
//  AmakaFlow
//
//  Reusable URL import sheet for YouTube, TikTok, Pinterest (AMA-1239)
//

import SwiftUI

struct ImportURLView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url: String = ""
    @State private var state: ImportState = .idle

    let title: String
    let placeholder: String
    let urlValidation: (String) -> Bool
    let importAction: (String) async throws -> IngestInstagramReelResponse

    enum ImportState: Equatable {
        case idle
        case loading
        case success(title: String)
        case error(message: String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .textContentType(.URL)
                        .accessibilityIdentifier("import_url_field")
                } header: {
                    Text("Paste a \(title) URL")
                }

                Section {
                    Button(action: importWorkout) {
                        HStack {
                            if state == .loading {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(buttonLabel)
                        }
                    }
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("import_url_button")
                }

                if case .error(let message) = state {
                    Section {
                        Text(message)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                if case .success(let resultTitle) = state {
                    Section {
                        Label(resultTitle, systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("Import from \(title)")
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
                    .accessibilityIdentifier("import_url_sheet")
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
        !url.isEmpty && urlValidation(url) && state == .idle
    }

    private func importWorkout() {
        state = .loading
        Task {
            do {
                let response = try await importAction(url)
                state = .success(title: response.title ?? "Workout imported")
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                dismiss()
            } catch {
                state = .error(message: error.localizedDescription)
            }
        }
    }
}
