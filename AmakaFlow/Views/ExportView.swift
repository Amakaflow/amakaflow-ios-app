//
//  ExportView.swift
//  AmakaFlow
//
//  AMA-1233: Workout export to FIT (Garmin) and CSV (Strong) formats
//

import SwiftUI

enum ExportFormat: String, CaseIterable {
    case fit = "FIT"
    case csv = "CSV"

    var displayName: String {
        switch self {
        case .fit: return "FIT (Garmin)"
        case .csv: return "CSV (Strong)"
        }
    }

    var fileExtension: String {
        switch self {
        case .fit: return "fit"
        case .csv: return "csv"
        }
    }

    var icon: String {
        switch self {
        case .fit: return "arrow.down.doc"
        case .csv: return "tablecells"
        }
    }
}

struct ExportView: View {
    let workoutId: String
    let workoutName: String

    @Environment(\.dismiss) var dismiss

    @State private var selectedFormat: ExportFormat = .fit
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var exportedFileURL: URL?
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                // Format Picker
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Export Format")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)

                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Button(action: { selectedFormat = format }) {
                            HStack(spacing: Theme.Spacing.md) {
                                Image(systemName: format.icon)
                                    .font(.system(size: 20))
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(format.displayName)
                                        .font(Theme.Typography.bodyBold)
                                    Text(format == .fit ? "Compatible with Garmin Connect" : "Compatible with Strong app")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }

                                Spacer()

                                Image(systemName: selectedFormat == format ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundColor(selectedFormat == format ? Theme.Colors.accentBlue : Theme.Colors.textSecondary)
                            }
                            .foregroundColor(Theme.Colors.textPrimary)
                            .padding(Theme.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .fill(selectedFormat == format ? Theme.Colors.accentBlue.opacity(0.1) : Theme.Colors.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .stroke(selectedFormat == format ? Theme.Colors.accentBlue : Theme.Colors.borderLight, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)

                Spacer()

                // Error Message
                if let errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 14))
                        Text(errorMessage)
                            .font(Theme.Typography.caption)
                    }
                    .foregroundColor(.red)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(Theme.CornerRadius.md)
                    .padding(.horizontal, Theme.Spacing.lg)
                }

                // Export Button
                Button(action: { exportWorkout() }) {
                    HStack(spacing: 8) {
                        if isExporting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                        }
                        Text(isExporting ? "Exporting..." : "Export & Share")
                            .font(Theme.Typography.bodyBold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: [Theme.Colors.accentBlue, Theme.Colors.accentGreen],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(Theme.CornerRadius.md)
                }
                .disabled(isExporting)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .padding(.top, Theme.Spacing.lg)
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Export Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let fileURL = exportedFileURL {
                    ShareSheet(activityItems: [fileURL])
                }
            }
        }
    }

    private func exportWorkout() {
        isExporting = true
        errorMessage = nil

        Task {
            do {
                let data: Data
                let filename: String

                switch selectedFormat {
                case .fit:
                    data = try await APIService.shared.exportWorkoutFIT(workoutId: workoutId)
                    filename = "\(sanitizedName).fit"
                case .csv:
                    data = try await APIService.shared.exportWorkoutCSV(workoutId: workoutId)
                    filename = "\(sanitizedName).csv"
                }

                // Write to temp file for sharing
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent(filename)
                try data.write(to: fileURL)

                await MainActor.run {
                    exportedFileURL = fileURL
                    isExporting = false
                    showingShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    errorMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private var sanitizedName: String {
        workoutName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()
    }
}

// MARK: - UIKit Share Sheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ExportView(workoutId: "test-123", workoutName: "Full Body Strength")
        .preferredColorScheme(.dark)
}
