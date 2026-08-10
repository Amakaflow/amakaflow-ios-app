//
//  StravaWorkoutStructureText.swift
//  AmakaFlow
//
//  AMA-2396: plain-text workout structure for Strava descriptions —
//  rounds, every step, and equipment emoji decoration.
//

import Foundation

// swiftlint:disable:next type_body_length
enum StravaWorkoutStructureText {
    /// Full Library workout → Strava structure body (no ownership signature).
    static func structureBody(from workout: Workout) -> String {
        var blocks: [String] = []
        for block in workout.blocks where !block.exercises.isEmpty {
            if let section = formatBlock(block) {
                blocks.append(section)
            }
        }
        if blocks.isEmpty {
            return workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return blocks.joined(separator: "\n\n")
    }

    /// Seed fill-in rows from the matched Library workout (timed steps keep M:SS notes).
    /// Multi-round circuits/EMOM/etc. seed `planned.sets` from `block.rounds` so
    /// verified “WHAT YOU DID” shows `6 × 3:00`, not `1 × 1 · 3:00`.
    static func fillInExercises(from workout: Workout) -> [ExerciseActual] {
        var rows: [ExerciseActual] = []
        var seen = Set<String>()
        for (blockIndex, block) in workout.blocks.enumerated() {
            for (exerciseIndex, exercise) in block.exercises.enumerated() {
                let base = slug(exercise.name)
                var key = "\(base)_\(blockIndex)_\(exerciseIndex)"
                if seen.contains(key) {
                    key = "\(key)_\(rows.count)"
                }
                seen.insert(key)
                let header = blockHeader(block)
                rows.append(
                    ExerciseActual(
                        id: key,
                        name: exercise.name,
                        planned: planned(from: exercise, in: block),
                        structureHeader: header.isEmpty ? nil : header,
                        structureBlockIndex: blockIndex
                    )
                )
            }
        }
        return Array(rows.prefix(24))
    }

    /// Heal drafts where a minute cap was stuffed into `rounds` → "CIRCUIT · 60 ROUNDS"
    /// / "60 × 3:00". Real multi-round circuits stay untouched (rounds &lt; 10, or non-clock notes).
    static func healMisencodedTimeCapRounds(
        exercises: [ExerciseActual]
    ) -> [ExerciseActual] {
        exercises.map { exercise in
            guard shouldHealMisencodedTimeCap(exercise) else { return exercise }
            let minutes = exercise.planned.sets
            let header = healedTimeCapHeader(
                from: exercise.structureHeader,
                minutes: minutes
            )
            let healedActualSets: Int = {
                if exercise.confirmation == nil { return 1 }
                if exercise.actualSets == exercise.planned.sets { return 1 }
                return exercise.actualSets
            }()
            return ExerciseActual(
                id: exercise.id,
                name: exercise.name,
                planned: ExerciseActualPlanned(
                    sets: 1,
                    reps: exercise.planned.reps,
                    weightKg: exercise.planned.weightKg,
                    note: exercise.planned.note
                ),
                confirmation: exercise.confirmation,
                actualSets: healedActualSets,
                actualReps: exercise.actualReps,
                actualWeightKg: exercise.actualWeightKg,
                structureHeader: header,
                structureBlockIndex: exercise.structureBlockIndex
            )
        }
    }

    static func healMisencodedTimeCapRounds(structureBody: String?) -> String? {
        guard let structureBody else { return nil }
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b(CIRCUIT|AMRAP|FOR TIME)\s*·\s*(\d+)\s*ROUNDS\b"#
        ) else {
            return structureBody
        }
        let structureNSString = structureBody as NSString
        let matches = regex.matches(in: structureBody, range: NSRange(location: 0, length: structureNSString.length))
        guard !matches.isEmpty else { return structureBody }
        var result = structureBody
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let kindRange = Range(match.range(at: 1), in: result),
                  let minutesRange = Range(match.range(at: 2), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let kind = String(result[kindRange]).uppercased()
            let minutes = String(result[minutesRange])
            let replacement: String = {
                if kind == "AMRAP" { return "AMRAP · \(minutes) MIN" }
                return "FOR TIME · \(minutes) MIN CAP"
            }()
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }

    /// Backfill structure bands from a stored Strava structure body when rows lack headers.
    static func stampingStructureHeaders(
        onto exercises: [ExerciseActual],
        from structureBody: String?
    ) -> [ExerciseActual] {
        guard let structureBody else { return exercises }
        let trimmedBody = structureBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return exercises }
        guard exercises.contains(where: { $0.structureHeader == nil }) else { return exercises }

        var result = exercises
        var header: String?
        var blockIndex = -1
        var nextIndex = 0

        for rawLine in trimmedBody.components(separatedBy: "\n") {
            let line = stripLeadingEmoji(rawLine)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if looksLikeStructureHeader(line) {
                blockIndex += 1
                header = line
                continue
            }
            guard nextIndex < result.count else { break }
            if result[nextIndex].structureHeader == nil {
                result[nextIndex].structureHeader = header
                result[nextIndex].structureBlockIndex = max(0, blockIndex)
            }
            nextIndex += 1
        }
        return result
    }

