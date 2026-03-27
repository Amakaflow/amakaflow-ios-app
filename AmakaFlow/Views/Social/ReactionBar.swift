//
//  ReactionBar.swift
//  AmakaFlow
//
//  Emoji reaction bar with heart/fire/muscle toggle buttons (AMA-1273)
//

import SwiftUI

struct ReactionBar: View {
    let reactions: [FeedReaction]
    let userReactions: [String]
    let onReact: (String) -> Void

    private let emojiOptions = [
        ("heart", "❤️"),
        ("fire", "🔥"),
        ("muscle", "💪")
    ]

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(emojiOptions, id: \.0) { key, display in
                let count = reactions.first(where: { $0.emoji == key })?.count ?? 0
                let isActive = userReactions.contains(key)

                Button {
                    onReact(key)
                } label: {
                    HStack(spacing: 4) {
                        Text(display)
                            .font(.system(size: 16))
                        if count > 0 {
                            Text("\(count)")
                                .font(Theme.Typography.footnote)
                                .foregroundColor(isActive ? Theme.Colors.accentBlue : Theme.Colors.textTertiary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        isActive
                            ? Theme.Colors.accentBlue.opacity(0.15)
                            : Theme.Colors.surfaceElevated
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                            .stroke(
                                isActive ? Theme.Colors.accentBlue.opacity(0.4) : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .cornerRadius(Theme.CornerRadius.sm)
                }
                .accessibilityIdentifier("reaction_\(key)")
            }
        }
    }
}

#Preview {
    ReactionBar(
        reactions: [
            FeedReaction(emoji: "heart", count: 5),
            FeedReaction(emoji: "fire", count: 2)
        ],
        userReactions: ["heart"],
        onReact: { _ in }
    )
    .padding()
    .background(Theme.Colors.surface)
    .preferredColorScheme(.dark)
}
