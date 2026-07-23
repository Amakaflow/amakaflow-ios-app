import Foundation

extension DDWorkoutDisplayGrouping {
    /// Display-only: merge consecutive unlabeled straight-set singletons into one virtual Main.
    static func collapseStraightSetSingletons(_ blocks: [Block]) -> [Block] {
        var result: [Block] = []
        var pendingExercises: [Exercise] = []

        func flushPending() {
            guard !pendingExercises.isEmpty else { return }
            result.append(
                Block(
                    label: "Main",
                    structure: .straight,
                    rounds: 1,
                    exercises: pendingExercises
                )
            )
            pendingExercises = []
        }

        for block in blocks {
            if isCollapsibleSingleton(block) {
                pendingExercises.append(contentsOf: block.exercises)
            } else {
                flushPending()
                result.append(block)
            }
        }
        flushPending()
        return result
    }

    static func isCollapsibleSingleton(_ block: Block) -> Bool {
        block.structure == .straight
            && block.exercises.count == 1
            && isUnlabeledStraightSetContainer(block)
    }

    static func isUnlabeledStraightSetContainer(_ block: Block) -> Bool {
        guard let label = block.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
            return true
        }
        if label.caseInsensitiveCompare("Main") == .orderedSame { return true }
        return isGenericBlockLabel(label)
    }

    static func isStraightSetContainer(_ block: Block) -> Bool {
        block.structure == .straight
    }

    static func shouldSuppressTitle(for block: Block, allBlocks: [Block]) -> Bool {
        guard isStraightSetContainer(block), isUnlabeledStraightSetContainer(block) else { return false }
        let unlabeledContainers = allBlocks.filter {
            isStraightSetContainer($0) && isUnlabeledStraightSetContainer($0)
        }
        return unlabeledContainers.count == 1 && unlabeledContainers[0].id == block.id
    }

    static func isGenericBlockLabel(_ label: String) -> Bool {
        label.range(
            of: #"^(Main block|Block \d+|AMRAP)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}
