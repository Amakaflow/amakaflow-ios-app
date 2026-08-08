//
//  ActualsFillInView.swift
//  AmakaFlow
//
//  AMA-2387: fill-in actuals — planned vs done (screens-actuals.jsx SYActualsScreen).
//

import SwiftUI

struct ActualsFillInView: View {
    @ObservedObject var viewModel: ActualsFillInViewModel
    var onSaved: () -> Void = {}
    var onBack: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, 10)

                    ForEach(viewModel.session.exercises) { exercise in
                        exerciseRow(exercise)
                            .padding(.top, 8)
                    }

                    Text(ActualsCopy.fillInRPEHeader)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .padding(.top, 14)
                        .padding(.bottom, 8)

                    rpeGrid

                    Text(ActualsCopy.fillInFooterNote)
                        .font(.system(size: 10))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }

            saveCTA
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if let onBack {
                    onBack()
                } else {
                    dismiss()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(ActualsCopy.fillInBackLabel)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DailyDriver.foregroundMuted)
            }
            .buttonStyle(.plain)

            Text(ActualsCopy.fillInTitle)
                .ddDisplayText(22, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .padding(.top, 8)

            Text(viewModel.progressLine)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
                .padding(.top, 4)

            Button {
                viewModel.markAllAsPlanned()
                DDToastCenter.shared.success(ActualsCopy.fillInAllAsPlannedToast)
            } label: {
                Text(ActualsCopy.fillInAllAsPlannedCTA)
                    .ddDisplayText(11.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(DailyDriver.card2)
                    .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 9)
            .accessibilityIdentifier(ActualsCopy.fillInAllAsPlannedAccessibilityID)
        }
    }

    // MARK: - Rows

    private func exerciseRow(_ exercise: ExerciseActual) -> some View {
        let confirmed = exercise.isConfirmed
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(ActualsCopy.fillInPlannedLine(exercise.planned))
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                confirmationSegment(exercise)
            }

            if exercise.confirmation == .adjusted {
                steppers(exercise)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    confirmed ? DailyDriver.lime.opacity(0.35) : DailyDriver.border,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier(exercise.accessibilityRowID)
    }

    private func confirmationSegment(_ exercise: ExerciseActual) -> some View {
        HStack(spacing: 0) {
            segmentButton(
                title: ActualsCopy.fillInAsPlannedSegment,
                selected: exercise.confirmation == .asPlanned,
                accessibilityID: exercise.accessibilityAsPlannedID
            ) {
                viewModel.markAsPlanned(exerciseID: exercise.id)
            }
            segmentButton(
                title: ActualsCopy.fillInAdjustSegment,
                selected: exercise.confirmation == .adjusted,
                accessibilityID: exercise.accessibilityAdjustID
            ) {
                viewModel.markAdjust(exerciseID: exercise.id)
            }
        }
        .padding(2)
        .background(DailyDriver.card2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(width: 150)
    }

    private func segmentButton(
        title: String,
        selected: Bool,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(selected ? DailyDriver.ink : DailyDriver.foregroundMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selected ? DailyDriver.lime : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func steppers(_ exercise: ExerciseActual) -> some View {
        HStack(spacing: 8) {
            stepper(
                label: "SETS",
                valueText: "\(exercise.actualSets)",
                ghost: nil,
                decrement: { viewModel.setActualSets(exerciseID: exercise.id, sets: exercise.actualSets - 1) },
                increment: { viewModel.setActualSets(exerciseID: exercise.id, sets: exercise.actualSets + 1) }
            )
            stepper(
                label: "REPS",
                valueText: "\(exercise.actualReps)",
                ghost: nil,
                decrement: { viewModel.setActualReps(exerciseID: exercise.id, reps: exercise.actualReps - 1) },
                increment: { viewModel.setActualReps(exerciseID: exercise.id, reps: exercise.actualReps + 1) }
            )
            if exercise.planned.weightKg != nil || exercise.actualWeightKg != nil {
                let kg = exercise.actualWeightKg ?? exercise.planned.weightKg ?? 0
                let ghost: String? = {
                    guard let planned = exercise.planned.weightKg, planned != kg else { return nil }
                    return ActualsCopy.fillInPlannedGhostKg(planned)
                }()
                stepper(
                    label: "KG",
                    valueText: kg == floor(kg) ? "\(Int(kg))" : String(format: "%.1f", kg),
                    ghost: ghost,
                    decrement: { viewModel.setActualWeightKg(exerciseID: exercise.id, kg: kg - 2.5) },
                    increment: { viewModel.setActualWeightKg(exerciseID: exercise.id, kg: kg + 2.5) }
                )
            }
        }
    }

    private func stepper(
        label: String,
        valueText: String,
        ghost: String?,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
            HStack(spacing: 8) {
                Button("−", action: decrement)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .buttonStyle(.plain)
                Text(valueText)
                    .ddDisplayText(15, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)
                    .frame(maxWidth: .infinity)
                Button("＋", action: increment)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .buttonStyle(.plain)
            }
            .padding(.top, 4)
            if let ghost {
                Text(ghost)
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(DailyDriver.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - RPE + CTA

    private var rpeGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(1...10, id: \.self) { value in
                let selected = viewModel.rpe == value
                Button {
                    viewModel.selectRPE(value)
                } label: {
                    Text("\(value)")
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(selected ? DailyDriver.ink : DailyDriver.foreground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(selected ? DailyDriver.lime : DailyDriver.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(ActualsCopy.fillInRPEAccessibilityID(value))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var saveCTA: some View {
        let ready = viewModel.canSave
        return Button {
            do {
                if try viewModel.save() {
                    onSaved()
                    dismiss()
                }
            } catch {
                // lastSaveError already set on the view model
            }
        } label: {
            Text(viewModel.saveCTATitle)
                .ddDisplayText(14.5, weight: .bold)
                .foregroundColor(ready ? DailyDriver.ink : DailyDriver.foregroundDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(ready ? DailyDriver.lime : DailyDriver.card2)
                .clipShape(Capsule(style: .continuous))
                .modifier(FillInCTAGlow(active: ready))
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .accessibilityIdentifier(ActualsCopy.fillInSaveAccessibilityID)
    }
}

private struct FillInCTAGlow: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.ddLimeGlow()
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("Fill-in actuals") {
    let session = ActualsFillInSession.lowerBodyPosteriorSample()
    let repo = ActualsRepository(database: try! AppDatabase.makeTestDatabase())
    ActualsFillInView(viewModel: ActualsFillInViewModel(session: session, repository: repo))
}
#endif
