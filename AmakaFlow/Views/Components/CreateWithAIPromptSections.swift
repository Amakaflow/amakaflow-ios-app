//
//  CreateWithAIPromptSections.swift
//  AmakaFlow
//
//  AMA-2373 — compose ask field + starter chips extracted from
//  CreateWithAIPromptView to satisfy SwiftLint type_body_length.
//

import SwiftUI

struct CreateWithAIAskField: View {
    @Binding var ask: String
    var onMicTap: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if ask.isEmpty {
                Text("e.g. A strength session with extra core")
                    .font(.system(size: 15))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $ask)
                .font(.system(size: 15))
                .foregroundColor(DailyDriver.foreground)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .padding(.trailing, 42)
                .frame(minHeight: 128)
                .accessibilityIdentifier("create_with_ai_prompt_field")

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: onMicTap) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DailyDriver.foreground)
                            .frame(width: 36, height: 36)
                            .background(DailyDriver.card2)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Speak workout request")
                    .accessibilityHint("Voice input is not available yet")
                    .accessibilityIdentifier("create_with_ai_mic")
                }
            }
            .padding(10)
        }
        .background(DailyDriver.inputBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DailyDriver.borderStrong, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct CreateWithAIStartersGrid: View {
    @Binding var ask: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("OR START FROM")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.25)
                .foregroundColor(DailyDriver.foregroundDim)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(CreateWithAICopy.starters, id: \.self) { starter in
                    Button {
                        ask = starter
                    } label: {
                        Text(starter)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(DailyDriver.foreground)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(DailyDriver.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(DailyDriver.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
