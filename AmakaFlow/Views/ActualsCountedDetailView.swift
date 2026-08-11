//
//  ActualsCountedDetailView.swift
//  AmakaFlow
//
//  AMA-2405: shared read-only detail chrome (status callout + optional Strava
//  text) used by `ActualsVerifiedView`. Never re-fetch Strava description
//  when decoration is `.ours` (AmakaFlow already wrote).
//
//  AMA-2407: the durable "Counted" detail screen that originally lived here
//  was removed — Verify-as-is always renders through `ActualsVerifiedView`,
//  which is why the type names below still say "Counted"/"Verified" for the
//  shared pieces they were extracted from.
//

import SwiftUI

/// AMA-2405: gate Strava description UI/fetch for counted + verified details.
enum ActualsStravaDescriptionPolicy {
    /// Hide the section for `.ours`, and for non-Strava cards with no activity id/text.
    static func showsDescriptionSection(
        decoration: StravaDecorationState,
        stravaActivityId: String?,
        cachedDescription: String
    ) -> Bool {
        guard decoration != .ours else { return false }
        let hasActivityId = !(stravaActivityId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let hasCachedDescription = !cachedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        return hasActivityId || hasCachedDescription
    }

    /// AmakaFlow already wrote Strava — do not re-pull description.
    static func allowsRemoteFetch(decoration: StravaDecorationState) -> Bool {
        decoration != .ours
    }
}

/// Shared Strava description body — loads detail when the sync list omitted it.
/// Skip remote fetch when AmakaFlow already owns the Strava text (`.ours`).
struct ActualsStravaDescriptionSection: View {
    let stravaActivityId: String?
    let initialDescription: String
    /// AMA-2405: false when `STRAVA ✓ OURS` — do not pull Strava again.
    var allowsRemoteFetch: Bool = true
    var onLoaded: ((String) -> Void)?

    @State private var descriptionText: String
    @State private var isLoading = false
    @State private var loadFailed = false

    init(
        stravaActivityId: String?,
        initialDescription: String,
        allowsRemoteFetch: Bool = true,
        onLoaded: ((String) -> Void)? = nil
    ) {
        self.stravaActivityId = stravaActivityId
        self.initialDescription = initialDescription
        self.allowsRemoteFetch = allowsRemoteFetch
        self.onLoaded = onLoaded
        _descriptionText = State(initialValue: initialDescription.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ActualsCopy.stravaDescriptionLabel)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)

            if isLoading && descriptionText.isEmpty {
                Text(ActualsCopy.stravaDescriptionLoading)
                    .font(.system(size: 13))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if descriptionText.isEmpty {
                Text(loadFailed
                      ? ActualsCopy.stravaDescriptionLoadFailed
                      : ActualsCopy.stravaDescriptionEmpty)
                    .font(.system(size: 13))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(descriptionText)
                    .font(.system(size: 14))
                    .foregroundColor(DailyDriver.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: "\(stravaActivityId ?? "")-\(allowsRemoteFetch)") {
            await loadIfNeeded()
        }
    }

    @MainActor
    private func loadIfNeeded() async {
        guard allowsRemoteFetch,
              descriptionText.isEmpty,
              let activityId = stravaActivityId,
              !activityId.isEmpty else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let detail = try await BFFStravaClient.live().getActivityDetail(activityId: activityId)
            let text = detail.description.trimmingCharacters(in: .whitespacesAndNewlines)
            descriptionText = text
            if !text.isEmpty {
                onLoaded?(text)
            }
        } catch {
            loadFailed = true
        }
    }
}

/// Lime status callout — shared visual with verified (screens-actuals verified card).
struct ActualsSessionStatusCallout: View {
    let headline: String
    let bodyText: String
    var accessibilityID: String = ActualsCopy.verifiedCalloutAccessibilityID

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DailyDriver.lime)
                Text(headline)
                    .ddDisplayText(13, weight: .bold)
                    .foregroundColor(DailyDriver.lime)
                Spacer(minLength: 8)
            }
            Text(bodyText)
                .font(.system(size: 11))
                .foregroundColor(DailyDriver.foregroundMuted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DailyDriver.lime.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.lime.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier(accessibilityID)
    }
}
