//
//  LibraryView+Collections.swift
//  AmakaFlow
//
//  AMA-2376: New Collection alert + pin helpers for Library.
//

import SwiftUI

extension LibraryView {
    var pinnedWorkouts: [Workout] {
        viewModel.collectionsStore.pinnedIDs.compactMap { viewModel.workoutsByID[$0] }
    }

    func unpinWorkout(_ workoutID: String) {
        do {
            try viewModel.collectionsStore.setPinned(workoutId: workoutID, isPinned: false)
        } catch {
            collectionsAlertMessage = "Couldn't unpin workout — try again"
        }
    }

    func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        newCollectionName = ""
        guard !name.isEmpty else { return }
        do {
            let created = try viewModel.collectionsStore.createCollection(name: name, note: nil)
            navigationPath.append(.collection(id: created.id))
        } catch {
            collectionsAlertMessage = "Couldn't create collection — try again"
        }
    }
}

extension View {
    /// AMA-2376: "+ New" collection name prompt used by Library content.
    func libraryNewCollectionAlert(
        isPresented: Binding<Bool>,
        name: Binding<String>,
        onCreate: @escaping () -> Void
    ) -> some View {
        alert("New Collection", isPresented: isPresented) {
            TextField("Collection name", text: name)
            Button("Cancel", role: .cancel) {
                name.wrappedValue = ""
            }
            Button("Create", action: onCreate)
        } message: {
            Text("Group workouts together, e.g. \u{201C}Hyrox Prep\u{201D} or \u{201C}Push / Pull / Legs\u{201D}.")
        }
    }

    /// AMA-2376: local collection write failures (create / pin / membership).
    func libraryCollectionsFailureAlert(message: Binding<String?>) -> some View {
        alert(
            "Couldn't update collections",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
