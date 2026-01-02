//
//  TranscriptionReviewView.swift
//  AmakaFlow
//
//  View for reviewing and editing transcribed text (AMA-5)
//

import SwiftUI

struct TranscriptionReviewView: View {
    @ObservedObject var viewModel: VoiceWorkoutViewModel
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.Colors.accentBlue)

                    Text("Review Transcription")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Edit the text below if needed, then create your workout")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                // Transcription editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your description:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    TextEditor(text: $viewModel.transcription)
                        .frame(minHeight: 150)
                        .padding(12)
                        .background(Theme.Colors.surface)
                        .cornerRadius(12)
                        .focused($isTextFieldFocused)
                        .scrollContentBackground(.hidden)
                }
                .padding(.horizontal)

                // Sport type selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workout type (helps with parsing):")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    SportPicker(selectedSport: $viewModel.selectedSport)
                }
                .padding(.horizontal)

                // Tips
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tips for better results:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        TipRow(icon: "checkmark.circle", text: "Include specific numbers (sets, reps, duration)")
                        TipRow(icon: "checkmark.circle", text: "Name your exercises clearly")
                        TipRow(icon: "checkmark.circle", text: "Mention rest periods if any")
                        TipRow(icon: "checkmark.circle", text: "Specify warmup and cooldown")
                    }
                }
                .padding()
                .background(Theme.Colors.surface)
                .cornerRadius(12)
                .padding(.horizontal)

                Spacer(minLength: 100)
            }
        }
        .background(Theme.Colors.background)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    isTextFieldFocused = false
                    Task {
                        await viewModel.confirmTranscription()
                    }
                } label: {
                    Text("Create Workout")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.Colors.accentBlue)
                        .cornerRadius(12)
                }

                Button("Record Again") {
                    viewModel.startOver()
                }
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Theme.Colors.background)
        }
        .onTapGesture {
            isTextFieldFocused = false
        }
    }
}

// MARK: - Sport Picker

private struct SportPicker: View {
    @Binding var selectedSport: WorkoutSport

    private let sports: [WorkoutSport] = [.cardio, .running, .strength, .cycling, .mobility, .swimming]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sports, id: \.self) { sport in
                    SportButton(
                        sport: sport,
                        isSelected: selectedSport == sport,
                        action: { selectedSport = sport }
                    )
                }
            }
            .padding(.horizontal)
        }
        .padding(.horizontal, -16)
    }
}

private struct SportButton: View {
    let sport: WorkoutSport
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: iconForSport(sport))
                Text(sport.rawValue.capitalized)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Theme.Colors.accentBlue : Theme.Colors.surface)
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }

    private func iconForSport(_ sport: WorkoutSport) -> String {
        switch sport {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .mobility: return "figure.flexibility"
        case .swimming: return "figure.pool.swim"
        case .cardio: return "heart.fill"
        case .other: return "sportscourt"
        }
    }
}

// MARK: - Tip Row

private struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.green)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TranscriptionReviewView(viewModel: {
            let vm = VoiceWorkoutViewModel()
            // Note: Can't set transcription directly in preview since it's a binding
            return vm
        }())
        .navigationTitle("Review Transcription")
    }
}
