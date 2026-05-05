//
//  TelegramSetupView.swift
//  AmakaFlow
//
//  Zero-friction Telegram account linking via backend-minted deep link (AMA-1763).
//

import Combine
import SwiftUI

private let telegramBlue = Color(hex: "29B6F6")

@MainActor
protocol URLOpener: Sendable {
    func open(_ url: URL) async -> Bool
}

struct SystemURLOpener: URLOpener {
    @MainActor
    func open(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url) { opened in
                continuation.resume(returning: opened)
            }
        }
    }
}

@MainActor
final class ConnectTelegramViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case minting
        case connecting
        case connected(telegramId: Int?)
        case failed(String)
    }

    @Published private(set) var state: State

    private let apiService: APIServiceProviding
    private let urlOpener: URLOpener
    private let pollIntervalNanoseconds: UInt64
    private let timeoutSeconds: TimeInterval
    private let now: @Sendable () -> Date
    private let onConnected: (Int?) -> Void
    private var pollingTask: Task<Void, Never>?

    init(
        apiService: APIServiceProviding = APIService.shared,
        urlOpener: URLOpener? = nil,
        initialTelegramId: Int? = nil,
        pollIntervalNanoseconds: UInt64 = 3_000_000_000,
        timeoutSeconds: TimeInterval = 90,
        now: @escaping @Sendable () -> Date = Date.init,
        onConnected: @escaping (Int?) -> Void = { _ in }
    ) {
        self.apiService = apiService
        self.urlOpener = urlOpener ?? SystemURLOpener()
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.timeoutSeconds = timeoutSeconds
        self.now = now
        self.onConnected = onConnected
        if let initialTelegramId {
            self.state = .connected(telegramId: initialTelegramId)
        } else {
            self.state = .idle
        }
    }

    deinit {
        pollingTask?.cancel()
    }

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    var isBusy: Bool {
        switch state {
        case .minting, .connecting: return true
        default: return false
        }
    }

    func connectTapped() {
        guard !isBusy else { return }
        if isConnected {
            state = .failed("Telegram is already connected. Disconnect in Telegram if you want to switch accounts.")
            return
        }

        pollingTask?.cancel()
        state = .minting

        pollingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let token = try await apiService.mintTelegramLinkToken()
                guard !Task.isCancelled else { return }

                await MainActor.run { self.state = .connecting }
                await self.openTelegram(nativeLink: token.nativeLink, deepLink: token.deepLink)
                await self.pollStatus(token: token.token, expiresInSeconds: token.expiresInSeconds)
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.state = .failed(Self.message(for: error))
                }
            }
        }
    }

    func cancel() {
        pollingTask?.cancel()
        pollingTask = nil
        state = .idle
    }

    private func openTelegram(nativeLink: String, deepLink: String) async {
        if let nativeURL = URL(string: nativeLink), await urlOpener.open(nativeURL) {
            return
        }
        if let fallbackURL = URL(string: deepLink), await urlOpener.open(fallbackURL) {
            return
        }
        state = .failed("Could not open Telegram. Install Telegram or try again from a browser.")
    }

    private func pollStatus(token: String, expiresInSeconds: Int) async {
        let startedAt = now()
        let timeoutAt = startedAt.addingTimeInterval(timeoutSeconds)
        let expiresAt = startedAt.addingTimeInterval(TimeInterval(expiresInSeconds))

        while now() < timeoutAt {
            guard !Task.isCancelled else { return }
            if now() >= expiresAt {
                state = .failed("Link expired, try again.")
                return
            }

            do {
                let status = try await apiService.getTelegramLinkStatus(token: token)
                guard !Task.isCancelled else { return }
                if status.linked {
                    state = .connected(telegramId: status.telegramId)
                    onConnected(status.telegramId)
                    pollingTask = nil
                    return
                }
            } catch {
                guard !Task.isCancelled else { return }
            }

            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        guard !Task.isCancelled else { return }
        state = .failed("Timed out waiting for Telegram. Try again.")
        pollingTask = nil
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .serverErrorWithBody(503, _):
                return "Telegram linking is temporarily unavailable. Please try again in a few minutes."
            case .unauthorized:
                return "Your session expired. Sign in again and retry."
            default:
                return apiError.localizedDescription
            }
        }
        return "Could not start Telegram linking. Please try again."
    }
}

struct TelegramSetupView: View {
    @StateObject private var viewModel: ConnectTelegramViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        initialTelegramId: Int? = nil,
        onConnected: @escaping (Int?) -> Void = { _ in },
        onSkip: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(
            wrappedValue: ConnectTelegramViewModel(
                initialTelegramId: initialTelegramId,
                onConnected: onConnected
            )
        )
        self.onSkip = onSkip
    }

    private let onSkip: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                    .fill(telegramBlue.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(telegramBlue)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text("Connect Telegram")
                    .font(Theme.Typography.title1)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("Open Telegram, tap Start, and AmakaFlow will confirm the connection automatically.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            statusContent

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Telegram")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    viewModel.cancel()
                    dismiss()
                }
            }
        }
        .onDisappear { viewModel.cancel() }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch viewModel.state {
        case .idle:
            connectButton
            Button("Skip for now", action: onSkip)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
        case .minting:
            ProgressView("Generating link…")
                .foregroundColor(Theme.Colors.textSecondary)
        case .connecting:
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                Text("Waiting for Telegram confirmation…")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                Button("Cancel", action: viewModel.cancel)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        case .connected(let telegramId):
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(Theme.Colors.accentGreen)
                Text(telegramId.map { "Connected to \($0)" } ?? "Telegram connected")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.accentGreen)
            }
        case .failed(let message):
            VStack(spacing: Theme.Spacing.md) {
                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accentRed)
                    .multilineTextAlignment(.center)
                connectButton
            }
        }
    }

    private var connectButton: some View {
        Button(action: viewModel.connectTapped) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right")
                Text("Open Telegram")
            }
            .font(Theme.Typography.bodyBold)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding()
            .background(telegramBlue)
            .cornerRadius(Theme.CornerRadius.md)
        }
        .accessibilityIdentifier("connect_telegram_button")
    }
}

#Preview {
    NavigationStack {
        TelegramSetupView()
            .preferredColorScheme(.dark)
    }
}
