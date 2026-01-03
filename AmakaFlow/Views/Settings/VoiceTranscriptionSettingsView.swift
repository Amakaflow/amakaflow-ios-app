//
//  VoiceTranscriptionSettingsView.swift
//  AmakaFlow
//
//  Settings UI for voice transcription provider and accent configuration (AMA-229)
//

import SwiftUI

struct VoiceTranscriptionSettingsView: View {
    @StateObject private var router = TranscriptionRouter.shared
    @StateObject private var dictionary = PersonalDictionary.shared

    @State private var showingAddCorrection = false
    @State private var showingAddTerm = false
    @State private var newWrongPhrase = ""
    @State private var newCorrectPhrase = ""
    @State private var newCustomTerm = ""

    var body: some View {
        List {
            // Provider selection
            providerSection

            // Accent selection
            accentSection

            // Cloud fallback settings
            if router.preferredProvider == .smart || router.preferredProvider == .onDevice {
                fallbackSection
            }

            // Personal dictionary
            dictionarySection

            // Custom terms
            customTermsSection
        }
        .navigationTitle("Voice Transcription")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddCorrection) {
            addCorrectionSheet
        }
        .sheet(isPresented: $showingAddTerm) {
            addTermSheet
        }
    }

    // MARK: - Provider Section

    private var providerSection: some View {
        Section {
            ForEach(TranscriptionProvider.allCases) { provider in
                Button {
                    router.preferredProvider = provider
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(provider.displayName)
                                    .foregroundColor(.primary)

                                if provider == router.recommendedProvider {
                                    Text("Recommended")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.Colors.accentGreen)
                                        .cornerRadius(4)
                                }
                            }

                            Text(provider.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(provider.costInfo)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(provider.isCloud ? .orange : .green)

                            if router.preferredProvider == provider {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.Colors.accentBlue)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Transcription Provider")
        } footer: {
            Text("Smart mode uses on-device first, then cloud if confidence is low.")
        }
    }

    // MARK: - Accent Section

    private var accentSection: some View {
        Section {
            ForEach(AccentRegion.allCases) { accent in
                Button {
                    router.accentRegion = accent
                } label: {
                    HStack {
                        Text(accent.displayName)
                            .foregroundColor(.primary)

                        Spacer()

                        if router.accentRegion == accent {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Theme.Colors.accentBlue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Accent / Language")
        } footer: {
            Text("Select your accent for better transcription accuracy.")
        }
    }

    // MARK: - Fallback Section

    private var fallbackSection: some View {
        Section {
            Toggle("Enable Cloud Fallback", isOn: $router.cloudFallbackEnabled)

            if router.cloudFallbackEnabled {
                Picker("Fallback Provider", selection: $router.fallbackProvider) {
                    Text("Deepgram (Best Accuracy)").tag(TranscriptionProvider.deepgram)
                    Text("AssemblyAI (Budget)").tag(TranscriptionProvider.assemblyai)
                }
            }
        } header: {
            Text("Cloud Fallback")
        } footer: {
            Text("When on-device confidence is below 80%, automatically try cloud transcription for better results.")
        }
    }

    // MARK: - Dictionary Section

    private var dictionarySection: some View {
        Section {
            if dictionary.corrections.isEmpty {
                Text("No corrections added yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(Array(dictionary.corrections.keys.sorted()), id: \.self) { wrong in
                    if let correct = dictionary.corrections[wrong] {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(wrong)
                                    .strikethrough()
                                    .foregroundColor(.secondary)
                                Text(correct)
                                    .fontWeight(.medium)
                            }

                            Spacer()
                        }
                    }
                }
                .onDelete { indexSet in
                    let keys = Array(dictionary.corrections.keys.sorted())
                    for index in indexSet {
                        dictionary.removeCorrection(wrong: keys[index])
                    }
                }
            }

            Button {
                showingAddCorrection = true
            } label: {
                Label("Add Correction", systemImage: "plus.circle")
            }
        } header: {
            Text("Personal Dictionary")
        } footer: {
            Text("Add corrections for phrases that are consistently misheard.")
        }
    }

    // MARK: - Custom Terms Section

    private var customTermsSection: some View {
        Section {
            if dictionary.customTerms.isEmpty {
                Text("No custom terms added yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(dictionary.customTerms, id: \.self) { term in
                    Text(term)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        dictionary.removeCustomTerm(dictionary.customTerms[index])
                    }
                }
            }

            Button {
                showingAddTerm = true
            } label: {
                Label("Add Custom Term", systemImage: "plus.circle")
            }
        } header: {
            Text("Custom Terms")
        } footer: {
            Text("Add exercise names or terms specific to your workouts to improve recognition.")
        }
    }

    // MARK: - Add Correction Sheet

    private var addCorrectionSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Wrong phrase", text: $newWrongPhrase)
                        .textInputAutocapitalization(.never)

                    TextField("Correct phrase", text: $newCorrectPhrase)
                } header: {
                    Text("Add Correction")
                } footer: {
                    Text("When the wrong phrase is detected, it will be replaced with the correct phrase.")
                }
            }
            .navigationTitle("Add Correction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAddCorrection = false
                        newWrongPhrase = ""
                        newCorrectPhrase = ""
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        dictionary.addCorrection(wrong: newWrongPhrase, correct: newCorrectPhrase)
                        showingAddCorrection = false
                        newWrongPhrase = ""
                        newCorrectPhrase = ""
                    }
                    .disabled(newWrongPhrase.isEmpty || newCorrectPhrase.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Add Term Sheet

    private var addTermSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Custom term", text: $newCustomTerm)
                } header: {
                    Text("Add Custom Term")
                } footer: {
                    Text("This term will be prioritized during transcription.")
                }
            }
            .navigationTitle("Add Term")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAddTerm = false
                        newCustomTerm = ""
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        dictionary.addCustomTerm(newCustomTerm)
                        showingAddTerm = false
                        newCustomTerm = ""
                    }
                    .disabled(newCustomTerm.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VoiceTranscriptionSettingsView()
    }
}
