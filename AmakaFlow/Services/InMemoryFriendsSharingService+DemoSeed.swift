//
//  InMemoryFriendsSharingService+DemoSeed.swift
//  AmakaFlow
//
//  AMA-2389: Demo directory / friendships / shares for local dogfood.
//

import Foundation

nonisolated enum InMemoryFriendsDemoSeed {
    struct Payload {
        let directory: [FriendProfile]
        let friendships: [Friendship]
        let shares: [WorkoutShare]
    }

    static func make(
        currentUserId: String,
        seedDemo: Bool
    ) -> Payload {
        // Release / seedDemo:false must not expose fictional searchable profiles.
        guard seedDemo else {
            return Payload(directory: [], friendships: [], shares: [])
        }
        let directory = demoDirectory()
        return Payload(
            directory: directory,
            friendships: demoFriendships(currentUserId: currentUserId, directory: directory),
            shares: demoShares(currentUserId: currentUserId, directory: directory)
        )
    }

    private static func demoDirectory() -> [FriendProfile] {
        [
            FriendProfile(
                id: "u-marcus",
                displayName: "Marcus O.",
                handle: "marcus_lifts",
                accentRaw: "blue"
            ),
            FriendProfile(
                id: "u-priya",
                displayName: "Priya S.",
                handle: "priya.runs",
                accentRaw: "purple"
            ),
            FriendProfile(
                id: "u-tomas",
                displayName: "Tomás R.",
                handle: "tomas_engine",
                accentRaw: "amber"
            ),
            FriendProfile(
                id: "u-jonas",
                displayName: "Jonas K.",
                handle: "jonas.k",
                accentRaw: "blue"
            ),
            FriendProfile(
                id: "u-sara",
                displayName: "Sara B.",
                handle: "sara.b",
                accentRaw: "amber"
            )
        ]
    }

    private static func demoFriendships(
        currentUserId: String,
        directory: [FriendProfile]
    ) -> [Friendship] {
        guard
            let marcus = directory.first(where: { $0.id == "u-marcus" }),
            let priya = directory.first(where: { $0.id == "u-priya" }),
            let tomas = directory.first(where: { $0.id == "u-tomas" }),
            let jonas = directory.first(where: { $0.id == "u-jonas" }),
            let sara = directory.first(where: { $0.id == "u-sara" })
        else { return [] }

        return [
            Friendship(
                id: "f-marcus",
                requesterId: currentUserId,
                addresseeId: marcus.id,
                status: .accepted,
                createdAt: Date().addingTimeInterval(-86400 * 14),
                peer: marcus,
                isOutgoing: true
            ),
            Friendship(
                id: "f-priya",
                requesterId: currentUserId,
                addresseeId: priya.id,
                status: .accepted,
                createdAt: Date().addingTimeInterval(-86400 * 3),
                peer: priya,
                isOutgoing: true
            ),
            Friendship(
                id: "f-tomas",
                requesterId: tomas.id,
                addresseeId: currentUserId,
                status: .accepted,
                createdAt: Date().addingTimeInterval(-86400 * 10),
                peer: tomas,
                isOutgoing: false
            ),
            Friendship(
                id: "f-jonas",
                requesterId: jonas.id,
                addresseeId: currentUserId,
                status: .pending,
                createdAt: Date().addingTimeInterval(-3600),
                peer: jonas,
                isOutgoing: false
            ),
            Friendship(
                id: "f-sara",
                requesterId: currentUserId,
                addresseeId: sara.id,
                status: .pending,
                createdAt: Date().addingTimeInterval(-7200),
                peer: sara,
                isOutgoing: true
            )
        ]
    }

    private static func demoShares(
        currentUserId: String,
        directory: [FriendProfile]
    ) -> [WorkoutShare] {
        guard
            let marcus = directory.first(where: { $0.id == "u-marcus" }),
            let tomas = directory.first(where: { $0.id == "u-tomas" })
        else { return [] }

        let posterior = WorkoutShareSnapshot(
            name: "Lower body — posterior",
            sport: "strength",
            source: "manual",
            sourceUrl: nil,
            description: nil,
            creatorName: marcus.displayName,
            intervals: [
                WorkoutSaveInterval(type: "reps", name: "RDL", sets: 3, reps: 5),
                WorkoutSaveInterval(type: "reps", name: "Hip thrust", sets: 3, reps: 8),
                WorkoutSaveInterval(type: "reps", name: "Hamstring curl", sets: 3, reps: 10)
            ],
            blocks: nil,
            lineageId: "src:demo-posterior"
        )
        let engine = WorkoutShareSnapshot(
            name: "Engine EMOM",
            sport: "conditioning",
            source: "instagram",
            sourceUrl: "https://www.instagram.com/reel/DMqEsenN6Dl/",
            description: nil,
            creatorName: tomas.displayName,
            intervals: [
                WorkoutSaveInterval(type: "time", name: "Bike", seconds: 40),
                WorkoutSaveInterval(type: "reps", name: "Burpee", sets: 1, reps: 8)
            ],
            blocks: nil,
            lineageId: "src:https://www.instagram.com/reel/dmqesenn6dl/"
        )

        // Matches fixture-hiit-001 lineage (`src:` + lowercased source_url) so
        // AF_USE_FIXTURES dogfood / Maestro can hit the amber dup card.
        let hiitDup = WorkoutShareSnapshot(
            name: "HIIT remixed",
            sport: "cardio",
            source: "instagram",
            sourceUrl: "https://www.instagram.com/amakaflow",
            description: nil,
            creatorName: marcus.displayName,
            intervals: [
                WorkoutSaveInterval(type: "reps", name: "Jumping Jacks", sets: 1, reps: 20)
            ],
            blocks: nil,
            lineageId: "src:https://www.instagram.com/amakaflow"
        )

        return [
            WorkoutShare(
                id: "share-marcus-1",
                fromUserId: marcus.id,
                toUserId: currentUserId,
                fromDisplayName: marcus.displayName,
                fromHandle: marcus.handle,
                snapshot: posterior,
                note: "the posterior day I promised",
                status: .sent,
                createdAt: Date().addingTimeInterval(-1800),
                savedWorkoutId: nil
            ),
            WorkoutShare(
                id: "share-tomas-1",
                fromUserId: tomas.id,
                toUserId: currentUserId,
                fromDisplayName: tomas.displayName,
                fromHandle: tomas.handle,
                snapshot: engine,
                note: nil,
                status: .sent,
                createdAt: Date().addingTimeInterval(-900),
                savedWorkoutId: nil
            ),
            WorkoutShare(
                id: "share-dup-hiit",
                fromUserId: marcus.id,
                toUserId: currentUserId,
                fromDisplayName: marcus.displayName,
                fromHandle: marcus.handle,
                snapshot: hiitDup,
                note: "same lineage as your HIIT fixture",
                status: .sent,
                // Older than the other demos so inbox "Look inside" index 0 is a clean save.
                createdAt: Date().addingTimeInterval(-2400),
                savedWorkoutId: nil
            )
        ]
    }
}
