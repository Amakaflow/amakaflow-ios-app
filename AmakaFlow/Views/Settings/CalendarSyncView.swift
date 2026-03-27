//
//  CalendarSyncView.swift
//  AmakaFlow
//
//  External calendar sync management view (AMA-1238).
//  Connect Google Calendar or Outlook, view sync status, trigger manual sync, disconnect.
//

import SwiftUI

struct CalendarSyncView: View {
    @StateObject private var viewModel = CalendarSyncViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Header
                headerSection

                // Error banner
                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }

                // Success banner
                if let message = viewModel.lastSyncMessage {
                    successBanner(message)
                }

                // Connected calendars
                if viewModel.calendars.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    connectedCalendarsSection
                }

                // Connect new calendar button
                connectButton
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Calendar Sync")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.fetchCalendars()
        }
        .confirmationDialog("Choose Calendar Provider", isPresented: $viewModel.showProviderPicker) {
            ForEach(CalendarProvider.allCases) { provider in
                Button(provider.displayName) {
                    Task {
                        await viewModel.connectProvider(provider)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Disconnect Calendar", isPresented: $viewModel.showDisconnectAlert) {
            Button("Cancel", role: .cancel) {
                viewModel.calendarToDisconnect = nil
            }
            Button("Disconnect", role: .destructive) {
                if let calendar = viewModel.calendarToDisconnect {
                    Task {
                        await viewModel.disconnectCalendar(calendar)
                    }
                }
            }
        } message: {
            if let calendar = viewModel.calendarToDisconnect {
                Text("Are you sure you want to disconnect \(calendar.name)? Your synced events will remain but no new updates will be pulled.")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Sync your external calendars to see events alongside your training schedule.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.textSecondary)

            Text("No Calendars Connected")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Connect Google Calendar or Outlook to sync your events with AmakaFlow.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Theme.Spacing.xl)
    }

    // MARK: - Connected Calendars

    private var connectedCalendarsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("CONNECTED CALENDARS")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)
                .padding(.horizontal, Theme.Spacing.xs)

            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(Theme.Colors.textSecondary)
                    Spacer()
                }
                .padding(.vertical, Theme.Spacing.lg)
            } else {
                ForEach(viewModel.calendars) { calendar in
                    calendarCard(calendar)
                }
            }
        }
    }

    // MARK: - Calendar Card

    private func calendarCard(_ calendar: ConnectedCalendar) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            // Calendar info
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(providerColor(calendar.provider).opacity(0.1))
                        .frame(width: 48, height: 48)

                    Image(systemName: providerIcon(calendar.provider))
                        .font(.system(size: 22))
                        .foregroundColor(providerColor(calendar.provider))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(calendar.name)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)

                        HStack(spacing: 4) {
                            Image(systemName: calendar.status == "active" ? "checkmark" : "exclamationmark.triangle")
                                .font(.system(size: 10, weight: .bold))
                            Text(calendar.status == "active" ? "Connected" : calendar.status.capitalized)
                                .font(Theme.Typography.footnote)
                        }
                        .foregroundColor(calendar.status == "active" ? Theme.Colors.accentGreen : Theme.Colors.accentOrange)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 2)
                        .background((calendar.status == "active" ? Theme.Colors.accentGreen : Theme.Colors.accentOrange).opacity(0.1))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    if let email = calendar.email {
                        Text(email)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Text("Last sync: \(viewModel.formatLastSync(calendar.lastSyncAt))")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()
            }

            // Action buttons
            HStack(spacing: Theme.Spacing.sm) {
                // Sync button
                Button {
                    Task {
                        await viewModel.syncCalendar(calendar)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isSyncing.contains(calendar.id) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(Theme.Colors.textPrimary)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 14))
                        }
                        Text("Sync Now")
                            .font(Theme.Typography.caption)
                    }
                    .foregroundColor(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .stroke(Theme.Colors.borderLight, lineWidth: 1)
                    )
                    .cornerRadius(Theme.CornerRadius.md)
                }
                .disabled(viewModel.isSyncing.contains(calendar.id))

                // Disconnect button
                Button {
                    viewModel.calendarToDisconnect = calendar
                    viewModel.showDisconnectAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 14))
                        Text("Disconnect")
                            .font(Theme.Typography.caption)
                    }
                    .foregroundColor(Theme.Colors.accentRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.accentRed.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .stroke(Theme.Colors.accentRed.opacity(0.2), lineWidth: 1)
                    )
                    .cornerRadius(Theme.CornerRadius.md)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }

    // MARK: - Connect Button

    private var connectButton: some View {
        Button {
            viewModel.showProviderPicker = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if viewModel.isConnecting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                }
                Text("Connect Calendar")
                    .font(Theme.Typography.bodyBold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.accentBlue)
            .cornerRadius(Theme.CornerRadius.md)
        }
        .disabled(viewModel.isConnecting)
    }

    // MARK: - Banners

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.Colors.accentRed)
            Text(message)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.accentRed.opacity(0.1))
        .cornerRadius(Theme.CornerRadius.md)
    }

    private func successBanner(_ message: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.Colors.accentGreen)
            Text(message)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer()
            Button {
                viewModel.lastSyncMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.accentGreen.opacity(0.1))
        .cornerRadius(Theme.CornerRadius.md)
    }

    // MARK: - Helpers

    private func providerColor(_ provider: String) -> Color {
        switch provider.lowercased() {
        case "google": return Color(red: 0.26, green: 0.52, blue: 0.96)
        case "outlook", "microsoft": return Color(red: 0.0, green: 0.47, blue: 0.84)
        default: return Theme.Colors.accentBlue
        }
    }

    private func providerIcon(_ provider: String) -> String {
        switch provider.lowercased() {
        case "google": return "calendar"
        case "outlook", "microsoft": return "envelope.fill"
        default: return "calendar.badge.clock"
        }
    }
}
