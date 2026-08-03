//
//  CreateWorkoutSheet.swift
//  AmakaFlow
//
//  Daily Driver "Add workout" sheet — explicit doors into import / create flows.
//

import SwiftUI

enum CreateWorkoutDoor: Equatable {
    case createWithAI
    case importURL
    case screenshot
    case speak
    case manual
}

struct CreateWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (CreateWorkoutDoor) -> Void

    var body: some View {
        DDBottomSheetChrome(title: "Add workout") {
            VStack(spacing: 10) {
                DDDoorRow(
                    icon: "sparkles",
                    iconBackground: DailyDriver.lime,
                    iconForeground: DailyDriver.ink,
                    title: "Create with AI",
                    subtitle: "Describe it — the coach drafts it"
                ) {
                    dismissThen { onSelect(.createWithAI) }
                }
                .accessibilityIdentifier("create_door_ai")

                DDDoorRow(
                    icon: "link",
                    iconBackground: DailyDriver.lime,
                    iconForeground: DailyDriver.ink,
                    title: "Import from URL",
                    subtitle: "Instagram, TikTok, or YouTube"
                ) {
                    dismissThen { onSelect(.importURL) }
                }
                .accessibilityIdentifier("create_door_url")

                DDDoorRow(
                    icon: "camera.fill",
                    iconBackground: DailyDriver.purple,
                    title: "Screenshot",
                    subtitle: "Photo of a workout → draft"
                ) {
                    dismissThen { onSelect(.screenshot) }
                }
                .accessibilityIdentifier("create_door_screenshot")

                DDDoorRow(
                    icon: "square.and.pencil",
                    iconBackground: DailyDriver.card2,
                    title: "Build from scratch",
                    subtitle: "From scratch, exercise by exercise"
                ) {
                    dismissThen { onSelect(.manual) }
                }
                .accessibilityIdentifier("create_door_manual")

                speakComingSoonFooter
            }
        }
        .accessibilityIdentifier("create_workout_sheet")
    }

    private var speakComingSoonFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 14, weight: .semibold))
            Text("Speak it — coming soon")
                .font(Theme.Typography.caption)
        }
        .foregroundColor(DailyDriver.foregroundMuted)
        .opacity(0.5)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Speak it, coming soon")
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            action()
        }
    }
}

#if DEBUG
#Preview {
    CreateWorkoutSheet { _ in }
}
#endif
