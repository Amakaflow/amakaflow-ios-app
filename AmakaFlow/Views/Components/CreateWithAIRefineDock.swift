//
//  CreateWithAIRefineDock.swift
//  AmakaFlow
//
//  AMA-2373: Create with AI — refine dock matching the mock (quick chips +
//  free-text bar, ↳ applied rows with Undo). Suggest another stays available
//  but is not a primary chrome element.
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

    /// Short chip labels matching the rig; applied as full tweak phrases so the
    /// coach still gets clear instructions.
    private static let quickTweaks: [(label: String, tweak: String)] = [
        ("Shorter", "Make it shorter"),
        ("Harder", "Make it harder"),
        ("Lower impact", "Lower impact"),
        ("More volume", "Add more volume")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .disabled(isApplying)
            .opacity(isApplying ? 0.5 : 1)
            .accessibilityIdentifier("create_with_ai_suggest_another")
        }
        .accessibilityIdentifier("create_with_ai_refine_dock")
    }

    private var appliedRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(appliedTweaks.enumerated()), id: \.offset) { index, tweak in
                let isLast = index == appliedTweaks.count - 1
                HStack(alignment: .center, spacing: 8) {
                    Text("↳ '\(tweak)'\(CreateWithAICopy.refineAppliedSuffix)")
                        .font(.system(size: 12.5))
                        .foregroundColor(DailyDriver.blue)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(DailyDriver.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DailyDriver.blue.opacity(0.45), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.quickTweaks, id: \.label) { item in
                    Button {
                        onApply(item.tweak)
                    } label: {
                        Text(item.label)
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
                .padding(.vertical, 12)
                .background(DailyDriver.inputBackground)
                .overlay(Capsule().stroke(DailyDriver.borderStrong, lineWidth: 1))
                .clipShape(Capsule())
                .accessibilityIdentifier("create_with_ai_refine_field")
                .disabled(isApplying)
                .onSubmit(submitFreeText)

            Button(action: submitFreeText) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(trimmedFreeText.isEmpty ? DailyDriver.foregroundDim : DailyDriver.ink)
                    .frame(width: 40, height: 40)
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
}

#if DEBUG
#Preview {
    ZStack {
        DailyDriver.screenBackground.ignoresSafeArea()
        CreateWithAIRefineDock(
            appliedTweaks: ["make it 30 minutes"],
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
