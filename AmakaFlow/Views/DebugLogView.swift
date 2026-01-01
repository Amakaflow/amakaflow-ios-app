//
//  DebugLogView.swift
//  AmakaFlow
//
//  Debug log viewer for API and device errors
//

import SwiftUI

struct DebugLogView: View {
    @StateObject private var logService = DebugLogService.shared
    @State private var showCopiedToast = false
    @State private var expandedEntryId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Action bar
            HStack(spacing: Theme.Spacing.md) {
                Button {
                    UIPasteboard.general.string = logService.getAllEntriesAsText()
                    showCopiedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCopiedToast = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy All")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.accentBlue)
                    .cornerRadius(Theme.CornerRadius.sm)
                }

                Button {
                    logService.clearLog()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.accentRed)
                    .cornerRadius(Theme.CornerRadius.sm)
                }

                Spacer()

                Text("\(logService.entries.count) entries")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)

            Divider()

            // Log entries
            if logService.entries.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(Theme.Colors.accentGreen)

                    Text("No errors logged")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)

                    Text("Errors from API calls, Watch connectivity,\nand workout completions will appear here.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(logService.entries) { entry in
                            logEntryRow(entry)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Debug Log")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if showCopiedToast {
                Text("Copied to clipboard")
                    .font(Theme.Typography.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(Theme.CornerRadius.md)
                    .padding(.top, Theme.Spacing.xl)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut, value: showCopiedToast)
            }
        }
    }

    // MARK: - Log Entry Row

    @ViewBuilder
    private func logEntryRow(_ entry: DebugLogEntry) -> some View {
        let isExpanded = expandedEntryId == entry.id

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Header
            HStack {
                // Type badge
                Text(entry.type.rawValue)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorForType(entry.type))
                    .cornerRadius(4)

                Text(entry.title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(isExpanded ? nil : 1)

                Spacer()

                Text(entry.formattedTimestamp)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            // Details (always show first line, expand for more)
            Text(entry.details)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(isExpanded ? nil : 2)

            // Metadata (only when expanded)
            if isExpanded, let metadata = entry.metadata, !metadata.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(alignment: .top, spacing: 4) {
                            Text("\(key):")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(Theme.Colors.accentBlue)
                            Text(value)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                }
                .padding(.top, Theme.Spacing.xs)
            }

            // Copy button when expanded
            if isExpanded {
                Button {
                    UIPasteboard.general.string = entry.copyableText
                    showCopiedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCopiedToast = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Entry")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(Theme.Colors.accentBlue)
                }
                .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                .stroke(isExpanded ? Theme.Colors.accentBlue.opacity(0.5) : Theme.Colors.borderLight, lineWidth: 1)
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedEntryId == entry.id {
                    expandedEntryId = nil
                } else {
                    expandedEntryId = entry.id
                }
            }
        }
    }

    // MARK: - Helpers

    private func colorForType(_ type: DebugLogType) -> Color {
        switch type {
        case .apiError:
            return Theme.Colors.accentRed
        case .apiSuccess:
            return Theme.Colors.accentGreen
        case .watchError:
            return Theme.Colors.accentOrange
        case .watchEvent:
            return Theme.Colors.accentBlue
        case .completionError:
            return Theme.Colors.accentRed
        case .networkError:
            return Theme.Colors.accentOrange
        case .authError:
            return Theme.Colors.accentRed
        case .general:
            return Theme.Colors.textSecondary
        }
    }
}

#Preview {
    NavigationStack {
        DebugLogView()
    }
}
