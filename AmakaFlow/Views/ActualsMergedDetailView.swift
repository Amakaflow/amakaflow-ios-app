//
//  ActualsMergedDetailView.swift
//  AmakaFlow
//
//  AMA-2387: merged session detail — provenance + Split (screens-actuals2.jsx).
//

import SwiftUI

struct ActualsMergedDetailView: View {
    let session: ActualsSession
    var onSplit: ([ActualsSourceRecording]) -> Void
    var onFillIn: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 10)

                mergeCallout
                    .padding(.top, 12)

                recordingsSection
                    .padding(.top, 14)

                HStack(spacing: 18) {
                    Button(action: splitTapped) {
                        Text(ActualsCopy.mergedSplitCTA)
                            .ddDisplayText(12, weight: .bold)
                            .foregroundColor(DailyDriver.amber)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(ActualsCopy.mergedSplitAccessibilityID)

                    Button(action: onFillIn) {
                        Text(ActualsCopy.mergedFillInCTA)
                            .ddDisplayText(12, weight: .bold)
                            .foregroundColor(DailyDriver.foregroundMuted)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 96)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                dismiss()
            } label: {
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
                DDIconChip(systemName: "flame.fill", background: DailyDriver.lime, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .ddDisplayText(22, weight: .heavy)
                        .foregroundColor(DailyDriver.foreground)
                    if session.isMerged {
                        Text(session.mergeBadge)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundDim)
                    }
                }
            }
        }
    }

    private var mergeCallout: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DailyDriver.lime)
                Text(ActualsCopy.mergedHeadline)
                    .ddDisplayText(13, weight: .bold)
                    .foregroundColor(DailyDriver.lime)
            }
            Text(ActualsCopy.mergedBody)
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
    }

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ActualsCopy.mergedRecordingsHeader)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)

            VStack(spacing: 0) {
                ForEach(Array(session.recordings.enumerated()), id: \.element.id) { index, recording in
                    if index > 0 {
                        Rectangle().fill(DailyDriver.border).frame(height: 1)
                    }
                    recordingRow(recording)
                }
            }
            .padding(.horizontal, 14)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func recordingRow(_ recording: ActualsSourceRecording) -> some View {
        HStack(spacing: 11) {
            DDIconChip(
                systemName: recording.provider == .strava ? "figure.run" : "applewatch",
                background: iconBackground(recording.provider),
                size: 28
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(ActualsCopy.sourceDisplayName(recording.provider))
                    .ddDisplayText(13, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Text(roleLine(recording))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(roleColor(recording.role))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }

    private func roleLine(_ recording: ActualsSourceRecording) -> String {
        let detail: String
        switch recording.provider {
        case .appleHealth: detail = "HEART RATE + CALORIES"
        case .garmin: detail = "LAPS + ROUTE"
        case .strava: detail = "SOCIAL COPY"
        }
        return ActualsCopy.recordingRoleLabel(recording.role, detail: detail)
    }

    private func roleColor(_ role: ActualsRecordingRole) -> Color {
        switch role {
        case .primary: return DailyDriver.lime
        case .attached: return DailyDriver.foregroundMuted
        case .hidden: return DailyDriver.foregroundDim
        }
    }

    private func iconBackground(_ provider: ActualsSourceProvider) -> Color {
        switch provider {
        case .appleHealth: return DailyDriver.card2
        case .garmin: return DailyDriver.blue
        case .strava: return DailyDriver.stravaBrand
        }
    }

    private func splitTapped() {
        let restored = ActualsMergeClassifier.split(session)
        onSplit(restored)
        dismiss()
    }
}

#if DEBUG
private struct MergedDetailFillInPreviewHost: View {
    let session: ActualsSession
    @State private var showFillIn = false

    var body: some View {
        ActualsMergedDetailView(
            session: session,
            onSplit: { _ in },
            onFillIn: { showFillIn = true }
        )
        .fullScreenCover(isPresented: $showFillIn) {
            if let database = try? AppDatabase.makeTestDatabase() {
                let repo = ActualsRepository(database: database)
                ActualsFillInView(
                    viewModel: ActualsFillInViewModel(
                        session: ActualsFillInSession.lowerBodyPosteriorSample(),
                        repository: repo
                    )
                )
            }
        }
    }
}

#Preview("Merged detail") {
    let session = ActualsMergeClassifier.merge([
        ActualsSourceRecording(
            id: "aw", provider: .appleHealth, deviceKind: .watch,
            title: "Hyrox Sim — Stations 1–4", startDate: Date(),
            durationSeconds: 44 * 60, streamRichness: 5
        ),
        ActualsSourceRecording(
            id: "g", provider: .garmin, deviceKind: .watch,
            title: "Hyrox", startDate: Date(),
            durationSeconds: 44 * 60, streamRichness: 4
        ),
        ActualsSourceRecording(
            id: "s", provider: .strava, deviceKind: .phone,
            title: "Hyrox Sim", startDate: Date(),
            durationSeconds: 44 * 60, streamRichness: 2
        )
    ])
    MergedDetailFillInPreviewHost(session: session)
}
#endif
