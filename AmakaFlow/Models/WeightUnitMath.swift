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

    static func displayValue(kg: Double, unit: WeightUnit) -> Double {
        switch unit {
        case .kg: return kg
        case .lbs: return kg * poundsPerKilogram
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
        var values: [Double] = []
        var current = min
        // Guard float accumulation by indexing.
        let count = Int(((max - min) / step).rounded(.down)) + 1
        for i in 0..<count {
            current = min + (Double(i) * step)
            if current > max + 1e-9 { break }
            values.append(snap(current, step: step))
        }
        return values
    }

    static func nearestWheelValue(
        kg: Double?,
        unit: WeightUnit,
        fine: Bool
    ) -> Double {
        let display = displayValue(kg: kg ?? 0, unit: unit)
        let step = fine ? fineStep(for: unit) : coarseStep(for: unit)
        return snap(display, step: step)
    }

    static func formatWeight(kg: Double, unit: WeightUnit) -> String {
        let value = displayValue(kg: kg, unit: unit)
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
        for kg in values {
            let lb = displayValue(kg: kg, unit: .lbs)
            let back = kilograms(fromDisplay: lb, unit: .lbs)
            if abs(back - kg) > epsilon {
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
}
