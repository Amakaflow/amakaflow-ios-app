//
//  ActualsMatchSaveView.swift
//  AmakaFlow
//
//  AMA-2387 Map v2: after Builder / photo — attach to session + optional Library.
//

import SwiftUI

struct ActualsMatchSaveView: View {
    let activity: ActualsUnmappedActivity
    let draft: ActualsCaptureDraft
    /// Final draft (with user title) + whether Library save succeeded.
    var onComplete: (_ finalDraft: ActualsCaptureDraft, _ alsoSaveToLibrary: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var workoutTitle: String
    @State private var alsoSaveToLibrary = true
    @State private var isSaving = false
    @State private var saveError: String?

    init(
        activity: ActualsUnmappedActivity,
        draft: ActualsCaptureDraft,
        onComplete: @escaping (_ finalDraft: ActualsCaptureDraft, _ alsoSaveToLibrary: Bool) -> Void
    ) {
        self.activity = activity
        self.draft = draft
        self.onComplete = onComplete
        let incoming = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholder = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let initial: String = {
            if incoming.isEmpty || incoming.localizedCaseInsensitiveCompare("Captured session") == .orderedSame {
                return placeholder
            }
            return incoming
        }()
        _workoutTitle = State(initialValue: initial)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, 10)

                    youBuiltCard
                        .padding(.top, 14)

                    DDStatusBanner(
                        style: .lime(
                            title: ActualsCopy.captureBannerTitle,
                            body: ActualsCaptureContext.bannerDetail(for: activity)
                        )
                    )
                    .padding(.top, 12)

                    Text(ActualsCopy.matchSaveBody)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)

                    libraryToggleCard
                        .padding(.top, 14)

                    if !alsoSaveToLibrary {
                        Text(ActualsCopy.matchSaveLibraryOffNote)
                            .font(.system(size: 10))
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .padding(.top, 8)
                    }

                    if let saveError {
                        Text(saveError)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DailyDriver.amber)
                            .padding(.top, 10)
                    }

                    Text(ActualsCopy.matchSaveFooter)
                        .font(.system(size: 10))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }

            Button(action: confirm) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .tint(DailyDriver.ink)
                    }
                    Text(
                        alsoSaveToLibrary
                            ? ActualsCopy.matchSaveCTAWithLibrary
                            : ActualsCopy.matchSaveCTASessionOnly
                    )
                    .ddDisplayText(14.5, weight: .bold)
                    .foregroundColor(DailyDriver.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(DailyDriver.lime)
                .clipShape(Capsule(style: .continuous))
                .ddLimeGlow()
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .accessibilityIdentifier(ActualsCopy.matchSaveCTAAccessibilityID)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
        .accessibilityIdentifier(ActualsCopy.matchSaveAccessibilityID)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(DailyDriver.foregroundMuted)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            Text(ActualsCopy.matchSaveTitle)
                .ddDisplayText(22, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
        }
    }

    private var youBuiltCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ActualsCopy.matchSaveYouBuilt)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)

            Text(ActualsCopy.matchSaveNameLabel)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundDim)

            TextField(ActualsCopy.matchSaveNamePlaceholder, text: $workoutTitle)
                .ddDisplayText(16, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(DailyDriver.card2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(isSaving)
                .accessibilityIdentifier(ActualsCopy.matchSaveNameFieldID)

            HStack(spacing: 8) {
                chip(draft.blocksLabel)
                ForEach(draft.blockSummaries.prefix(2), id: \.self) { line in
                    chip(line.uppercased())
                }
                chip("~\(draft.estimatedMinutes) MIN")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundMuted)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DailyDriver.card2)
            .clipShape(Capsule())
    }

    private var libraryToggleCard: some View {
        Button {
            alsoSaveToLibrary.toggle()
        } label: {
            HStack(spacing: 12) {
                DDIconChip(
                    systemName: "bookmark.fill",
                    background: DailyDriver.lime,
                    size: 32
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(ActualsCopy.matchSaveLibraryTitle)
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(ActualsCopy.matchSaveLibrarySub)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: alsoSaveToLibrary ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(alsoSaveToLibrary ? DailyDriver.lime : DailyDriver.foregroundDim)
            }
            .padding(14)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        alsoSaveToLibrary ? DailyDriver.lime.opacity(0.45) : DailyDriver.border,
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityIdentifier(ActualsCopy.matchSaveLibraryToggleID)
        .accessibilityAddTraits(alsoSaveToLibrary ? .isSelected : [])
    }

    private var titledDraft: ActualsCaptureDraft {
        var next = draft
        next.title = workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return next
    }

    private func confirm() {
        guard !isSaving else { return }
        let trimmed = workoutTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveError = ActualsCopy.matchSaveNameRequired
            return
        }
        isSaving = true
        saveError = nil
        let finalDraft = titledDraft
        Task {
            var savedToLibrary = false
            if alsoSaveToLibrary {
                do {
                    let request = finalDraft.toWorkoutSaveRequest()
                    let saved = try await AppDependencies.current.apiService.saveWorkout(request)
                    _ = WorkoutLibraryDetailStore.saveAfterEditor(saved: saved, request: request)
                    NotificationCenter.default.post(name: .libraryContentDidChange, object: nil)
                    savedToLibrary = true
                    DDToastCenter.shared.success(
                        DDToastCopy.savedToLibrary,
                        sub: DDToastCopy.savedSub(
                            workoutName: finalDraft.title,
                            minutes: finalDraft.estimatedMinutes,
                            collection: "Library"
                        )
                    )
                } catch {
                    await MainActor.run {
                        saveError = "Library save failed — session still matched."
                    }
                }
            }
            DDToastCenter.shared.success(
                ActualsCopy.matchSaveToastMatched,
                sub: ActualsCopy.matchSaveToastMatchedSub
            )
            await MainActor.run {
                isSaving = false
                onComplete(finalDraft, savedToLibrary)
            }
        }
    }
}

#if DEBUG
#Preview("Match save") {
    let activity = ActualsUnmappedActivity(
        title: "Gym session",
        provider: .garmin,
        startDate: Date(),
        durationSeconds: 44 * 60,
        distanceMeters: nil,
        calories: 486,
        avgHR: 151,
        type: .strength
    )
    ActualsMatchSaveView(
        activity: activity,
        draft: .sampleHyrox(),
        onComplete: { _, _ in }
    )
}
#endif
