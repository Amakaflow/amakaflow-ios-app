//
//  AppleWatchDeliveryPrefsSheet.swift
//  AmakaFlow
//
//  AMA-2360 — Settings / Start sheet editor for Apple work/rest delivery prefs.
//

import SwiftUI

struct AppleWatchDeliveryPrefsSheet: View {
    enum Mode {
        case settings
    }

    let mode: Mode
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var prefs: AppleWatchDeliveryPrefs
    private let initialPrefs: AppleWatchDeliveryPrefs

    init(
        mode: Mode = .settings,
        initial: AppleWatchDeliveryPrefs? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onSaved = onSaved
        let starting = initial ?? AppleWatchDeliveryPrefsStore.current
        initialPrefs = starting
        _prefs = State(initialValue: starting)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("How Apple Workout should run AmakaFlow sets and rest.")
                        .font(Theme.Typography.body)
                        .foregroundColor(DailyDriver.foregroundMuted)

                    section(title: "Work sets", subtitle: "How do you finish each set?") {
                        ForEach(AppleExerciseEnd.allCases) { option in
                            optionRow(title: option.title, isSelected: prefs.exerciseEnd == option) {
                                prefs.exerciseEnd = option
                                AppleWatchDeliveryPrefsStore.applyLiveSelection(exerciseEnd: option)
                            }
                        }
                    }

                    section(title: "Between-set rest", subtitle: "What should rest look like?") {
                        ForEach(AppleRestMode.allCases) { option in
                            optionRow(title: option.title, isSelected: prefs.restMode == option) {
                                prefs.restMode = option
                                AppleWatchDeliveryPrefsStore.applyLiveSelection(restMode: option)
                            }
                        }
                    }

                    Text("No “timed everything” for Apple — tap or timed holds only (ease-first).")
                        .font(Theme.Typography.caption)
                        .foregroundColor(DailyDriver.foregroundMuted)

                    Button {
                        AppleWatchDeliveryPrefsStore.current = prefs
                        onSaved?()
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(DailyDriver.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(DailyDriver.lime)
                            .cornerRadius(Theme.CornerRadius.md)
                    }
                    .accessibilityIdentifier("af_apple_delivery_prefs_save")

                    Button {
                        prefs = initialPrefs
                        AppleWatchDeliveryPrefsStore.current = initialPrefs
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(Theme.Typography.body)
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Theme.Spacing.lg)
            }
            .background(DailyDriver.screenBackground)
            .navigationTitle("Apple Watch delivery")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
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
            content()
        }
    }

    private func optionRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundColor(DailyDriver.foreground)
                    .multilineTextAlignment(.leading)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DailyDriver.lime)
                }
            }
            .padding(Theme.Spacing.md)
            .background(isSelected ? DailyDriver.lime.opacity(0.15) : DailyDriver.card)
            .cornerRadius(Theme.CornerRadius.md)
        }
        .buttonStyle(.plain)
    }
}
