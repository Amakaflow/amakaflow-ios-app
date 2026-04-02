//
//  StageIndicator.swift
//  AmakaFlow
//
//  Horizontal stage progress indicator for coach chat (AMA-1410)
//

import SwiftUI

struct StageIndicator: View {
    let completedStages: [ChatStage]
    let currentStage: ChatStage?

    private var visibleStages: [ChatStage] {
        ChatStage.allCases.filter { $0 != .complete }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(visibleStages, id: \.self) { stage in
                HStack(spacing: Theme.Spacing.xs) {
                    if completedStages.contains(stage) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.Colors.accentGreen)
                    } else if currentStage == stage {
                        ProgressView()
                            .scaleEffect(0.5)
                            .tint(Theme.Colors.accentBlue)
                    } else {
                        Image(systemName: stage.iconName)
                            .font(.system(size: 9))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }

                    Text(stage.displayName)
                        .font(.system(size: 10, weight: currentStage == stage ? .semibold : .regular))
                        .foregroundColor(
                            currentStage == stage ? Theme.Colors.accentBlue :
                            completedStages.contains(stage) ? Theme.Colors.textSecondary :
                            Theme.Colors.textTertiary
                        )
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xs)
    }
}
