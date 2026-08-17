//
//  EditorV2CoachSheet.swift
//  AmakaFlow
//
//  AMA-2443 slice 2b — "Ask Amaka" from the exercise picker.
//

import SwiftUI

/// Coach sheet for "Ask Amaka" from the exercise picker. Uses the app-level
/// `CoachSessionStore` from the environment — iOS has ONE coach session
/// (AMA-2234); creating a fresh store here would fork the conversation.
struct EditorV2CoachSheet: View {
    let prefillQuery: String?
    let clearPrefill: () -> Void
    @EnvironmentObject private var coachSession: CoachSessionStore

    var body: some View {
        CoachChatView()
            .task { await sendPrefillIfNeeded() }
    }

    private func sendPrefillIfNeeded() async {
        guard let query = prefillQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else { return }
        // Clear before sending so a re-presentation never resends the query.
        clearPrefill()
        // CoachChatView's own .task also kicks off session restore; wait it
        // out — sendMessage rejects sends while a restore is in flight.
        await coachSession.loadMessagesIfNeeded()
        while coachSession.isLoadingMessages {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        await coachSession.sendMessage(query)
    }
}
