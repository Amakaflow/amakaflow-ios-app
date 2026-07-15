//
//  SocialImportFlowView.swift
//  AmakaFlow
//
//  AMA-2285: URL / plain-text / screenshot entry sheets for social import.
//  No Instagram scraping — URL + text + image are posted to the ingestor.
//

import PhotosUI
import SwiftUI

struct SocialImportFlowView: View {
    enum Mode: Equatable {
        case url(platformHint: SocialImportPlatform?)
        case plainText(platform: SocialImportPlatform)
    }

    let mode: Mode
    /// Prefill URL field (Library paste / clipboard routing — AMA-2297).
    var initialURL: String? = nil
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SocialImportViewModel()
    @State private var urlText: String = ""
    @State private var plainText: String = ""
    @State private var didApplyInitialURL = false

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .preview, .saving, .saved:
                    if let draft = viewModel.draft {
                        SocialImportPreviewView(viewModel: viewModel, draft: draft) {
                            onSaved?()
                            dismiss()
                        }
                    } else {
                        inputForm
                    }
                default:
                    inputForm
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .accessibilityIdentifier("social_import_flow")
            .onAppear {
                applyInitialURLIfNeeded()
            }
        }
    }

    private func applyInitialURLIfNeeded() {
        guard !didApplyInitialURL else { return }
        didApplyInitialURL = true
        guard case .url = mode,
              let initialURL,
              !initialURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        urlText = SocialImportPlatform.normalizeForIngest(initialURL)
    }

    private var navigationTitle: String {
        switch mode {
        case .url(let hint):
            return "Import from \(hint?.displayName ?? "Link")"
        case .plainText(let platform):
            return platform == .manual ? "Paste Workout Text" : "Import from \(platform.displayName)"
        }
    }

    @ViewBuilder
    private var inputForm: some View {
        Form {
            switch mode {
            case .url(let hint):
                Section {
                    TextField(urlPlaceholder(for: hint), text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("social_import_url_field")
                } header: {
                    Text("Paste a workout URL")
                } footer: {
                    Text("We send the link to AmakaFlow's import service — no on-device scraping.")
                }

            case .plainText:
                Section {
                    TextEditor(text: $plainText)
                        .frame(minHeight: 140)
                        .accessibilityIdentifier("social_import_text_editor")
                } header: {
                    Text("Paste workout text")
                } footer: {
                    Text("Captions, notes, or a written plan. You can edit everything before saving.")
                }
            }

            Section {
                Button {
                    startImport()
                } label: {
                    HStack {
                        if viewModel.phase == .importing {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text(viewModel.phase == .importing ? "Importing…" : "Import Workout")
                    }
                }
                .disabled(!canSubmit || viewModel.phase == .importing)
                .accessibilityIdentifier("social_import_submit")
            }

            if case .failed(let failure) = viewModel.phase {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(failure.title)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.accentOrange)
                        Text(failure.userMessage)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .accessibilityIdentifier("social_import_error")
                }
            }
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .url:
            return !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .plainText:
            return !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func urlPlaceholder(for hint: SocialImportPlatform?) -> String {
        switch hint {
        case .youtube: return "https://youtube.com/watch?v=…"
        case .tiktok: return "https://tiktok.com/@…/video/…"
        case .instagram: return "https://instagram.com/reels/…"
        default: return "https://…"
        }
    }

    private func startImport() {
        Task {
            switch mode {
            case .url(let hint):
                await viewModel.importURL(urlText, platformHint: hint)
            case .plainText(let platform):
                await viewModel.importPlainText(plainText, platform: platform)
            }
        }
    }
}

/// Screenshot / photo import entry (PhotosPicker → ingestSocialImage).
struct ImageImportView: View {
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SocialImportViewModel()
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .preview, .saving, .saved:
                    if let draft = viewModel.draft {
                        SocialImportPreviewView(viewModel: viewModel, draft: draft) {
                            onSaved?()
                            dismiss()
                        }
                    } else {
                        pickerForm
                    }
                default:
                    pickerForm
                }
            }
            .navigationTitle("Image Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .accessibilityIdentifier("image_import_sheet")
            .onChange(of: pickerItem) { _, newItem in
                Task { await loadAndImport(newItem) }
            }
        }
    }

    private var pickerForm: some View {
        Form {
            Section {
                PhotosPicker(
                    selection: $pickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(
                        viewModel.phase == .importing ? "Importing…" : "Choose Screenshot",
                        systemImage: "photo.on.rectangle.angled"
                    )
                }
                .disabled(viewModel.phase == .importing)
                .accessibilityIdentifier("image_import_picker")
            } footer: {
                Text("Pick a workout screenshot. We send the image to the import service — you can edit the result before saving.")
            }

            if viewModel.phase == .importing {
                Section {
                    ProgressView("Reading workout from image…")
                }
            }

            if case .failed(let failure) = viewModel.phase {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(failure.title)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.accentOrange)
                        Text(failure.userMessage)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .accessibilityIdentifier("image_import_error")
                }
            }
        }
    }

    private func loadAndImport(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                viewModel.phase = .failed(.parse(message: "Couldn't read that photo. Try another screenshot."))
                return
            }
            await viewModel.importImageData(data, filename: "screenshot.jpg")
        } catch {
            viewModel.phase = .failed(SocialImportFailure.map(error))
        }
    }
}

#Preview("URL") {
    SocialImportFlowView(mode: .url(platformHint: .youtube))
}

#Preview("Image") {
    ImageImportView()
}
