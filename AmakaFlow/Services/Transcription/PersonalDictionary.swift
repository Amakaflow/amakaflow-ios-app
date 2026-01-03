//
//  PersonalDictionary.swift
//  AmakaFlow
//
//  User's personal vocabulary corrections and custom terms (AMA-229)
//

import Foundation
import Combine

/// Manages user-specific vocabulary corrections and custom terms
/// Corrections are applied post-transcription to fix common misrecognitions
@MainActor
final class PersonalDictionary: ObservableObject {
    // MARK: - Singleton

    static let shared = PersonalDictionary()

    // MARK: - Published Properties

    /// Correction mappings: wrong phrase → correct phrase
    @Published private(set) var corrections: [String: String] = [:]

    /// Custom terms to boost in transcription
    @Published private(set) var customTerms: [String] = []

    /// When corrections were last synced with backend
    @Published private(set) var lastSyncDate: Date?

    /// Whether a sync is in progress
    @Published private(set) var isSyncing = false

    // MARK: - Properties

    private let storageKey = "personal_dictionary"
    private let apiService = APIService.shared

    // MARK: - Initialization

    private init() {
        loadFromStorage()
    }

    // MARK: - Correction Management

    /// Add a new correction mapping
    /// - Parameters:
    ///   - wrong: The incorrectly transcribed phrase
    ///   - correct: The correct phrase it should be
    func addCorrection(wrong: String, correct: String) {
        let normalizedWrong = wrong.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCorrect = correct.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedWrong.isEmpty, !normalizedCorrect.isEmpty else { return }

        corrections[normalizedWrong] = normalizedCorrect
        saveToStorage()

        // Trigger background sync
        Task {
            await syncWithBackend()
        }
    }

    /// Remove a correction
    func removeCorrection(wrong: String) {
        let normalized = wrong.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        corrections.removeValue(forKey: normalized)
        saveToStorage()

        Task {
            await syncWithBackend()
        }
    }

    /// Add a custom term to boost in transcription
    func addCustomTerm(_ term: String) {
        let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !customTerms.contains(normalized) else { return }

        customTerms.append(normalized)
        saveToStorage()

        Task {
            await syncWithBackend()
        }
    }

    /// Remove a custom term
    func removeCustomTerm(_ term: String) {
        customTerms.removeAll { $0 == term }
        saveToStorage()

        Task {
            await syncWithBackend()
        }
    }

    // MARK: - Apply Corrections

    /// Apply all corrections to transcribed text
    /// - Parameter text: Original transcription
    /// - Returns: Text with corrections applied
    func applyCorrections(to text: String) -> String {
        var result = text

        // Sort corrections by length (longest first) to handle overlapping phrases
        let sortedCorrections = corrections.sorted { $0.key.count > $1.key.count }

        for (wrong, correct) in sortedCorrections {
            // Case-insensitive replacement while preserving original case pattern
            result = result.replacingOccurrences(
                of: wrong,
                with: correct,
                options: .caseInsensitive
            )
        }

        return result
    }

    // MARK: - Persistence

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(StoredDictionary.self, from: data) else {
            return
        }

        corrections = stored.corrections
        customTerms = stored.customTerms
        lastSyncDate = stored.lastSyncDate

        print("[PersonalDictionary] Loaded \(corrections.count) corrections and \(customTerms.count) custom terms")
    }

    private func saveToStorage() {
        let stored = StoredDictionary(
            corrections: corrections,
            customTerms: customTerms,
            lastSyncDate: lastSyncDate
        )

        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - Backend Sync

    /// Sync dictionary with backend for cross-device consistency
    func syncWithBackend() async {
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let response = try await apiService.syncPersonalDictionary(
                corrections: corrections,
                customTerms: customTerms
            )

            // Merge with server data (server wins for conflicts)
            for (wrong, correct) in response.corrections {
                corrections[wrong] = correct
            }

            for term in response.customTerms where !customTerms.contains(term) {
                customTerms.append(term)
            }

            lastSyncDate = Date()
            saveToStorage()

            print("[PersonalDictionary] Synced with backend - \(corrections.count) corrections, \(customTerms.count) terms")

        } catch {
            // Sync failures are non-fatal - local data is still usable
            print("[PersonalDictionary] Sync failed: \(error.localizedDescription)")
        }
    }

    /// Fetch latest dictionary from backend
    func fetchFromBackend() async {
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let response = try await apiService.fetchPersonalDictionary()

            corrections = response.corrections
            customTerms = response.customTerms
            lastSyncDate = Date()
            saveToStorage()

            print("[PersonalDictionary] Fetched from backend - \(corrections.count) corrections, \(customTerms.count) terms")

        } catch {
            print("[PersonalDictionary] Fetch failed: \(error.localizedDescription)")
        }
    }

    /// Clear all local data
    func clearAll() {
        corrections = [:]
        customTerms = []
        lastSyncDate = nil
        saveToStorage()
    }
}

// MARK: - Storage Models

private struct StoredDictionary: Codable {
    let corrections: [String: String]
    let customTerms: [String]
    let lastSyncDate: Date?
}

// MARK: - Common Corrections

extension PersonalDictionary {
    /// Add common fitness term corrections that are frequently misheard
    func addDefaultCorrections() {
        let defaults: [String: String] = [
            // Common misrecognitions
            "hip thrust": "hip thrusts",
            "dead lift": "deadlift",
            "dead lifts": "deadlifts",
            "bench presses": "bench press",
            "pull up": "pull-up",
            "pushup": "push-up",
            "pushups": "push-ups",
            "set up": "setup",

            // Acronyms often misheard
            "h i i t": "HIIT",
            "high intensity interval training": "HIIT",
            "a m rap": "AMRAP",
            "e mom": "EMOM",
            "are p e": "RPE",

            // Numbers as words
            "one rep": "1 rep",
            "two reps": "2 reps",
            "three reps": "3 reps",
            "four reps": "4 reps",
            "five reps": "5 reps",
            "ten reps": "10 reps",
            "twelve reps": "12 reps",
            "fifteen reps": "15 reps"
        ]

        for (wrong, correct) in defaults {
            if corrections[wrong] == nil {
                corrections[wrong] = correct
            }
        }

        saveToStorage()
    }
}
