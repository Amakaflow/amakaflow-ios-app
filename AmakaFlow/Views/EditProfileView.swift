//
//  EditProfileView.swift
//  AmakaFlow
//
//  User-facing edit-profile surface (AMA-1639). Display name + unit
//  preferences, persisted via @AppStorage. Pushed from SettingsView's
//  Account card.
//

import SwiftUI

// MARK: - Distance Unit

enum DistanceUnit: String, Codable, CaseIterable {
    case mi
    case km

    var display: String {
        switch self {
        case .mi: return "mi"
        case .km: return "km"
        }
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("user.displayName") private var displayName: String = ""
    @AppStorage("user.weightUnit") private var weightUnit: WeightUnit = .lbs
    @AppStorage("user.distanceUnit") private var distanceUnit: DistanceUnit = .mi

    /// Read-only fallback shown as the field's placeholder when the user
    /// hasn't set a local display name. Never written back to displayName
    /// — only the user's explicit edits are persisted.
    let initialNameFallback: String?

    @State private var draftName: String = ""
    @State private var hasEditedName: Bool = false

    init(initialNameFallback: String? = nil) {
        self.initialNameFallback = initialNameFallback
    }

    var body: some View {
        Form {
            Section("Profile") {
                TextField(
                    "Display name",
                    text: $draftName,
                    prompt: Text(initialNameFallback ?? "Your name")
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .accessibilityIdentifier("edit_profile_name_field")
                .onChange(of: draftName) { _, _ in hasEditedName = true }
            }

            Section("Units") {
                Picker("Weight", selection: $weightUnit) {
                    Text("lbs").tag(WeightUnit.lbs)
                    Text("kg").tag(WeightUnit.kg)
                }
                .accessibilityIdentifier("edit_profile_weight_unit")

                Picker("Distance", selection: $distanceUnit) {
                    Text("mi").tag(DistanceUnit.mi)
                    Text("km").tag(DistanceUnit.km)
                }
                .accessibilityIdentifier("edit_profile_distance_unit")
            }

            Section {
                Button("Save") {
                    // Only persist the name when the user explicitly edited
                    // it. AMA-1648: write the trimmed value even if it's
                    // empty — that effectively clears the local override
                    // (since "" is the @AppStorage default state) and lets
                    // the placeholder/Clerk fallback show again.
                    if hasEditedName {
                        displayName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    dismiss()
                }
                .accessibilityIdentifier("edit_profile_save")
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Seed the field from the saved value only. Fallback shows in
            // the placeholder; we don't pre-populate the field so a Save
            // tap doesn't accidentally overwrite displayName with the
            // Clerk fallback.
            draftName = displayName
            hasEditedName = false
        }
    }
}

#Preview("Edit Profile") {
    NavigationStack {
        EditProfileView(initialNameFallback: "Sample User")
    }
    .preferredColorScheme(.dark)
}
