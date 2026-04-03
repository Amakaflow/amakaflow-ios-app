//
//  ToolCallCard.swift
//  AmakaFlow
//
//  Inline tool call visualization for coach chat (AMA-1410)
//

import SwiftUI

struct ToolCallCard: View {
    let toolCall: ChatToolCall

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: toolCall.iconName)
                .font(.system(size: 12))
                .foregroundColor(Theme.Colors.accentBlue)

            Text(toolCall.displayName)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            Spacer()

            switch toolCall.status {
            case .pending, .running:
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(Theme.Colors.accentBlue)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.accentGreen)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.accentRed)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surfaceElevated)
        .cornerRadius(Theme.CornerRadius.md)
    }
}
