//
//  JoinCrewView.swift
//  AmakaFlow
//
//  Join a training crew by entering an invite code (AMA-1277)
//

import SwiftUI

struct JoinCrewView: View {
    @ObservedObject var viewModel: CrewsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var inviteCode = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                Image(systemName: "person.badge.plus")
                    .font(.system(size: 56))
                    .foregroundColor(Theme.Colors.accentBlue)

                Text("Join a Crew")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("Enter the 8-character invite code shared by a crew member.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)

                TextField("Invite Code", text: $inviteCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .onChange(of: inviteCode) { _, newValue in
                        inviteCode = String(newValue.prefix(8)).uppercased()
                    }

                if let error = viewModel.joinError {
                    Text(error)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentRed)
                }

                if viewModel.joinSuccess {
                    Label("Joined successfully!", systemImage: "checkmark.circle.fill")
                        .foregroundColor(Theme.Colors.accentGreen)
                        .font(Theme.Typography.bodyBold)
                }

                Button {
                    Task {
                        // We need the crew ID — for now we use the invite code to find it
                        // The API supports join by crew_id + invite_code validation
                        let success = await viewModel.joinCrew(crewId: inviteCode, inviteCode: inviteCode)
                        if success {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                dismiss()
                            }
                        }
                    }
                } label: {
                    if viewModel.isJoining {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Join Crew")
                            .font(Theme.Typography.bodyBold)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(inviteCode.count == 8 ? Theme.Colors.accentBlue : Theme.Colors.surface)
                .cornerRadius(12)
                .disabled(inviteCode.count != 8 || viewModel.isJoining)
                .padding(.horizontal, Theme.Spacing.xl)

                Spacer()
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }
        }
    }
}

#Preview {
    JoinCrewView(viewModel: CrewsViewModel())
        .preferredColorScheme(.dark)
}
