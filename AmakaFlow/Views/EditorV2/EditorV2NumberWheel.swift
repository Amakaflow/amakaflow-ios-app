//
//  EditorV2NumberWheel.swift
//  AmakaFlow
//
//  AMA-2443 slice 5 — the logbook scroll-snap wheel, reused for editing numbers.
//

import SwiftUI

/// Grid values a wheel offers, always including whatever is currently selected.
///
/// `Picker` renders no selected row when the bound value is absent from its
/// options, and the first scroll then silently overwrites the saved value. A
/// saved workout is under no obligation to sit on our step grid — 47s of work,
/// 61 kg, 450 m — so the selected value joins the grid rather than being snapped
/// onto it. Snapping would need a write-back, and a write-back on open would
/// stamp user provenance onto an exercise nobody touched.
enum EditorV2WheelValues {
    static func offering<Value: Hashable & Comparable>(
        _ values: [Value],
        including selection: Value
    ) -> [Value] {
        guard !values.contains(selection) else { return values }
        var merged = values
        let insertion = merged.firstIndex { $0 > selection } ?? merged.endIndex
        merged.insert(selection, at: insertion)
        return merged
    }
}

/// One wheel column: a snapping value picker with a mono caption beneath it.
///
/// `Picker(.wheel)` is the same control the logbook uses (`LogbookWheelSheet`),
/// including its own centred selection band, so the rig's highlight band is not
/// redrawn here.
struct EditorV2NumberWheel<Value: Hashable & Comparable>: View {
    let label: String
    let values: [Value]
    let display: (Value) -> String
    let accessibilityIdentifier: String
    @Binding var selection: Value

    var body: some View {
        VStack(spacing: 5) {
            Picker(label, selection: $selection) {
                ForEach(EditorV2WheelValues.offering(values, including: selection), id: \.self) { value in
                    Text(display(value))
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundColor(DailyDriver.foreground)
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: 132)
            .clipped()
            .accessibilityIdentifier(accessibilityIdentifier)

            Text(label)
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
                .accessibilityHidden(true)
        }
    }
}

extension EditorV2NumberWheel where Value == Int {
    /// Integer wheel over a closed range with a fixed step.
    init(
        label: String,
        range: ClosedRange<Int>,
        step: Int = 1,
        accessibilityIdentifier: String,
        selection: Binding<Int>,
        display: @escaping (Int) -> String = { "\($0)" }
    ) {
        self.init(
            label: label,
            values: Array(stride(from: range.lowerBound, through: range.upperBound, by: step)),
            display: display,
            accessibilityIdentifier: accessibilityIdentifier,
            selection: selection
        )
    }
}