    /// Fallback when we only have fill-in rows (no stored structure body).
    static func structureBody(
        fromExercises exercises: [ExerciseActual],
        header: String? = nil
    ) -> String {
        var lines: [String] = []
        if let header {
            let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lines.append(trimmed) }
        }
        for exercise in exercises {
            let prescription: String = {
                if let note = exercise.planned.note, !note.isEmpty,
                   exercise.planned.weightKg == nil {
                    if exercise.planned.sets > 0 {
                        return "\(exercise.planned.sets) × \(note)"
                    }
                    return note
                }
                return exercise.planned.displayLine
            }()
            lines.append("\(emoji(forExerciseName: exercise.name)) \(exercise.name) — \(prescription)")
        }
        return lines.joined(separator: "\n")
    }

    static func emoji(forExerciseName name: String) -> String {
        let symbol = WorkoutSportHonesty.systemImage(forExerciseName: name)
        switch symbol {
        case "bicycle": return "🚴"
        case "figure.skiing.crosscountry": return "⛷️"
        case "figure.rower": return "🚣"
        case "figure.run": return "🏃"
        case "figure.elliptical": return "🔄"
        case "figure.stair.stepper": return "🪜"
        case "figure.jumprope": return "🪢"
        case "figure.pool.swim": return "🏊"
        case "figure.flexibility": return "🧘"
        default: return "🏋️"
        }
    }

    // MARK: - Private

    private static func shouldHealMisencodedTimeCap(_ exercise: ExerciseActual) -> Bool {
        let sets = exercise.planned.sets
        // Time caps are usually 10–90; genuine timed circuits are rarely 10+ full rounds.
        guard sets >= 10 else { return false }
        guard let note = exercise.planned.note, looksLikeClockNote(note) else { return false }
        guard let header = exercise.structureHeader?.uppercased(),
              let rounds = roundsCount(in: header),
              rounds == sets else {
            return false
        }
        if header.contains("TRI-SET") || header.contains("SUPERSET")
            || header.contains("EMOM") || header.contains("TABATA") {
            return false
        }
        return header.contains("ROUNDS")
    }

    private static func healedTimeCapHeader(from header: String?, minutes: Int) -> String {
        let upper = header?.uppercased() ?? ""
        if upper.contains("AMRAP") {
            return "AMRAP · \(minutes) MIN"
        }
        return "FOR TIME · \(minutes) MIN CAP"
    }

    private static func roundsCount(in header: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\s*ROUNDS"#),
              let match = regex.firstMatch(
                in: header,
                range: NSRange(header.startIndex..<header.endIndex, in: header)
              ),
              let range = Range(match.range(at: 1), in: header) else {
            return nil
        }
        return Int(header[range])
    }

    private static func looksLikeClockNote(_ note: String) -> Bool {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^\d+:\d{2}$"#, options: .regularExpression) != nil
    }

    private static func formatBlock(_ block: Block) -> String? {
        guard !block.exercises.isEmpty else { return nil }
        var lines: [String] = []
        let header = blockHeader(block)
        if !header.isEmpty { lines.append(header) }
        for exercise in block.exercises {
            let detail = PrescriptionFormatter.lineForDetailList(from: exercise)
            let prescription = detail.isEmpty ? "as built" : detail
            lines.append("\(emoji(forExerciseName: exercise.name)) \(exercise.name) — \(prescription)")
        }
        return lines.joined(separator: "\n")
    }

    private static func looksLikeStructureHeader(_ line: String) -> Bool {
        let upper = line.uppercased()
        if upper.contains(" — ") || upper.contains(" - ") { return false }
        let tokens = [
            "TRI-SET", "TRI SET", "SUPERSET", "CIRCUIT", "EMOM", "AMRAP",
            "TABATA", "ROUNDS", "FOR TIME", "WARM-UP", "WARM UP", "COOL-DOWN", "COOL DOWN"
        ]
        return tokens.contains { upper.contains($0) }
    }

    private static func stripLeadingEmoji(_ line: String) -> String {
        var scalars = Array(line.unicodeScalars)
        while let first = scalars.first {
            let isEmoji = first.properties.isEmojiPresentation
                || first.properties.isEmoji && first.value > 0xFF
            let isSpace = CharacterSet.whitespacesAndNewlines.contains(first)
            if isEmoji || isSpace {
                scalars.removeFirst()
                continue
            }
            break
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func blockHeader(_ block: Block) -> String { // swiftlint:disable:this cyclomatic_complexity
        let rounds = max(1, block.rounds)
        let structureName = block.structure.displayName.uppercased()
        if let label = block.label?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty,
           !isGenericBlockLabel(label) {
            if rounds > 1 {
                return "\(label.uppercased()) · \(rounds) ROUNDS"
            }
            return label.uppercased()
        }
        switch block.structure {
        case .circuit, .timedCircuit, .amrap, .emom, .tabata:
            if rounds > 1 {
                return "\(structureName) · \(rounds) ROUNDS"
            }
            return structureName
        case .superset:
            // 3+ stations read as a tri-set in Strava / verified structure text.
            let stations = block.exercises.count
            let kind = stations >= 3 ? "TRI-SET" : "SUPERSET"
            return rounds > 1 ? "\(kind) · \(rounds) ROUNDS" : kind
        case .straight:
            return rounds > 1 ? "\(rounds) ROUNDS" : ""
        }
    }

    private static func isGenericBlockLabel(_ label: String) -> Bool {
        let lowered = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "main", "main block", "block", "work", "workout",
            "circuit", "amrap", "emom", "tabata", "for time", "for-time",
            // Prefer stations-based TRI-SET / SUPERSET wording over a bare format label.
            "superset", "super set", "tri-set", "triset", "tri set"
        ].contains(lowered)
    }

    private static func planned(from exercise: Exercise, in block: Block) -> ExerciseActualPlanned { // swiftlint:disable:this cyclomatic_complexity
        let sets = plannedSets(for: exercise, in: block)
        if let seconds = exercise.durationSeconds, seconds > 0 {
            return ExerciseActualPlanned(
                sets: sets,
                reps: 1,
                note: formatClock(seconds)
            )
        }
        if let meters = exercise.distance, meters > 0 {
            let distanceText = meters >= 1000
                ? String(format: "%.1f km", meters / 1000)
                : "\(Int(meters.rounded())) m"
            return ExerciseActualPlanned(sets: sets, reps: 1, note: distanceText)
        }
        if let load = exercise.load {
            let reps = Int(exercise.reps ?? "") ?? 1
            let unit = load.unit.lowercased()
            let kilograms: Double? = (unit == "kg" || unit == "kilograms") ? load.value : nil
            let note: String? = kilograms == nil
                ? PrescriptionFormatter.lineForDetailList(from: exercise)
                : nil
            return ExerciseActualPlanned(
                sets: sets,
                reps: max(1, reps),
                weightKg: kilograms,
                note: note
            )
        }
        if let reps = Int(exercise.reps ?? ""), reps > 0 {
            return ExerciseActualPlanned(sets: sets, reps: reps)
        }
        let detail = PrescriptionFormatter.lineForDetailList(from: exercise)
        if !detail.isEmpty {
            return ExerciseActualPlanned(sets: sets, reps: 1, note: detail)
        }
        return ExerciseActualPlanned(sets: sets, reps: 1, note: "AS BUILT")
    }

    /// Circuit / EMOM rounds are the athlete-facing “sets” for each station.
    /// AMRAP / For-time caps are duration — never multiply stations by the minute cap.
    private static func plannedSets(for exercise: Exercise, in block: Block) -> Int {
        let rounds = max(1, block.rounds)
        let exerciseSets = max(1, exercise.sets ?? 1)
        switch block.structure {
        case .amrap:
            return exerciseSets
        case .circuit, .timedCircuit, .emom, .tabata, .superset:
            return rounds > 1 ? rounds : exerciseSets
        case .straight:
            // Legacy repeat→straight with rounds>1 and placeholder sets=1.
            if rounds > 1, exercise.sets == nil || exercise.sets == 1 {
                return rounds
            }
            return exerciseSets
        }
    }

    private static func formatClock(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let rem = seconds % 60
        return String(format: "%d:%02d", minutes, rem)
    }

    private static func slug(_ name: String) -> String {
        let raw = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return raw.isEmpty ? "move" : raw
    }
}
