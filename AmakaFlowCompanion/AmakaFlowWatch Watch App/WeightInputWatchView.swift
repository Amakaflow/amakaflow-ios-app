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
    /// When true and crown still matches prescribed load, primary CTA is "AS PLANNED" (AMA-2420 Phase 3).
    let allowCompleteAsPrescribed: Bool
    /// Prescribed load from plan (not last-logged). Used to decide AS PLANNED vs LOG.
    let prescribedWeight: Double?
    let onLogSet: (Double?, String) -> Void
    let onSkipWeight: () -> Void
    let onCompleteAsPrescribed: (() -> Void)?

    @State private var weight: Double
    @State private var crownValue: Double = 0

    // Weight increment based on unit
    private var increment: Double {
        weightUnit == "kg" ? 2.5 : 5.0
    }

    private var isAtPrescribedWeight: Bool {
        guard allowCompleteAsPrescribed, let prescribed = prescribedWeight else { return false }
        return abs(weight - prescribed) < 0.01
    }

    init(
        exerciseName: String,
        setNumber: Int,
        totalSets: Int,
        suggestedWeight: Double?,
        weightUnit: String,
        allowCompleteAsPrescribed: Bool = false,
        prescribedWeight: Double? = nil,
        onLogSet: @escaping (Double?, String) -> Void,
        onSkipWeight: @escaping () -> Void,
        onCompleteAsPrescribed: (() -> Void)? = nil
    ) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.totalSets = totalSets
        self.suggestedWeight = suggestedWeight
        self.weightUnit = weightUnit
        self.allowCompleteAsPrescribed = allowCompleteAsPrescribed
        self.prescribedWeight = prescribedWeight
        self.onLogSet = onLogSet
        self.onSkipWeight = onSkipWeight
        self.onCompleteAsPrescribed = onCompleteAsPrescribed
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

                // Primary: AS PLANNED when still at prescribed, else LOG
                Button {
                    if isAtPrescribedWeight, let onCompleteAsPrescribed {
                        onCompleteAsPrescribed()
                    } else {
                        let logWeight = weight > 0 ? weight : nil
                        onLogSet(logWeight, weightUnit)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                        Text(isAtPrescribedWeight ? "AS PLANNED" : "LOG")
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(.white)
                    .frame(minWidth: 88, minHeight: 44)
                    .padding(.horizontal, 8)
                    .background(Color.green)
                    .cornerRadius(22)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(
                    isAtPrescribedWeight ? "af_watch_as_planned" : "af_watch_log_set"
                )
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
