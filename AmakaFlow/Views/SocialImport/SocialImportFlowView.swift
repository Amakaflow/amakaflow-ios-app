//
//  SocialImportFlowView.swift
//  AmakaFlow
//
//  AMA-2285: URL / plain-text / screenshot entry sheets for social import.
//  Daily Driver chrome: pill URL input, processing animation, bottom-sheet layout.
//

import PhotosUI
import SwiftUI

struct SocialImportFlowView: View {
    enum Mode: Equatable {
        case url(platformHint: SocialImportPlatform?)
        case plainText(platform: SocialImportPlatform)
    }

    let mode: Mode
    var initialURL: String?
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SocialImportViewModel()
    @State private var urlText: String = ""
    @State private var plainText: String = ""
    @State private var didApplyInitialURL = false
    @State private var processingStep = 0

    private let importSteps = [
        "Fetching your link…",
        "Reading caption & video…",
        "Extracting exercises & sets…",
        "Building your workout…"
    ]

    init(
        mode: Mode,
        initialURL: String? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.initialURL = initialURL
        self.onSaved = onSaved
    }

    var body: some View {
        Group {
            switch contentPhase {
            case .importing:
                importingSheet
            case .preview:
                previewSheet
            case .input:
                inputSheet
            }
        }
        .accessibilityIdentifier("social_import_flow")
        .onAppear { applyInitialURLIfNeeded() }
        .task(id: viewModel.phase) {
            await animateImportStepsWhileImporting()
        }
    }

    private enum ContentPhase {
        case input
        case importing
        case preview
    }

    private var contentPhase: ContentPhase {
        switch viewModel.phase {
        case .importing:
            return .importing
        case .preview, .saving, .saved:
            return viewModel.draft == nil ? .input : .preview
        case .failed:
            return viewModel.draft == nil ? .input : .preview
        default:
            return .input
        }
    }

    private var sheetTitle: String {
        switch contentPhase {
        case .importing:
            return "Importing…"
        case .preview:
            return "Review & save"
        case .input:
            switch mode {
            case .url:
                return "Import from URL"
            case .plainText(let platform):
                return platform == .manual ? "Paste workout text" : "Import from \(platform.displayName)"
            }
        }
    }

    @ViewBuilder
    private var inputSheet: some View {
        DDBottomSheetChrome(title: sheetTitle) {
            VStack(alignment: .leading, spacing: 16) {
                switch mode {
                case .url(let hint):
                    DDURLPillInput(
                        text: $urlText,
                        placeholder: urlPlaceholder(for: hint)
                    ) {
                        if let clip = UIPasteboard.general.string {
                            urlText = SocialImportPlatform.normalizeForIngest(clip)
                        }
                    }
                    .accessibilityIdentifier("social_import_url_field")

                    Text("Instagram, TikTok, or YouTube — we pull the workout out of the post.")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .padding(.horizontal, 4)

                case .plainText:
                    TextEditor(text: $plainText)
                        .font(Theme.Typography.body)
                        .frame(minHeight: 140)
                        .padding(12)
                        .background(DailyDriver.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                                .stroke(Theme.Colors.borderLight, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))
                        .accessibilityIdentifier("social_import_text_editor")

                    Text("Captions, notes, or a written plan. You can edit everything before saving.")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                if case .failed(let failure) = viewModel.phase {
                    importErrorBlock(failure)
                }

                HStack {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(AFGhostButtonStyle(size: .md, isWide: false))

                    Spacer()

                    Button {
                        startImport()
                    } label: {
                        Text("Import workout")
                    }
                    .buttonStyle(AFPrimaryButtonStyle(size: .md))
                    .disabled(!canSubmit || viewModel.phase == .importing)
                    .accessibilityIdentifier("social_import_submit")
                }
            }
        }
    }

    @ViewBuilder
    private var importingSheet: some View {
        DDBottomSheetChrome(title: sheetTitle) {
            DDImportProcessingView(
                urlPreview: truncatedURLPreview,
                stepIndex: $processingStep,
                steps: importSteps
            )
        }
    }

    @ViewBuilder
    private var previewSheet: some View {
        if let draft = viewModel.draft {
            SocialImportDetailPreviewView(
                viewModel: viewModel,
                draft: draft,
                onLibraryReload: { onSaved?() },
                onDismiss: {
                    onSaved?()
                    dismiss()
                }
            )
        } else {
            inputSheet
        }
    }

    private var truncatedURLPreview: String {
        let raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count > 34 else { return raw.isEmpty ? "your link" : raw }
        return String(raw.prefix(31)) + "…"
    }

    @ViewBuilder
    private func importErrorBlock(_ failure: SocialImportFailure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(failure.title)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.accentOrange)
            Text(failure.userMessage)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DailyDriver.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))
        .accessibilityIdentifier("social_import_error")
    }

    private func applyInitialURLIfNeeded() {
        guard !didApplyInitialURL else { return }
        didApplyInitialURL = true
        guard case .url = mode,
              let initialURL,
              !initialURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        urlText = SocialImportPlatform.normalizeForIngest(initialURL)
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
        default: return "Paste a workout link…"
        }
    }

    private func startImport() {
        processingStep = 0
        Task {
            switch mode {
            case .url(let hint):
                await viewModel.importURL(urlText, platformHint: hint)
            case .plainText(let platform):
                await viewModel.importPlainText(plainText, platform: platform)
            }
        }
    }

    private func animateImportStepsWhileImporting() async {
        guard case .importing = viewModel.phase else { return }
        processingStep = 0
        for step in 0..<(importSteps.count - 1) {
            do {
                try await Task.sleep(nanoseconds: 850_000_000)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard case .importing = viewModel.phase else { return }
            processingStep = step + 1
        }
    }
}

