//
//  StepDisplayView.swift
//  AmakaFlow
//
//  Displays the current workout step with timer and progress
//

import SwiftUI

struct StepDisplayView: View {
    @ObservedObject var engine: WorkoutEngine

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // For reps steps, WeightInputView handles all display including step name
            if engine.currentStep?.stepType == .reps {
                repsDisplay

                // Follow-along button for reps exercises
                if let url = engine.currentStep?.followAlongUrl {
                    followAlongButton(url: url)
                }
            } else {
                // For timed/other steps, show standard layout
                // Round info (if applicable)
                if let roundInfo = engine.currentStep?.roundInfo {
                    Text(roundInfo)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentBlue)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Colors.accentBlue.opacity(0.15))
                        .cornerRadius(Theme.CornerRadius.sm)
                }

                // Step name - shows set info if applicable (e.g., "Squat - Set 1 of 3")
                Text(engine.currentStep?.displayLabel ?? "")
                    .font(Theme.Typography.title1)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                // Timer display (for timed steps and rest with countdown)
                if engine.currentStep?.stepType == .timed ||
                   (engine.currentStep?.stepType == .rest && engine.currentStep?.timerSeconds != nil) {
                    timerDisplay
                }

                // Step details
                if let details = engine.currentStep?.details, !details.isEmpty {
                    Text(details)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                // Follow-along button
                if let url = engine.currentStep?.followAlongUrl {
                    followAlongButton(url: url)
                }
            }
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Timer Display

    private var timerDisplay: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Large timer text
            Text(engine.formattedRemainingTime)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(timerColor)
                .monospacedDigit()

            // Progress ring
            ZStack {
                Circle()
                    .stroke(Theme.Colors.borderLight, lineWidth: 8)
                    .frame(width: 200, height: 200)

                Circle()
                    .trim(from: 0, to: engine.stepProgress)
                    .stroke(
                        timerColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: engine.stepProgress)
            }
            .overlay {
                VStack {
                    Text("remaining")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
    }

    private var timerColor: Color {
        if engine.remainingSeconds <= 3 {
            return Theme.Colors.accentRed
        } else if engine.remainingSeconds <= 10 {
            return Color.orange
        } else {
            return Theme.Colors.accentGreen
        }
    }

    // MARK: - Reps Display (AMA-281: Weight Input)

    private var repsDisplay: some View {
        Group {
            if let step = engine.currentStep {
                // Get last logged weight for this exercise (within this workout)
                let lastWeight = engine.getLastWeight(for: step.label)
                let suggestedWeight = lastWeight?.weight
                let suggestedUnit: WeightUnit = {
                    if let unitStr = lastWeight?.unit {
                        return WeightUnit(rawValue: unitStr) ?? .lbs
                    }
                    return .lbs  // TODO: User preference
                }()

                WeightInputView(
                    exerciseName: step.label,
                    setNumber: step.setNumber ?? 1,
                    totalSets: step.totalSets ?? 1,
                    suggestedWeight: suggestedWeight,
                    suggestedUnit: suggestedUnit,
                    onLogSet: { weight, unit in
                        engine.logSetWeight(weight: weight, unit: unit.rawValue)
                    },
                    onSkipWeight: {
                        engine.logSetWeight(weight: nil, unit: nil)
                    }
                )
            } else {
                // Fallback if no step (shouldn't happen)
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 48))
                        .foregroundColor(Theme.Colors.accentGreen)

                    Text("Complete and tap Next")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.vertical, Theme.Spacing.xl)
            }
        }
    }

    // MARK: - Follow Along Button

    private func followAlongButton(url: String) -> some View {
        Button {
            openFollowAlongUrl(url)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20))
                Text("Watch Demo")
                    .font(Theme.Typography.bodyBold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                LinearGradient(
                    colors: [Color.pink, Color.purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(Theme.CornerRadius.md)
        }
    }

    private func openFollowAlongUrl(_ urlString: String) {
        // Check if it's an Instagram URL
        if urlString.contains("instagram.com") {
            // Try to open in Instagram app first
            let reelId = urlString.components(separatedBy: "/").last ?? ""
            if let instagramUrl = URL(string: "instagram://reel/\(reelId)"),
               UIApplication.shared.canOpenURL(instagramUrl) {
                UIApplication.shared.open(instagramUrl)
                return
            }
        }

        // Fallback to Safari
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Weight Unit (AMA-281)

enum WeightUnit: String, Codable, CaseIterable {
    case lbs
    case kg

    var increment: Double {
        switch self {
        case .lbs: return 5.0
        case .kg: return 2.5
        }
    }

    var mediumIncrement: Double {
        switch self {
        case .lbs: return 10.0
        case .kg: return 5.0
        }
    }

    var largeIncrement: Double {
        switch self {
        case .lbs: return 25.0
        case .kg: return 10.0
        }
    }
}

// MARK: - Weight Input View (AMA-281)

struct WeightInputView: View {
    let exerciseName: String
    let setNumber: Int
    let totalSets: Int
    let onLogSet: (Double?, WeightUnit) -> Void
    let onSkipWeight: () -> Void

    @State private var weight: Double = 0
    @State private var unit: WeightUnit = .lbs
    @State private var isHolding = false
    @State private var holdTimer: Timer?
    @State private var holdDuration: TimeInterval = 0
    @State private var showKeypad = false
    @State private var keypadText = ""

    init(
        exerciseName: String,
        setNumber: Int,
        totalSets: Int,
        suggestedWeight: Double? = nil,
        suggestedUnit: WeightUnit = .lbs,
        onLogSet: @escaping (Double?, WeightUnit) -> Void,
        onSkipWeight: @escaping () -> Void
    ) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.totalSets = totalSets
        self.onLogSet = onLogSet
        self.onSkipWeight = onSkipWeight
        _weight = State(initialValue: suggestedWeight ?? 0)
        _unit = State(initialValue: suggestedUnit)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Exercise and set info
            VStack(spacing: Theme.Spacing.xs) {
                Text(exerciseName.uppercased())
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .tracking(1)

                Text("Set \(setNumber) of \(totalSets)")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            // Weight input controls
            HStack(spacing: Theme.Spacing.lg) {
                // Minus button
                incrementButton(isPlus: false)

                // Weight display (tappable for keypad)
                Button {
                    keypadText = weight > 0 ? String(format: "%.0f", weight) : ""
                    showKeypad = true
                } label: {
                    VStack(spacing: 4) {
                        Text(formattedWeight)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(weight > 0 ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                            .monospacedDigit()

                        // Unit selector
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(WeightUnit.allCases, id: \.self) { weightUnit in
                                Button {
                                    unit = weightUnit
                                } label: {
                                    Text(weightUnit.rawValue)
                                        .font(Theme.Typography.captionBold)
                                        .foregroundColor(unit == weightUnit ? Theme.Colors.accentBlue : Theme.Colors.textTertiary)
                                        .padding(.horizontal, Theme.Spacing.sm)
                                        .padding(.vertical, Theme.Spacing.xs)
                                        .background(
                                            RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                                                .fill(unit == weightUnit ? Theme.Colors.accentBlue.opacity(0.15) : Color.clear)
                                        )
                                }
                            }
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())

                // Plus button
                incrementButton(isPlus: true)
            }
            .padding(.vertical, Theme.Spacing.md)

            // Action buttons
            VStack(spacing: Theme.Spacing.sm) {
                // Skip weight button
                Button {
                    onSkipWeight()
                } label: {
                    Text("SKIP WEIGHT")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.Colors.surface)
                        .cornerRadius(Theme.CornerRadius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                .stroke(Theme.Colors.borderLight, lineWidth: 1)
                        )
                }

                // Log set button
                Button {
                    let logWeight = weight > 0 ? weight : nil
                    onLogSet(logWeight, unit)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                        Text("LOG SET")
                            .font(Theme.Typography.bodyBold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Theme.Colors.accentGreen)
                    .cornerRadius(Theme.CornerRadius.md)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .sheet(isPresented: $showKeypad) {
            WeightKeypadView(
                text: $keypadText,
                unit: unit,
                onDone: { value in
                    if let parsed = Double(value) {
                        weight = parsed
                    }
                    showKeypad = false
                },
                onCancel: {
                    showKeypad = false
                }
            )
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Increment Button

    @ViewBuilder
    private func incrementButton(isPlus: Bool) -> some View {
        let baseIncrement = unit.increment

        Button {
            // Single tap
            adjustWeight(by: isPlus ? baseIncrement : -baseIncrement)
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.Colors.surface)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(Theme.Colors.borderMedium, lineWidth: 2)
                    )

                Image(systemName: isPlus ? "plus" : "minus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.Colors.textPrimary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    startHoldIncrement(isPlus: isPlus)
                }
        )
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            if !pressing {
                stopHoldIncrement()
            }
        }, perform: {})
    }

    // MARK: - Weight Adjustment

    private func adjustWeight(by amount: Double) {
        let newWeight = max(0, weight + amount)
        weight = newWeight
    }

    private func startHoldIncrement(isPlus: Bool) {
        isHolding = true
        holdDuration = 0

        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            holdDuration += 0.1

            // Determine increment based on hold duration
            let increment: Double
            if holdDuration < 0.5 {
                increment = unit.increment
            } else if holdDuration < 1.5 {
                increment = unit.mediumIncrement
            } else {
                increment = unit.largeIncrement
            }

            // Apply increment every 0.15 seconds
            if Int(holdDuration * 10) % 2 == 0 {
                adjustWeight(by: isPlus ? increment : -increment)
            }
        }
    }

    private func stopHoldIncrement() {
        isHolding = false
        holdTimer?.invalidate()
        holdTimer = nil
        holdDuration = 0
    }

    private var formattedWeight: String {
        if weight == 0 {
            return "0"
        }
        return String(format: "%.0f", weight)
    }
}

// MARK: - Weight Keypad View (AMA-281)

struct WeightKeypadView: View {
    @Binding var text: String
    let unit: WeightUnit
    let onDone: (String) -> Void
    let onCancel: () -> Void

    private let buttons: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        [".", "0", "del"]
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Header
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .foregroundColor(Theme.Colors.textSecondary)

                Spacer()

                Text("Enter Weight")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Button("Done") {
                    onDone(text)
                }
                .foregroundColor(Theme.Colors.accentBlue)
                .fontWeight(.semibold)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)

            // Display
            HStack {
                Text(text.isEmpty ? "0" : text)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(text.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)

                Text(unit.rawValue)
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)

            // Keypad
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(buttons, id: \.self) { row in
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(row, id: \.self) { button in
                            keypadButton(button)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
    }

    @ViewBuilder
    private func keypadButton(_ label: String) -> some View {
        Button {
            handleKeypress(label)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                    .fill(Theme.Colors.surface)
                    .frame(height: 52)

                if label == "del" {
                    Image(systemName: "delete.left")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.Colors.textPrimary)
                } else {
                    Text(label)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Theme.Colors.textPrimary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func handleKeypress(_ key: String) {
        switch key {
        case "del":
            if !text.isEmpty {
                text.removeLast()
            }
        case ".":
            if !text.contains(".") {
                text += text.isEmpty ? "0." : "."
            }
        default:
            // Limit to 4 digits before decimal
            let parts = text.split(separator: ".")
            if parts.isEmpty || parts[0].count < 4 {
                text += key
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()

        StepDisplayView(engine: WorkoutEngine.shared)
    }
}
