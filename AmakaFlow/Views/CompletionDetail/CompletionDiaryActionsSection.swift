//
//  CompletionDiaryActionsSection.swift
//  AmakaFlow
//
//  AMA-2289: verify / map / enrich on completed diary items (no structure edit).
//

import SwiftUI

struct CompletionDiaryActionsSection: View {
    @ObservedObject var viewModel: CompletionDetailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DIARY ACTIONS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("af_completion_diary_actions")

            Text("Completed sessions are locked — verify, map, or enrich without editing structure.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(viewModel.diaryActions) { action in
                Button {
                    viewModel.performDiaryAction(action)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: action.systemImage)
                            .foregroundColor(Theme.Colors.accentGreen)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(action.subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        if action == .verify, viewModel.isVerified {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(action.accessibilityIdentifier)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct CompletionDiaryMapSheet: View {
    @ObservedObject var viewModel: CompletionDetailViewModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.detail?.distanceMeters != nil
                     ? "Route map from the synced activity. Structure stays locked."
                     : "Map device exercise names to your library. Structure stays locked.")
                    .font(.body)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { viewModel.showingMapSheet = false }
                }
            }
            .accessibilityIdentifier("af_completion_map_sheet")
        }
        .presentationDetents([.medium])
    }
}

struct CompletionDiaryEnrichSheet: View {
    @ObservedObject var viewModel: CompletionDetailViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("How did it feel?", text: $viewModel.enrichNote, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("af_completion_enrich_note")
                }
                Section {
                    Text("Enrich adds notes only — never edits the completed workout structure.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Enrich")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.showingEnrichSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { viewModel.saveEnrichNote() }
                        .accessibilityIdentifier("af_completion_enrich_save")
                }
            }
            .accessibilityIdentifier("af_completion_enrich_sheet")
        }
        .presentationDetents([.medium])
    }
}

struct CompletionDiaryActionToast: View {
    @ObservedObject var viewModel: CompletionDetailViewModel

    var body: some View {
        VStack {
            Spacer()
            Text(viewModel.diaryActionToastMessage)
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
                .padding(.bottom, 50)
                .accessibilityIdentifier("af_completion_diary_toast")
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut, value: viewModel.showDiaryActionToast)
    }
}
