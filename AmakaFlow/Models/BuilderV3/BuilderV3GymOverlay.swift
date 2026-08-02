//
//  BuilderV3GymOverlay.swift
//  AmakaFlow
//
//  AMA-2372 — "NOT IN YOUR GYM" marking (never hiding) from the coaching
//  profile equipment inventory. When the profile can't be loaded, treat the
//  user as having no profile — never mark anything as missing.
//

import Foundation

/// Pure overlay logic — kept free of `Components.Schemas` decoding so it can
/// be unit tested against plain `[String: Bool]` maps mirroring
/// `EquipmentInventory`'s generated shape.
enum BuilderV3GymOverlay {
    /// Flatten an equipment inventory's category maps into the set of keys the
    /// user has marked available. Bodyweight defaults to always-available even
    /// when the map is missing a key (mirrors `EquipmentProfileViewModel`'s
    /// `defaultInventory` bodyweight-on convention).
    static func availableEquipmentKeys(
        bodyweight: [String: Bool]?,
        cardio: [String: Bool]?,
        strength: [String: Bool]?,
        mobility: [String: Bool]?
    ) -> Set<String> {
        var keys = Set<String>()
        for map in [bodyweight, cardio, strength, mobility] {
            guard let map else { continue }
            for (key, value) in map where value {
                keys.insert(key)
            }
        }
        return keys
    }

    /// `nil` availableKeys ⇒ no profile loaded (or it failed to load) ⇒ never mark
    /// anything missing. Bodyweight (`equipmentKey == nil`) is always available.
    static func isInGym(equipmentKey: String?, availableKeys: Set<String>?) -> Bool {
        guard let equipmentKey else { return true }
        guard let availableKeys else { return true }
        return availableKeys.contains(equipmentKey)
    }
}
