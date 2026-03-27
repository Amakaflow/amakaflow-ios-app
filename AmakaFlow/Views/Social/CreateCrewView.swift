//
//  CreateCrewView.swift
//  AmakaFlow
//
//  Create a new training crew — name, description, max members (AMA-1277)
//

import SwiftUI

struct CreateCrewView: View {
    @ObservedObject var viewModel: CrewsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var maxMembers = 8

    var body: some View {
        NavigationStack {
            Form {
                Section("Crew Info") {
                    TextField("Crew name", text: $name)
                        .foregroundColor(Theme.Colors.textPrimary)

                    TextField("Description (optional)", text: $description)
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                Section("Size") {
                    Stepper("Max members: \(maxMembers)", value: $maxMembers, in: 3...8)
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                if let error = viewModel.createError {
                    Section {
                        Text(error)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.accentRed)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Create Crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        Task {
                            let desc = description.isEmpty ? nil : description
                            let success = await viewModel.createCrew(
                                name: name,
                                description: desc,
                                maxMembers: maxMembers
                            )
                            if success { dismiss() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isCreating)
                    .foregroundColor(Theme.Colors.accentBlue)
                }
            }
        }
    }
}

#Preview {
    CreateCrewView(viewModel: CrewsViewModel())
        .preferredColorScheme(.dark)
}
