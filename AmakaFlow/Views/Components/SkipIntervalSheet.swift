//
//  SkipIntervalSheet.swift
//  AmakaFlow
//
//  AMA-291: Skip interval sheet with reason picker for execution tracking
//

import SwiftUI

struct SkipIntervalSheet: View {
    @Binding var isPresented: Bool
    let onSkip: (SkipReason) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                // Header
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.Colors.accentBlue)

                    Text("Skip This Exercise?")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("Select a reason to help track your progress")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Theme.Spacing.lg)

                // Skip reason buttons
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(SkipReason.allCases, id: \.self) { reason in
                        skipReasonButton(reason)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)

                Spacer()
            }
            .background(Theme.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
    }

    private func skipReasonButton(_ reason: SkipReason) -> some View {
        Button {
            onSkip(reason)
            isPresented = false
        } label: {
            HStack {
                Image(systemName: iconFor(reason))
                    .font(.system(size: 20))
                    .foregroundColor(colorFor(reason))
                    .frame(width: 28)

                Text(reason.displayName)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.CornerRadius.md)
        }
    }

    private func iconFor(_ reason: SkipReason) -> String {
        switch reason {
        case .fatigue: return "battery.25"
        case .timeConstraint: return "clock"
        case .equipmentUnavailable: return "dumbbell"
        case .pain: return "bandage"
        case .other: return "ellipsis.circle"
        }
    }

    private func colorFor(_ reason: SkipReason) -> Color {
        switch reason {
        case .fatigue: return .orange
        case .timeConstraint: return Theme.Colors.accentBlue
        case .equipmentUnavailable: return .purple
        case .pain: return Theme.Colors.accentRed
        case .other: return Theme.Colors.textSecondary
        }
    }
}

// MARK: - Preview

#Preview {
    SkipIntervalSheet(isPresented: .constant(true)) { reason in
        print("Skipped with reason: \(reason.displayName)")
    }
}
