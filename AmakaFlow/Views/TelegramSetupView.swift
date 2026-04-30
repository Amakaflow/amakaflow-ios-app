//
//  TelegramSetupView.swift
//  AmakaFlow
//
//  Zero-friction Telegram account linking via t.me?start= deep link (AMA-1617).
//

import SwiftUI

private let telegramBlue = Color(hex: "29B6F6")

struct TelegramSetupView: View {
    let onConnected: () -> Void
    let onSkip: () -> Void

    @State private var phase: Phase = .idle
    @State private var linkTask: Task<Void, Never>?
    @State private var pollTask: Task<Void, Never>?

    private enum Phase {
        case idle
        case loading
        case polling
        case connected
        case error(String)
    }

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

                Text("Your morning briefings, evening check-ins, and workout swaps all happen in Telegram. Two taps to connect your account.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            switch phase {
            case .idle, .error:
                VStack(spacing: Theme.Spacing.sm) {
                    Button(action: openTelegram) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right")
                            Text("Open Telegram →")
                        }
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(telegramBlue)
                        .cornerRadius(Theme.CornerRadius.md)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)

                    if case .error(let msg) = phase {
                        Text(msg)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.accentRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.lg)
                    }

                    Button("Skip for now", action: onSkip)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }

            case .loading:
                VStack(spacing: Theme.Spacing.sm) {
                    ProgressView()
                    Text("Generating link…")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

            case .polling:
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                    Text("Waiting for Telegram confirmation…")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Button("Cancel", action: cancelAll)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }

            case .connected:
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.Colors.accentGreen)
                    Text("Telegram connected!")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.accentGreen)
                }
            }

            Spacer()
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .onDisappear {
            linkTask?.cancel()
            pollTask?.cancel()
        }
    }

    private func openTelegram() {
        phase = .loading
        linkTask?.cancel()
        linkTask = Task {
            do {
                let baseURL = AppEnvironment.current.mapperAPIURL
                guard let url = URL(string: "\(baseURL)/api/telegram/link-token") else {
                    await MainActor.run { phase = .error("Invalid server URL.") }
                    return
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.allHTTPHeaderFields = await APIService.shared.makeAuthHeaders()

                guard !Task.isCancelled else { return }
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }

                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    await MainActor.run { phase = .error("Failed to generate link. Try again.") }
                    return
                }

                let json = try JSONDecoder().decode(LinkTokenResponse.self, from: data)

                var components = URLComponents(string: json.nativeLink)
                    ?? URLComponents(string: json.deepLink)
                guard let deepLink = components?.url ?? URL(string: json.deepLink) else {
                    await MainActor.run { phase = .error("Invalid deep link from server.") }
                    return
                }

                await MainActor.run {
                    phase = .polling
                    UIApplication.shared.open(deepLink) { opened in
                        if !opened {
                            // tg:// unavailable — try https://t.me fallback
                            if let fallback = URL(string: json.deepLink) {
                                UIApplication.shared.open(fallback) { fallbackOpened in
                                    if !fallbackOpened {
                                        phase = .error("Could not open Telegram. Please install it and try again.")
                                    }
                                }
                            } else {
                                phase = .error("Could not open Telegram. Please install it and try again.")
                            }
                        }
                    }
                    startPolling(token: json.token)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { phase = .error("Network error. Please try again.") }
            }
        }
    }

    private func startPolling(token: String) {
        pollTask?.cancel()
        pollTask = Task {
            let deadline = Date().addingTimeInterval(300)
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                do {
                    let baseURL = AppEnvironment.current.mapperAPIURL
                    var components = URLComponents(string: "\(baseURL)/api/telegram/link-status")
                    components?.queryItems = [URLQueryItem(name: "token", value: token)]
                    guard let url = components?.url else { continue }
                    var request = URLRequest(url: url)
                    request.allHTTPHeaderFields = await APIService.shared.makeAuthHeaders()
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                    let status = try JSONDecoder().decode(LinkStatusResponse.self, from: data)
                    if status.linked {
                        await MainActor.run {
                            phase = .connected
                            pollTask = nil
                        }
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        await MainActor.run { onConnected() }
                        return
                    }
                } catch { }
            }
            await MainActor.run {
                if case .polling = phase {
                    phase = .error("Timed out. Tap Open Telegram to try again.")
                }
            }
        }
    }

    private func cancelAll() {
        linkTask?.cancel()
        linkTask = nil
        pollTask?.cancel()
        pollTask = nil
        phase = .idle
    }
}

private struct LinkTokenResponse: Decodable {
    let token: String
    let deepLink: String
    let nativeLink: String

    enum CodingKeys: String, CodingKey {
        case token
        case deepLink = "deep_link"
        case nativeLink = "native_link"
    }
}

private struct LinkStatusResponse: Decodable {
    let linked: Bool
}

#Preview {
    TelegramSetupView(onConnected: {}, onSkip: {})
        .preferredColorScheme(.dark)
}
