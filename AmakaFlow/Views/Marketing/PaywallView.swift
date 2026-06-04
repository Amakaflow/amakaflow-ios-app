//
//  PaywallView.swift
//  AmakaFlow
//
//  Hi-fi paywall shell (`screens-marketing.jsx` → PaywallMobile). StoreKit /
//  Clerk billing integration is deferred — this is the design-aligned surface.
//

import SwiftUI

struct PaywallView: View {
    enum Plan: String, CaseIterable, Identifiable {
        case annual
        case monthly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .annual: return "Annual"
            case .monthly: return "Monthly"
            }
        }

        var price: String {
            switch self {
            case .annual: return "$89.99"
            case .monthly: return "$12.99"
            }
        }

        var subtitle: String {
            switch self {
            case .annual: return "$89.99/yr · $7.50/mo"
            case .monthly: return "$12.99/mo · 7-day trial"
            }
        }

        var badge: String? {
            switch self {
            case .annual: return "SAVE 42%"
            case .monthly: return nil
            }
        }
    }

    private struct Feature: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: Plan = .annual

    var allowsDismiss = true
    var onStartTrial: (() -> Void)?
    var onRestore: (() -> Void)?

    private let features: [Feature] = [
        Feature(title: "Daily adaptive plan", subtitle: "Re-optimizes every 6am from biometrics"),
        Feature(title: "Garmin + Apple Watch sync", subtitle: "Live HR, pace, zones during workouts"),
        Feature(title: "Injury-aware swaps", subtitle: "Coach adjusts when you flag soreness"),
        Feature(title: "Block periodization", subtitle: "Multi-month plans for races and events"),
        Feature(title: "Readiness insights", subtitle: "HRV, sleep, load trends explained")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    featureList
                    planPicker
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
            }
            footer
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .accessibilityIdentifier("paywall_screen")
    }

    private var header: some View {
        HStack {
            if allowsDismiss {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("paywall_close")
            } else {
                Color.clear.frame(width: 28, height: 28)
            }

            Spacer()

            Button("Restore") {
                onRestore?()
            }
            .font(Theme.Typography.label)
            .foregroundColor(Theme.Colors.textSecondary)
            .accessibilityIdentifier("paywall_restore")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            AFLabel(text: "AMAKAFLOW PRO")
            Text("Adaptive coaching,\nbuilt for hybrid days.")
                .font(Theme.Typography.largeTitle)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineSpacing(2)
            Text("Your plan reshapes every morning based on HRV, sleep, and yesterday's load — so you train when you're ready and recover when you're not.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(3)
                .padding(.top, Theme.Spacing.xs)
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            ForEach(features) { feature in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.Colors.readyHigh)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(feature.subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.Colors.borderLight)
                        .frame(height: 1)
                }
            }
        }
        .padding(.top, Theme.Spacing.lg)
    }

    private var planPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            AFLabel(text: "CHOOSE PLAN")
                .padding(.top, Theme.Spacing.md)

            ForEach(Plan.allCases) { plan in
                planOption(plan)
            }
        }
    }

    private func planOption(_ plan: Plan) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Theme.Colors.textPrimary : Theme.Colors.borderMedium, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle()
                            .fill(Theme.Colors.textPrimary)
                            .frame(width: 8, height: 8)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(plan.title)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)
                        if let badge = plan.badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Theme.Colors.background)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.Colors.textPrimary)
                                .clipShape(Capsule())
                        }
                    }
                    Text(plan.subtitle)
                        .font(Theme.Typography.mono)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                Text(plan.price)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            .padding(Theme.Spacing.md)
            .background(isSelected ? Theme.Colors.accentBackground : Theme.Colors.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                    .stroke(isSelected ? Theme.Colors.textPrimary : Theme.Colors.borderLight, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paywall_plan_\(plan.rawValue)")
    }

    private var footer: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                onStartTrial?()
                if allowsDismiss {
                    dismiss()
                }
            } label: {
                Text("Start 7-day free trial")
            }
            .buttonStyle(AFPrimaryButtonStyle(size: .lg))
            .accessibilityIdentifier("paywall_start_trial")

            Text("CANCEL ANYTIME · NO CHARGE TODAY")
                .font(Theme.Typography.label)
                .foregroundColor(Theme.Colors.textTertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.surfaceElevated)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Colors.borderLight).frame(height: 1)
        }
    }
}

#Preview {
    PaywallView()
}
