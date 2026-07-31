//
//  WorkoutTypeMatchChip.swift
//  AmakaFlow
//
//  Advisory canonical workout-type match shown under the editor title.
//

import SwiftUI

struct WorkoutTypeMatchChip: View {
    let displayName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text("Matched: \(displayName)")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(DailyDriver.foregroundMuted)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(DailyDriver.backgroundElevated)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(DailyDriver.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Matched workout type: \(displayName)")
        .accessibilityHint("Opens workout type choices")
        .accessibilityIdentifier("workout_type_match_chip")
    }
}

#if DEBUG
#Preview {
    WorkoutTypeMatchChip(displayName: "Tempo Run", action: {})
        .padding()
        .background(DailyDriver.screenBackground)
        .preferredColorScheme(.dark)
}
#endif
