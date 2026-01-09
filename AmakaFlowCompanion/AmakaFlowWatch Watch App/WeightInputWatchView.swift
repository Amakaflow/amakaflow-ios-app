//
//  WeightInputWatchView.swift
//  AmakaFlowWatch Watch App
//
//  AMA-286: Weight input view for Apple Watch using Digital Crown
//

import SwiftUI

struct WeightInputWatchView: View {
    let exerciseName: String
    let setNumber: Int
    let totalSets: Int
    let suggestedWeight: Double?
    let weightUnit: String
    let onLogSet: (Double?, String) -> Void
    let onSkipWeight: () -> Void

    @State private var weight: Double
    @State private var crownValue: Double = 0

    // Weight increment based on unit
    private var increment: Double {
        weightUnit == "kg" ? 2.5 : 5.0
    }

    init(
        exerciseName: String,
        setNumber: Int,
        totalSets: Int,
        suggestedWeight: Double?,
        weightUnit: String,
        onLogSet: @escaping (Double?, String) -> Void,
        onSkipWeight: @escaping () -> Void
    ) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.totalSets = totalSets
        self.suggestedWeight = suggestedWeight
        self.weightUnit = weightUnit
        self.onLogSet = onLogSet
        self.onSkipWeight = onSkipWeight
        _weight = State(initialValue: suggestedWeight ?? 0)
        _crownValue = State(initialValue: suggestedWeight ?? 0)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Exercise name and set info
            VStack(spacing: 2) {
                Text(exerciseName.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text("Set \(setNumber)/\(totalSets)")
                    .font(.system(size: 14, weight: .bold))
            }

            // Weight display with Digital Crown control
            VStack(spacing: 4) {
                Text(formattedWeight)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(weight > 0 ? .primary : .secondary)

                Text(weightUnit)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                // Hint for Digital Crown
                HStack(spacing: 4) {
                    Image(systemName: "digitalcrown.horizontal.arrow.counterclockwise")
                        .font(.system(size: 10))
                    Text("Crown to adjust")
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary.opacity(0.7))
            }
            .focusable(true)
            .digitalCrownRotation(
                $crownValue,
                from: 0,
                through: 1000,
                by: increment,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .onChange(of: crownValue) { _, newValue in
                weight = max(0, newValue)
            }

            // Action buttons
            HStack(spacing: 12) {
                // Skip button
                Button {
                    onSkipWeight()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.3))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Log Set button (primary action)
                Button {
                    let logWeight = weight > 0 ? weight : nil
                    onLogSet(logWeight, weightUnit)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                        Text("LOG")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(width: 80, height: 44)
                    .background(Color.green)
                    .cornerRadius(22)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private var formattedWeight: String {
        if weight == 0 {
            return "0"
        }
        // Show decimal only if needed
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", weight)
        }
        return String(format: "%.1f", weight)
    }
}

// MARK: - Preview

#Preview("Weight Input") {
    WeightInputWatchView(
        exerciseName: "Bench Press",
        setNumber: 2,
        totalSets: 4,
        suggestedWeight: 135,
        weightUnit: "lbs",
        onLogSet: { weight, unit in
            print("Logged: \(weight ?? 0) \(unit)")
        },
        onSkipWeight: {
            print("Skipped")
        }
    )
}

#Preview("No Weight") {
    WeightInputWatchView(
        exerciseName: "Squats",
        setNumber: 1,
        totalSets: 3,
        suggestedWeight: nil,
        weightUnit: "lbs",
        onLogSet: { _, _ in },
        onSkipWeight: {}
    )
}