/// Screenshot / photo import entry (PhotosPicker → ingestSocialImage).
struct ImageImportView: View {
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SocialImportViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var processingStep = 0

    private let importSteps = [
        "Reading your screenshot…",
        "Detecting exercises…",
        "Building your workout…"
    ]

    var body: some View {
        Group {
            switch viewModel.phase {
            case .importing:
                DDBottomSheetChrome(title: "Importing…") {
                    DDImportProcessingView(
                        urlPreview: "screenshot",
                        stepIndex: $processingStep,
                        steps: importSteps
                    )
                }
            case .preview, .saving, .saved:
                if let draft = viewModel.draft {
                    SocialImportDetailPreviewView(
                        viewModel: viewModel,
                        draft: draft,
                        onLibraryReload: { onSaved?() },
                        onDismiss: {
                            onSaved?()
                            dismiss()
                        }
                    )
                } else {
                    pickerSheet
                }
            case .failed:
                if let draft = viewModel.draft {
                    SocialImportDetailPreviewView(
                        viewModel: viewModel,
                        draft: draft,
                        onLibraryReload: { onSaved?() },
                        onDismiss: {
                            onSaved?()
                            dismiss()
                        }
                    )
                } else {
                    pickerSheet
                }
            default:
                pickerSheet
            }
        }
        .accessibilityIdentifier("image_import_sheet")
        .onChange(of: pickerItem) { _, newItem in
            Task { await loadAndImport(newItem) }
        }
        .task(id: viewModel.phase) {
            await animateImportStepsWhileImporting()
        }
    }

    private var pickerSheet: some View {
        DDBottomSheetChrome(title: "Screenshot") {
            VStack(spacing: 12) {
                PhotosPicker(
                    selection: $pickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    DDDoorRow(
                        icon: "photo.on.rectangle.angled",
                        iconBackground: DailyDriver.purple,
                        title: "Choose screenshot",
                        subtitle: "Workout photo → editable draft"
                    ) {}
                }
                .disabled(viewModel.phase == .importing)
                .accessibilityIdentifier("image_import_picker")

                Text("We send the image to the import service — you can edit the result before saving.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Colors.textSecondary)

                if case .failed(let failure) = viewModel.phase {
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

                Button("Cancel") { dismiss() }
                    .buttonStyle(AFGhostButtonStyle(size: .md))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func loadAndImport(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        processingStep = 0
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

    private func animateImportStepsWhileImporting() async {
        guard case .importing = viewModel.phase else { return }
        processingStep = 0
        for step in 0..<(importSteps.count - 1) {
            do {
                try await Task.sleep(nanoseconds: 850_000_000)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard case .importing = viewModel.phase else { return }
            processingStep = step + 1
        }
    }
}

#Preview("URL") {
    SocialImportFlowView(mode: .url(platformHint: .youtube))
}

#Preview("Image") {
    ImageImportView()
}
