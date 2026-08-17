//
//  EditorV2NumberWheel.swift
//  AmakaFlow
//
//  AMA-2443 slice 5 — the logbook scroll-snap wheel, reused for editing numbers.
//

import SwiftUI

/// One wheel column: a snapping value picker with a mono caption beneath it.
///
/// `Picker(.wheel)` is the same control the logbook uses (`LogbookWheelSheet`),
/// including its own centred selection band, so the rig's highlight band is not
/// redrawn here.
struct EditorV2NumberWheel<Value: Hashable>: View {
    let label: String
    let values: [Value]
    let display: (Value) -> String
    let accessibilityIdentifier: String
    @Binding var selection: Value

    var body: some View {
        VStack(spacing: 5) {
            Picker(label, selection: $selection) {
                ForEach(values, id: \.self) { value in
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
