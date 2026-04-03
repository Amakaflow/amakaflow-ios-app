//
//  UserProfileMiniView.swift
//  AmakaFlow
//
//  Public user profile with workouts, stats, and follow button (AMA-1273)
//

import SwiftUI

struct UserProfileMiniView: View {
    let userId: String
    @State private var profile: UserPublicProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isFollowLoading = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading profile...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let profile = profile {
                profileContent(profile)
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text(errorMessage ?? "Could not load profile")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadProfile()
        }
    }

    // MARK: - Profile Content

    private func profileContent(_ profile: UserPublicProfile) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Avatar + name
                VStack(spacing: Theme.Spacing.sm) {
                    profileAvatar(profile)

                    Text(profile.userName)
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)

                    // Follow button
                    Button {
                        Task { await toggleFollow() }
                    } label: {
                        Text(profile.isFollowing ? "Following" : "Follow")
                            .font(Theme.Typography.captionBold)
                            .foregroundColor(profile.isFollowing ? Theme.Colors.textPrimary : .white)
                            .frame(width: 120, height: 36)
                            .background(
                                profile.isFollowing
                                    ? Theme.Colors.surfaceElevated
                                    : Theme.Colors.accentBlue
                            )
                            .cornerRadius(Theme.CornerRadius.md)
                    }
                    .disabled(isFollowLoading)
                    .accessibilityIdentifier("follow_button")
                }
                .padding(.top, Theme.Spacing.lg)

                // Stats grid
                HStack(spacing: Theme.Spacing.lg) {
                    statItem(value: "\(profile.workoutCount)", label: "Workouts")
                    statItem(value: formatVolume(profile.totalVolume), label: "Volume")
                    statItem(value: "\(profile.streakDays)d", label: "Streak")
                }
                .padding(.horizontal, Theme.Spacing.md)

                Divider()
                    .background(Theme.Colors.borderLight)

                // Recent workouts
                if !profile.recentWorkouts.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Recent Workouts")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .padding(.horizontal, Theme.Spacing.md)

                        ForEach(profile.recentWorkouts) { post in
                            FeedPostCard(
                                post: post,
                                onReact: { _ in },
                                onComment: {},
                                onTapUser: { _ in }
                            )
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                    }
                }
            }
            .padding(.bottom, 100)
        }
    }

    private func profileAvatar(_ profile: UserPublicProfile) -> some View {
        Group {
            if let avatarUrl = profile.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    profileAvatarPlaceholder(name: profile.userName)
                }
            } else {
                profileAvatarPlaceholder(name: profile.userName)
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(Circle())
    }

    private func profileAvatarPlaceholder(name: String) -> some View {
        Circle()
            .fill(Theme.Colors.surfaceElevated)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Theme.Colors.textSecondary)
            )
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
            Text(label)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.0fk", volume / 1000)
        }
        return "\(Int(volume))"
    }

    // MARK: - Actions

    private func loadProfile() async {
        isLoading = true
        do {
            profile = try await APIService.shared.fetchUserPublicProfile(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
            print("[UserProfileMiniView] loadProfile failed: \(error)")
        }
        isLoading = false
    }

    private func toggleFollow() async {
        guard let currentProfile = profile else { return }
        isFollowLoading = true
        do {
            if currentProfile.isFollowing {
                try await APIService.shared.unfollowUser(userId: userId)
            } else {
                try await APIService.shared.followUser(userId: userId)
            }
            // Reload profile to get updated isFollowing state
            profile = try await APIService.shared.fetchUserPublicProfile(userId: userId)
        } catch {
            print("[UserProfileMiniView] toggleFollow failed: \(error)")
        }
        isFollowLoading = false
    }
}
