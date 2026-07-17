//
//  CreateWorkoutSheet.swift
//  AmakaFlow
//
//  Daily Driver "Add workout" sheet — four doors into import / create flows.
//

import SwiftUI

enum CreateWorkoutDoor: Equatable {
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
                    icon: "mic.fill",
                    iconBackground: DailyDriver.blue,
                    title: "Speak or describe it",
                    subtitle: "Coach turns it into a draft"
                ) {
                    dismissThen { onSelect(.speak) }
                }
                .accessibilityIdentifier("create_door_speak")

                DDDoorRow(
                    icon: "square.and.pencil",
                    iconBackground: DailyDriver.card2,
                    title: "Build from scratch",
                    subtitle: "From scratch, exercise by exercise"
                ) {
                    dismissThen { onSelect(.manual) }
                }
                .accessibilityIdentifier("create_door_manual")
            }
        }
        .accessibilityIdentifier("create_workout_sheet")
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
