//
//  CoachingProfileOnboardingView.swift
//  AmakaFlow
//
//  Quick 3-field onboarding form for coaching profile (AMA-1265).
//  Shown if user has no coaching profile when requesting a workout suggestion.
//

import SwiftUI

struct CoachingProfileOnboardingView: View {
    @ObservedObject var viewModel: SuggestWorkoutViewModel

    @State private var experience: ExperienceLevel = .intermediate
    @State private var goal: TrainingGoal = .generalFitness
    @State private var daysPerWeek: Int = 3
    @State private var consentAccepted = UserDefaults.standard.bool(forKey: "biometric_consent_v1")

    var body: some View {
        if !consentAccepted {
            BiometricConsentView(
                onAccept: {
                    UserDefaults.standard.set(true, forKey: "biometric_consent_v1")
                    consentAccepted = true
                },
                onDecline: {
                    UserDefaults.standard.set(false, forKey: "biometric_consent_v1")
                }
            )
        } else {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    // Header
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "person.fill.questionmark")
                            .font(.system(size: 40))
                            .foregroundColor(Theme.Colors.accentOrange)

                        Text("Quick Setup")
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text("Tell us a little about yourself so we can suggest the right workout for you.")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Theme.Spacing.lg)

                    // Experience Level
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Experience Level")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Picker("Experience", selection: $experience) {
                            ForEach(ExperienceLevel.allCases, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(Theme.Spacing.lg)
                    .background(Theme.Colors.surface)
                    .cornerRadius(Theme.CornerRadius.lg)

                    // Training Goal
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Primary Goal")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)

                        ForEach(TrainingGoal.allCases, id: \.self) { goalOption in
                            Button {
                                goal = goalOption
                            } label: {
                                HStack {
                                    Text(goalOption.displayName)
                                        .font(Theme.Typography.body)
                                        .foregroundColor(Theme.Colors.textPrimary)
                                    Spacer()
                                    if goal == goalOption {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Theme.Colors.accentOrange)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(Theme.Colors.textSecondary)
                                    }
                                }
                                .padding(.vertical, Theme.Spacing.sm)
                            }

                            if goalOption != TrainingGoal.allCases.last {
                                Divider()
                            }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .background(Theme.Colors.surface)
                    .cornerRadius(Theme.CornerRadius.lg)

                    // Days Per Week
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Days Per Week")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)

                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(1...7, id: \.self) { day in
                                Button {
                                    daysPerWeek = day
                                } label: {
                                    Text("\(day)")
                                        .font(Theme.Typography.bodyBold)
                                        .foregroundColor(daysPerWeek == day ? .white : Theme.Colors.textPrimary)
                                        .frame(width: 40, height: 40)
                                        .background(daysPerWeek == day ? Theme.Colors.accentOrange : Theme.Colors.surfaceElevated)
                                        .cornerRadius(Theme.CornerRadius.md)
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .background(Theme.Colors.surface)
                    .cornerRadius(Theme.CornerRadius.lg)

                    // Submit button
                    Button {
                        viewModel.completeOnboarding(
                            experience: experience,
                            goal: goal,
                            daysPerWeek: daysPerWeek
                        )
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Generate My Workout")
                        }
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Colors.accentOrange)
                        .cornerRadius(Theme.CornerRadius.lg)
                    }
                    .accessibilityIdentifier("generate_workout_button")
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, 40)
            }
            .accessibilityIdentifier("coaching_onboarding")
        }
    }
}

#Preview {
    CoachingProfileOnboardingView(viewModel: SuggestWorkoutViewModel())
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
}
