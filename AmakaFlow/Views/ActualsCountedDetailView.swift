//
//  ActualsCountedDetailView.swift
//  AmakaFlow
//
//  AMA-2405: read-only detail for counted / kept-as-is — same chrome as
//  verified (header + status callout + optional Strava text). Never re-fetch
//  Strava description when decoration is `.ours` (AmakaFlow already wrote).
//

import SwiftUI

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

struct ActualsCountedDetailView: View {
    let title: String
    let metaLine: String
    let sourceName: String
    let decoration: StravaDecorationState
    let stravaActivityId: String?
    let initialDescription: String
    var onDescriptionLoaded: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss

    /// AmakaFlow already wrote Strava — do not re-pull description (layout stays put).
    private var showsStravaDescription: Bool {
        decoration != .ours
    }

    private var allowsRemoteFetch: Bool {
        decoration != .ours
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 10)

                if decoration.badgeLabel != nil {
                    SZStravaBadge(decoration: decoration)
                        .padding(.top, 10)
                }

                ActualsSessionStatusCallout(
                    headline: ActualsCopy.countedHeadline,
                    bodyText: ActualsCopy.countedCalloutBody(sourceName: sourceName),
                    accessibilityID: ActualsCopy.countedCalloutAccessibilityID
                )
                .padding(.top, 12)

                if showsStravaDescription {
                    ActualsStravaDescriptionSection(
                        stravaActivityId: stravaActivityId,
                        initialDescription: initialDescription,
                        allowsRemoteFetch: allowsRemoteFetch,
                        onLoaded: onDescriptionLoaded
                    )
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 96)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
        .navigationBarBackButtonHidden(true)
        .accessibilityIdentifier(ActualsCopy.countedDetailAccessibilityID)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Today")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DailyDriver.foregroundMuted)
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                DDIconChip(systemName: "dumbbell.fill", background: DailyDriver.purple, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .ddDisplayText(22, weight: .heavy)
                        .foregroundColor(DailyDriver.foreground)
                    Text(metaLine)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Counted detail · untouched") {
    NavigationStack {
        ActualsCountedDetailView(
            title: "Bike ski row repeats",
            metaLine: "20:14 · KEPT AS-IS · FROM STRAVA",
            sourceName: "Strava",
            decoration: .untouched,
            stravaActivityId: nil,
            initialDescription: "Assault bike · ski · row"
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Counted detail · ours (no re-fetch)") {
    NavigationStack {
        ActualsCountedDetailView(
            title: "Bike ski row repeats",
            metaLine: "20:14 · KEPT AS-IS · FROM STRAVA",
            sourceName: "Strava",
            decoration: .ours,
            stravaActivityId: "555",
            initialDescription: ""
        )
    }
    .preferredColorScheme(.dark)
}
#endif
