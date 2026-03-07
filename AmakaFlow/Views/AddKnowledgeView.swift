//
//  AddKnowledgeView.swift
//  AmakaFlow
//
//  Sheet for adding a URL or raw text to the user's knowledge library.
//

import SwiftUI

struct AddKnowledgeView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var urlText: String = ""
    @State private var bodyText: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var didSave: Bool = false

    private var bothEmpty: Bool {
        urlText.trimmingCharacters(in: .whitespaces).isEmpty &&
        bodyText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    // URL field
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("URL")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.textSecondary)

                        TextField("https://", text: $urlText)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(Theme.Spacing.md)
                            .background(Theme.Colors.surface)
                            .cornerRadius(Theme.CornerRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
                            )
                            .foregroundColor(Theme.Colors.textPrimary)
                            .font(Theme.Typography.body)
                            .accessibilityIdentifier("knowledge_url_field")
                    }

                    // Manual text field
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("OR PASTE TEXT")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(Theme.Colors.textSecondary)

                        TextEditor(text: $bodyText)
                            .frame(minHeight: 100)
                            .padding(Theme.Spacing.sm)
                            .background(Theme.Colors.surface)
                            .cornerRadius(Theme.CornerRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
                            )
                            .foregroundColor(Theme.Colors.textPrimary)
                            .font(Theme.Typography.body)
                            .scrollContentBackground(.hidden)
                            .accessibilityIdentifier("knowledge_text_field")
                    }

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(Theme.Typography.caption)
                            .foregroundColor(.red)
                    }

                    // Confirmation label
                    if didSave {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Theme.Colors.accentGreen)
                            Text("Saving to library in the background…")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.accentGreen)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.lg)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Add to Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Theme.Colors.accentBlue)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .foregroundColor(Theme.Colors.accentBlue)
                    .disabled(bothEmpty || isSaving)
                    .accessibilityIdentifier("knowledge_save_button")
                }
            }
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        errorMessage = nil

        let trimmedURL = urlText.trimmingCharacters(in: .whitespaces)
        let trimmedText = bodyText.trimmingCharacters(in: .whitespaces)

        do {
            _ = try await KnowledgeService.shared.ingest(
                url: trimmedURL.isEmpty ? nil : trimmedURL,
                text: trimmedText.isEmpty ? nil : trimmedText
            )
            didSave = true
            isSaving = false

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}

// MARK: - Preview

#Preview {
    AddKnowledgeView()
        .preferredColorScheme(.dark)
}
