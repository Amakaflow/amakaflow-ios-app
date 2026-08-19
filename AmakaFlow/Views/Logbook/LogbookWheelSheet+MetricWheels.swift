//
//  LogbookWheelSheet+MetricWheels.swift
//  AmakaFlow
//
//  AMA-2462 — time / metres / calories wheels for machine stations. Split from
//  LogbookWheelSheet.swift, which the distance wheel pushed past the SwiftLint
//  type_body_length limit.
//

import SwiftUI

extension LogbookWheelSheet {
    var durationValues: [Int] { Array(stride(from: 0, through: 60 * 60, by: 5)) }
    var distanceValues: [Int] { Array(stride(from: 0, through: 21_000, by: 50)) }
    /// Coarse calorie steps — same remount cost discipline as duration.
    var calorieValues: [Int] { Array(stride(from: 0, through: 2000, by: 5)) }

    func durationWheel(selection: Binding<Int>) -> some View {
        Picker(LogbookCopy.columnTime, selection: selection) {
            ForEach(durationValues, id: \.self) { value in
                Text(value == 0 ? "—" : LogbookMetricFormat.duration(value))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(DailyDriver.foreground)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("af_logbook_duration_wheel")
    }

    func distanceWheel(selection: Binding<Int>) -> some View {
        Picker(LogbookCopy.columnDistanceShort, selection: selection) {
            ForEach(distanceValues, id: \.self) { value in
                Text(value == 0 ? "—" : "\(value)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(DailyDriver.foreground)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("af_logbook_distance_wheel")
    }

    func calorieWheel(selection: Binding<Int>) -> some View {
        Picker(LogbookCopy.columnCal, selection: selection) {
            ForEach(calorieValues, id: \.self) { value in
                Text(value == 0 ? "—" : "\(value)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(DailyDriver.foreground)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("af_logbook_calorie_wheel")
    }
}
