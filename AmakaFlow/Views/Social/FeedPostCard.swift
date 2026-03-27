//
//  FeedPostCard.swift
//  AmakaFlow
//
//  Workout card for the community feed (AMA-1273)
//

import SwiftUI

struct FeedPostCard: View {
    let post: FeedPost
    let onReact: (String) -> Void
    let onComment: () -> Void
    let onTapUser: (String) -> Void

    @State private var showingOverflowMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Header: avatar + name + time + overflow
            header

            // Workout title
            Text(post.workoutName)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)

            // Exercises list (condensed)
            if !post.exercises.isEmpty {
                exercisesList
            }

            // Stats row: volume + duration
            statsRow

            // PR badges
            if !post.personalRecords.isEmpty {
                prBadges
            }

            // Optional photo
            if let photoUrl = post.photoUrl, !photoUrl.isEmpty {
                AsyncImage(url: URL(string: photoUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxHeight: 200)
                        .clipped()
                        .cornerRadius(Theme.CornerRadius.md)
                } placeholder: {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(Theme.Colors.surfaceElevated)
                        .frame(height: 200)
                        .overlay(ProgressView())
                }
            }

            // Reaction bar + comment count
            HStack {
                ReactionBar(
                    reactions: post.reactions,
                    userReactions: post.userReactions,
                    onReact: onReact
                )

                Spacer()

                Button(action: onComment) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 14))
                        if post.commentCount > 0 {
                            Text("\(post.commentCount)")
                                .font(Theme.Typography.caption)
                        }
                    }
                    .foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.lg)
        .accessibilityIdentifier("feed_post_\(post.id)")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Avatar
            Button {
                onTapUser(post.userId)
            } label: {
                userAvatar
            }

            VStack(alignment: .leading, spacing: 2) {
                Button {
                    onTapUser(post.userId)
                } label: {
                    Text(post.userName)
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                Text(post.postedAt.timeAgoDisplay())
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer()

            Menu {
                Button(role: .destructive) {
                    // Block action — placeholder
                } label: {
                    Label("Block User", systemImage: "hand.raised")
                }
                Button(role: .destructive) {
                    // Report action — placeholder
                } label: {
                    Label("Report Post", systemImage: "flag")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(Theme.Colors.textTertiary)
                    .frame(width: 32, height: 32)
            }
        }
    }

    private var userAvatar: some View {
        Group {
            if let avatarUrl = post.userAvatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Theme.Colors.surfaceElevated)
            .overlay(
                Text(String(post.userName.prefix(1)).uppercased())
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textSecondary)
            )
    }

    // MARK: - Exercises

    private var exercisesList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(post.exercises.prefix(4), id: \.name) { exercise in
                HStack(spacing: 4) {
                    Text(exercise.name)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)

                    if let sets = exercise.sets, let reps = exercise.reps {
                        Text("\(sets)x\(reps)")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }

                    if let weight = exercise.weight, weight > 0 {
                        Text("@ \(Int(weight))kg")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
            }
            if post.exercises.count > 4 {
                Text("+\(post.exercises.count - 4) more")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let volume = post.totalVolume, volume > 0 {
                Label {
                    Text(formatVolume(volume))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                } icon: {
                    Image(systemName: "scalemass")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.accentBlue)
                }
            }

            Label {
                Text(formatDuration(post.durationSeconds))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            } icon: {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.accentBlue)
            }
        }
    }

    // MARK: - PR Badges

    private var prBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(post.personalRecords, id: \.exerciseName) { pr in
                    HStack(spacing: 4) {
                        Text("🏆")
                            .font(.system(size: 12))
                        Text("\(pr.exerciseName) \(pr.metric): \(pr.value)")
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Color(hex: "D4A017"))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "D4A017").opacity(0.15))
                    .cornerRadius(Theme.CornerRadius.sm)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk kg", volume / 1000)
        }
        return "\(Int(volume)) kg"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Date Extension

extension Date {
    func timeAgoDisplay() -> String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: self)
        }
    }
}
