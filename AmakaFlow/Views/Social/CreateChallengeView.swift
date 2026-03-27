//
//  CreateChallengeView.swift
//  AmakaFlow
//
//  Form for creating a new challenge — title, type, target, dates, team mode (AMA-1276)
//

import SwiftUI

struct CreateChallengeView: View {
    @ObservedObject var viewModel: ChallengesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var selectedType: ChallengeType = .volume
    @State private var target = ""
    @State private var targetUnit = "kg"
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var isTeamMode = false

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !target.isEmpty &&
        Double(target) != nil &&
        endDate > startDate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    formField(label: "Challenge Title") {
                        TextField("e.g., 10k Volume Week", text: $title)
                            .textFieldStyle(.plain)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .padding(12)
                            .background(Theme.Colors.surfaceElevated)
                            .cornerRadius(10)
                    }

                    formField(label: "Challenge Type") {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(ChallengeType.allCases) { type in
                                Button {
                                    selectedType = type
                                    updateDefaultUnit()
                                } label: {
                                    Text(type.displayName)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(selectedType == type ? .white : Theme.Colors.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(selectedType == type ? colorForType(type) : Theme.Colors.surfaceElevated)
                                        .cornerRadius(10)
                                }
                            }
                        }
                    }

                    formField(label: "Target") {
                        HStack(spacing: Theme.Spacing.sm) {
                            TextField("e.g., 10000", text: $target)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.plain)
                                .foregroundColor(Theme.Colors.textPrimary)
                                .padding(12)
                                .background(Theme.Colors.surfaceElevated)
                                .cornerRadius(10)

                            Text(targetUnit)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .frame(width: 40)
                        }
                    }

                    formField(label: "Description (optional)") {
                        TextField("What's the challenge about?", text: $description, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.plain)
                            .foregroundColor(Theme.Colors.textPrimary)
                            .padding(12)
                            .background(Theme.Colors.surfaceElevated)
                            .cornerRadius(10)
                    }

                    formField(label: "Start Date") {
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(Theme.Colors.accentBlue)
                    }

                    formField(label: "End Date") {
                        DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(Theme.Colors.accentBlue)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Team Mode")
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("Participants work together toward the target")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }

                        Spacer()

                        Toggle("", isOn: $isTeamMode)
                            .labelsHidden()
                            .tint(Theme.Colors.accentBlue)
                    }

                    if let error = viewModel.createError {
                        Text(error)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.accentRed)
                    }

                    Button {
                        Task { await createChallenge() }
                    } label: {
                        HStack {
                            if viewModel.isCreating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Create Challenge")
                            }
                        }
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isFormValid ? Theme.Colors.accentBlue : Theme.Colors.surfaceElevated)
                        .cornerRadius(12)
                    }
                    .disabled(!isFormValid || viewModel.isCreating)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.Colors.accentBlue)
                }
            }
        }
    }

    private func formField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.Colors.textSecondary)
            content()
        }
    }

    private func createChallenge() async {
        guard let targetValue = Double(target) else { return }

        let request = CreateChallengeRequest(
            title: title.trimmingCharacters(in: .whitespaces),
            type: selectedType,
            description: description.isEmpty ? nil : description,
            target: targetValue,
            targetUnit: targetUnit,
            startDate: startDate,
            endDate: endDate,
            isTeamMode: isTeamMode
        )

        let success = await viewModel.createChallenge(request)
        if success {
            dismiss()
        }
    }

    private func updateDefaultUnit() {
        switch selectedType {
        case .volume: targetUnit = "kg"
        case .consistency: targetUnit = "days"
        case .pr: targetUnit = "kg"
        }
    }
}

#Preview {
    CreateChallengeView(viewModel: ChallengesViewModel())
        .preferredColorScheme(.dark)
}
