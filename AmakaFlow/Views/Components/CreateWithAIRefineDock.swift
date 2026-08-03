//
//  CreateWithAIRefineDock.swift
//  AmakaFlow
//
//  AMA-2373: Create with AI — refine dock (quick chips + free text, applied
//  tweak history with Undo, "applying…" state, Suggest another = reroll).
//

import SwiftUI

struct CreateWithAIRefineDock: View {
    let appliedTweaks: [String]
    let canUndo: Bool
    let isApplying: Bool
    let onApply: (String) -> Void
    let onUndo: () -> Void
    let onSuggestAnother: () -> Void

    @State private var freeText = ""

    private static let quickTweaks = [
        "Make it shorter",
        "Make it harder",
        "Lower impact",
        "Add more core"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(CreateWithAICopy.refineHeading)

            if !appliedTweaks.isEmpty {
                appliedRows
            }

            if isApplying {
                HStack(spacing: 8) {
                    ProgressView().tint(DailyDriver.lime).scaleEffect(0.8)
                    Text(CreateWithAICopy.refineApplying)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }
                .accessibilityIdentifier("create_with_ai_refine_applying")
            }

            quickChips

            textField

            Button(action: onSuggestAnother) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(CreateWithAICopy.suggestAnother)
                }
                .ddDisplayText(13, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(DailyDriver.card)
                .overlay(Capsule().stroke(DailyDriver.borderStrong, lineWidth: 1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isApplying)
            .opacity(isApplying ? 0.5 : 1)
            .accessibilityIdentifier("create_with_ai_suggest_another")
        }
        .padding(14)
        .background(DailyDriver.backgroundElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("create_with_ai_refine_dock")
    }

    private var appliedRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(appliedTweaks.enumerated()), id: \.offset) { index, tweak in
                let isLast = index == appliedTweaks.count - 1
                HStack(alignment: .top, spacing: 8) {
                    Text("↳")
                        .foregroundColor(DailyDriver.foregroundDim)
                    Text(tweak)
                        .font(.system(size: 12.5))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if isLast, canUndo {
                        Button("Undo", action: onUndo)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(DailyDriver.lime)
                            .disabled(isApplying)
                            .opacity(isApplying ? 0.5 : 1)
                            .accessibilityIdentifier("create_with_ai_refine_undo")
                    }
                }
            }
        }
    }

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.quickTweaks, id: \.self) { tweak in
                    Button {
                        onApply(tweak)
                    } label: {
                        Text(tweak)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DailyDriver.foreground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DailyDriver.card2)
                            .overlay(Capsule().stroke(DailyDriver.borderStrong, lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isApplying)
                    .opacity(isApplying ? 0.5 : 1)
                }
            }
        }
        .accessibilityIdentifier("create_with_ai_refine_chips")
    }

    private var textField: some View {
        HStack(spacing: 8) {
            TextField(CreateWithAICopy.refinePlaceholder, text: $freeText)
                .font(.system(size: 13))
                .foregroundColor(DailyDriver.foreground)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(DailyDriver.inputBackground)
                .overlay(Capsule().stroke(DailyDriver.borderStrong, lineWidth: 1))
                .clipShape(Capsule())
                .accessibilityIdentifier("create_with_ai_refine_field")
                .disabled(isApplying)
                .onSubmit(submitFreeText)

            Button(action: submitFreeText) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DailyDriver.ink)
                    .frame(width: 36, height: 36)
                    .background(trimmedFreeText.isEmpty ? DailyDriver.card2 : DailyDriver.lime)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(trimmedFreeText.isEmpty || isApplying)
            .accessibilityIdentifier("create_with_ai_refine_submit")
        }
    }

    private var trimmedFreeText: String {
        freeText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitFreeText() {
        let text = trimmedFreeText
        guard !text.isEmpty else { return }
        onApply(text)
        freeText = ""
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.25)
            .foregroundColor(DailyDriver.foregroundDim)
    }
}

#if DEBUG
#Preview {
    ZStack {
        DailyDriver.screenBackground.ignoresSafeArea()
        CreateWithAIRefineDock(
            appliedTweaks: ["Make it shorter"],
            canUndo: true,
            isApplying: false,
            onApply: { _ in },
            onUndo: {},
            onSuggestAnother: {}
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}
#endif
