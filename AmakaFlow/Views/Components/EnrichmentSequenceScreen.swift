//
//  EnrichmentSequenceScreen.swift
//  AmakaFlow
//
//  AMA-2378 Task 3 — navigation stub. The shared mobility/cooldown sequence
//  builder (target segment, steppers, chip registry, ordered steps) lands in
//  Task 4; this placeholder proves the enhance sheet's Binding round-trip so
//  Task 4 only has to fill in the editor body.
//

import SwiftUI

struct EnrichmentSequenceScreen: View {
    @Binding var activities: [EnrichmentActivityPref]
    let kind: EnrichmentSequenceKind

    @Environment(\.dismiss) private var dismiss

    private var title: String {
        WorkoutEnrichmentPushCopy.offerTitle(
            for: kind == .mobility ? .sessionWarmup : .cooldown,
            target: .garmin
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .ddDisplayText(20, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Text(WorkoutEnrichmentPushCopy.sequenceHeaderMeta(
                    activities.map(EnrichmentActivity.init(pref:)),
                    kind: kind
                ))
                .font(Theme.Typography.mono)
                .foregroundColor(DailyDriver.foregroundMuted)
            }

            Text("Full step editor lands in Task 4 — Save keeps whatever the enhance sheet already has for this sequence.")
                .font(Theme.Typography.caption)
                .foregroundColor(DailyDriver.foregroundMuted)

            if activities.isEmpty {
                Text("NO STEPS ADDED")
                    .font(Theme.Typography.mono)
                    .foregroundColor(DailyDriver.foregroundDim)
                    .accessibilityIdentifier("af_seq_screen_empty")
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(activities) { activity in
                        Text(WorkoutEnrichmentPushCopy.activitySummaryLabel(
                            name: activity.name,
                            goal: activity.goal,
                            durationSec: activity.durationSec
                        ))
                        .font(Theme.Typography.mono)
                        .foregroundColor(DailyDriver.foreground)
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Text("Save")
            }
            .buttonStyle(AFPrimaryButtonStyle(size: .lg))
            .accessibilityIdentifier("af_seq_screen_save")
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("af_seq_screen_\(kind.rawValue)")
    }
}

#if DEBUG
#Preview("Mobility") {
    NavigationStack {
        EnrichmentSequenceScreen(
            activities: .constant([EnrichmentActivityPref(name: "Jump Rope")]),
            kind: .mobility
        )
    }
}

#Preview("Cooldown — empty") {
    NavigationStack {
        EnrichmentSequenceScreen(
            activities: .constant([]),
            kind: .cooldown
        )
    }
}
#endif
