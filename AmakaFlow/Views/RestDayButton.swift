//
//  RestDayButton.swift
//  AmakaFlow
//
//  "Log Rest Day" button with green checkmark and positive messaging (AMA-1286)
//

import SwiftUI

struct RestDayButton: View {
    let onRestDayLogged: () -> Void

    @State private var isLogged = false
    @State private var showCelebration = false
    @State private var checkmarkScale: CGFloat = 0

    private let restGreen = Color(hex: "00B894")

    var body: some View {
        Button {
            guard !isLogged else { return }
            logRestDay()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                // Checkmark icon
                ZStack {
                    Circle()
                        .fill(isLogged ? restGreen : restGreen.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: isLogged ? "checkmark.circle.fill" : "moon.zzz.fill")
                        .font(.system(size: isLogged ? 24 : 20))
                        .foregroundColor(isLogged ? .white : restGreen)
                        .scaleEffect(isLogged ? checkmarkScale : 1.0)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isLogged ? "Rest Day Logged" : "Log Rest Day")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(isLogged
                         ? "Muscles grow during rest. You\u{2019}re doing this right."
                         : "Take an intentional rest day (+10 XP)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(isLogged ? restGreen : Theme.Colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if !isLogged {
                    Text("+10 XP")
                        .font(Theme.Typography.captionBold)
                        .foregroundColor(restGreen)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(restGreen.opacity(0.15))
                        .cornerRadius(Theme.CornerRadius.sm)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                    .stroke(isLogged ? restGreen.opacity(0.5) : Theme.Colors.borderLight, lineWidth: 1)
            )
            .cornerRadius(Theme.CornerRadius.lg)
        }
        .buttonStyle(.plain)
        .disabled(isLogged)
        .accessibilityIdentifier("rest_day_button")
    }

    private func logRestDay() {
        // Trigger celebration animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            isLogged = true
            showCelebration = true
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.1)) {
            checkmarkScale = 1.0
        }

        // Notify parent to call API
        onRestDayLogged()
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        RestDayButton(onRestDayLogged: {})
    }
    .padding()
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}
