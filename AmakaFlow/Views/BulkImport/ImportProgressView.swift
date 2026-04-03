//
//  ImportProgressView.swift
//  AmakaFlow
//
//  Step 5: Show import progress and final results (AMA-1415)
//

import SwiftUI

struct ImportProgressView: View {
    @ObservedObject var viewModel: BulkImportViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            // Progress indicator
            VStack(spacing: Theme.Spacing.md) {
                if viewModel.importComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(Theme.Colors.accentGreen)

                    Text("Import Complete")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)
                } else if viewModel.errorMessage != nil {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(Theme.Colors.accentRed)

                    Text("Import Failed")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accentBlue))
                        .scaleEffect(1.5)

                    Text("Importing workouts...")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ProgressView(value: Double(viewModel.importProgress), total: 100)
                    .progressViewStyle(LinearProgressViewStyle(tint: Theme.Colors.accentBlue))
                    .scaleEffect(x: 1, y: 2, anchor: .center)

                HStack {
                    Text("\(viewModel.importProgress)%")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)

                    Spacer()

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.accentRed)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)

            // Results list
            if !viewModel.importResults.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Results")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.horizontal, Theme.Spacing.md)

                    ScrollView {
                        VStack(spacing: Theme.Spacing.xs) {
                            ForEach(viewModel.importResults) { result in
                                ImportResultRow(result: result)
                                    .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            }

            Spacer()

            // Action buttons
            VStack(spacing: Theme.Spacing.sm) {
                if viewModel.importComplete || viewModel.errorMessage != nil {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(Theme.Colors.accentBlue)
                            .cornerRadius(Theme.CornerRadius.md)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                } else {
                    Button {
                        viewModel.cancelImport()
                    } label: {
                        Text("Cancel Import")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.accentRed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(Theme.Colors.surface)
                            .cornerRadius(Theme.CornerRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .stroke(Theme.Colors.accentRed.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
            }
            .padding(.bottom, Theme.Spacing.lg)
        }
    }
}

// MARK: - Import Result Row

struct ImportResultRow: View {
    let result: ImportResult

    private var statusIcon: String {
        switch result.status {
        case "success": return "checkmark.circle.fill"
        case "skipped": return "minus.circle.fill"
        default: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch result.status {
        case "success": return Theme.Colors.accentGreen
        case "skipped": return Theme.Colors.textSecondary
        default: return Theme.Colors.accentRed
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)

                if let error = result.error {
                    Text(error)
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.accentRed)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
