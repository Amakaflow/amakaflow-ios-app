//
//  WeightUnitMath.swift
//  AmakaFlow
//
//  AMA-2426: Settings kg/lb conversion. Canonical storage is always kilograms.
//  kg→lb→kg uses inverse factors so the full wheel range round-trips with zero drift.
//

import Foundation

enum WeightUnitMath {
    /// Exact inverse of `poundsPerKilogram` — never redefine independently.
    static let kilogramsPerPound = 0.453_592_37
    static let poundsPerKilogram = 1.0 / kilogramsPerPound

    /// Coarse wheel steps (ticket): KG 2.5 / LB 5.
    static func coarseStep(for unit: WeightUnit) -> Double {
        switch unit {
        case .kg: return 2.5
        case .lbs: return 5.0
        }
    }

    /// Long-press finer steps: KG 1.25 / LB 2.5.
    static func fineStep(for unit: WeightUnit) -> Double {
        switch unit {
        case .kg: return 1.25
        case .lbs: return 2.5
        }
    }

    static func displayValue(kg kilograms: Double, unit: WeightUnit) -> Double {
        switch unit {
        case .kg: return kilograms
        case .lbs: return kilograms * poundsPerKilogram
        }
    }

    /// Inverse of `displayValue` — exact for the factor pair above.
    static func kilograms(fromDisplay value: Double, unit: WeightUnit) -> Double {
        switch unit {
        case .kg: return value
        case .lbs: return value * kilogramsPerPound
        }
    }

    static func snap(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    static func wheelValues(
        unit: WeightUnit,
        fine: Bool,
        min: Double = 0,
        max: Double = 400
    ) -> [Double] {
        let step = fine ? fineStep(for: unit) : coarseStep(for: unit)
        guard step > 0 else { return [0] }
        guard min <= max else { return [] }
        var values: [Double] = []
        // Guard float accumulation by indexing.
        let count = Int(((max - min) / step).rounded(.down)) + 1
        for index in 0..<count {
            let current = min + (Double(index) * step)
            if current > max + 1e-9 { break }
            values.append(snap(current, step: step))
        }
        return values
    }

    static func nearestWheelValue(
        kg kilograms: Double?,
        unit: WeightUnit,
        fine: Bool
    ) -> Double {
        let display = displayValue(kg: kilograms ?? 0, unit: unit)
        let step = fine ? fineStep(for: unit) : coarseStep(for: unit)
        return snap(display, step: step)
    }

    static func formatWeight(kg kilograms: Double, unit: WeightUnit) -> String {
        let value = displayValue(kg: kilograms, unit: unit)
        if abs(value - value.rounded()) < 1e-9 {
            return "\(Int(value.rounded()))"
        }
        // Keep one decimal for 2.5 / 1.25 style steps.
        let tenths = (value * 10).rounded() / 10
        if abs(tenths - tenths.rounded()) < 1e-9 {
            return String(format: "%.0f", tenths)
        }
        return String(format: "%.1f", tenths)
    }

    static func unitLabel(_ unit: WeightUnit) -> String {
        switch unit {
        case .kg: return "KG"
        case .lbs: return "LB"
        }
    }

    /// Named gate: every coarse KG wheel value survives kg→lb→kg with zero drift.
    static func kgLbKgRoundTripHolds(
        minKg: Double = 0,
        maxKg: Double = 300,
        epsilon: Double = 1e-9
    ) -> Bool {
        let values = wheelValues(unit: .kg, fine: false, min: minKg, max: maxKg)
        for valueKg in values {
            let pounds = displayValue(kg: valueKg, unit: .lbs)
            let back = kilograms(fromDisplay: pounds, unit: .lbs)
            if abs(back - valueKg) > epsilon {
                return false
            }
        }
        return true
    }
}

extension WeightUnit {
    var logbookCoarseStep: Double { WeightUnitMath.coarseStep(for: self) }
    var logbookFineStep: Double { WeightUnitMath.fineStep(for: self) }
    var logbookLabel: String { WeightUnitMath.unitLabel(self) }

    /// Settings preference — canonical storage stays kilograms.
    ///
    /// AMA-2462: the fallback MUST match `EditProfileView`'s
    /// `@AppStorage(...) weightUnit: WeightUnit = .lbs`. `@AppStorage` writes
    /// nothing until the picker is touched, so a different default here means
    /// Profile displays "lbs" while the logbook renders kilograms — the screen
    /// lying about its own setting.
    static var stored: WeightUnit {
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.userWeightUnit.rawValue),
           let parsed = WeightUnit(rawValue: raw) {
            return parsed
        }
        return .lbs
    }
}

extension DistanceUnit {
    /// Settings preference — canonical storage stays metres.
    ///
    /// AMA-2462: matches `EditProfileView`'s `distanceUnit: DistanceUnit = .mi`
    /// for the same reason as `WeightUnit.stored`. Before this, nothing in the
    /// app read `user.distanceUnit` at all — choosing miles changed nothing.
    static var stored: DistanceUnit {
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.userDistanceUnit.rawValue),
           let parsed = DistanceUnit(rawValue: raw) {
            return parsed
        }
        return .mi
    }
}
