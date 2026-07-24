//
//  GarminWatchDisplayPrefsSheet.swift
//  AmakaFlow
//
//  AMA-2316: One-time (and Settings) sheet for Garmin work/rest display prefs.
//

import SwiftUI

struct GarminWatchDisplayPrefsSheet: View {
    enum Mode {
        /// First-time after Connect / pair — subtitle says "only see this once".
        case onboarding
        /// Settings → Garmin editor.
        case settings
    }

    let mode: Mode
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var prefs: GarminWatchDisplayPrefs

    init(
        mode: Mode,
        initial: GarminWatchDisplayPrefs? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onSaved = onSaved
        _prefs = State(initialValue: initial ?? GarminWatchDisplayPrefsStore.current)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header

                    section(
                        title: "Work sets",
                        subtitle: "How do you finish each set?"
                    ) {
                        ForEach(GarminExerciseEnd.allCases) { option in
                            optionRow(
                                title: option.title,
                                isSelected: prefs.exerciseEnd == option
                            ) {
                                prefs.exerciseEnd = option
                            }
                        }
                    }

                    section(
                        title: "Between-set rest",
                        subtitle: "What should rest look like?"
                    ) {
                        ForEach(GarminRestMode.allCases) { option in
                            optionRow(
                                title: option.title,
                                isSelected: prefs.restMode == option
                            ) {
                                prefs.restMode = option
                            }
                        }
                    }

                    Text("These choices match what Garmin’s native workout player can do.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(DailyDriver.foregroundMuted)

                    Button {
                        save()
                    } label: {
                        Text(mode == .onboarding ? "Continue" : "Save")
                    }
                    .buttonStyle(AFPrimaryButtonStyle(size: .lg))
                    .accessibilityIdentifier("af_garmin_display_prefs_save")
                }
                .padding(Theme.Spacing.lg)
            }
            .background(DailyDriver.screenBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .settings {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("af_garmin_display_prefs_sheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("How should workouts show on your watch?")
                .afH2()
                .accessibilityAddTraits(.isHeader)
            if mode == .onboarding {
                Text("You’ll only see this once. Change anytime in Settings → Garmin.")
                    .afMuted()
            } else {
                Text("Applied on every Garmin push. Change anytime here.")
                    .afMuted()
            }
        }
    }

    private func section<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.bodyBold)
                .foregroundColor(DailyDriver.foreground)
            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundColor(DailyDriver.foregroundMuted)
            VStack(spacing: Theme.Spacing.sm) {
                content()
            }
        }
    }

    private func optionRow(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? DailyDriver.lime : DailyDriver.foregroundMuted)
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundColor(DailyDriver.foreground)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                    .fill(DailyDriver.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                    .stroke(
                        isSelected ? DailyDriver.lime.opacity(0.7) : DailyDriver.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func save() {
        GarminWatchDisplayPrefsStore.current = prefs
        onSaved?()
        dismiss()
    }
}

#if DEBUG
#Preview("Onboarding") {
    GarminWatchDisplayPrefsSheet(mode: .onboarding)
}

#Preview("Settings") {
    GarminWatchDisplayPrefsSheet(mode: .settings)
}
#endif
