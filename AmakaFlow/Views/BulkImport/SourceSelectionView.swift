//
//  SourceSelectionView.swift
//  AmakaFlow
//
//  Step 1: Choose source type and enter URLs / select images / pick file (AMA-1415)
//

import SwiftUI

struct SourceSelectionView: View {
    @ObservedObject var viewModel: BulkImportViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Import Workouts")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("Choose where to import your workouts from.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, Theme.Spacing.md)

                // Input type picker
                Picker("Source Type", selection: $viewModel.inputType) {
                    ForEach(BulkInputType.allCases, id: \.rawValue) { type in
                        Label(type.displayName, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.md)

                // Source-specific input
                Group {
                    switch viewModel.inputType {
                    case .urls:
                        urlInputSection
                    case .images:
                        imagePlaceholderSection
                    case .file:
                        filePlaceholderSection
                    }
                }

                // Error message
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentRed)
                        .padding(.horizontal, Theme.Spacing.md)
                }

                // Detect button
                Button {
                    Task { await viewModel.detect() }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(viewModel.isLoading ? "Detecting..." : "Detect Workouts")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.accentBlue)
                    .cornerRadius(Theme.CornerRadius.md)
                }
                .disabled(viewModel.isLoading)
                .padding(.horizontal, Theme.Spacing.md)
            }
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    // MARK: - URL Input

    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Workout URLs")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Button {
                    if let clipboard = UIPasteboard.general.string {
                        let lines = clipboard.components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        if !lines.isEmpty {
                            viewModel.urlInputs = lines
                        }
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentBlue)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)

            ForEach(viewModel.urlInputs.indices, id: \.self) { index in
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("https://...", text: $viewModel.urlInputs[index])
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.surface)
                        .cornerRadius(Theme.CornerRadius.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                                .stroke(Theme.Colors.borderLight, lineWidth: 1)
                        )

                    if viewModel.urlInputs.count > 1 {
                        Button {
                            viewModel.removeURL(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(Theme.Colors.accentRed)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }

            Button {
                viewModel.addURL()
            } label: {
                Label("Add URL", systemImage: "plus.circle")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accentBlue)
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
    }

    // MARK: - Image Placeholder

    private var imagePlaceholderSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("Photo import coming soon")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            Button {
                // PhotosPicker will be wired in a future iteration
            } label: {
                Text("Select Photos")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.borderMedium)
                    .cornerRadius(Theme.CornerRadius.md)
            }
            .disabled(true)
            .padding(.horizontal, Theme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }

    // MARK: - File Placeholder

    private var filePlaceholderSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("File import coming soon")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            Button {
                // DocumentPicker will be wired in a future iteration
            } label: {
                Text("Choose File")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.borderMedium)
                    .cornerRadius(Theme.CornerRadius.md)
            }
            .disabled(true)
            .padding(.horizontal, Theme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }
}
