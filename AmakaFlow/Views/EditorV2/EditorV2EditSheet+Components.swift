//
//  EditorV2EditSheet+Components.swift
//  AmakaFlow
//
//  AMA-2379 — reusable focused-editor view components.
//

import SwiftUI

struct EditorV2StepperCellConfiguration {
    let label: String
    let value: Int
    let min: Int
    let max: Int
    let step: Int
    let valueText: ((Int) -> String)?
    let accessibilityIdentifier: String

    init(
        label: String,
        value: Int,
        min: Int,
        max: Int,
        step: Int = 1,
        valueText: ((Int) -> String)? = nil,
        accessibilityIdentifier: String
    ) {
        self.label = label
        self.value = value
        self.min = min
        self.max = max
        self.step = step
        self.valueText = valueText
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

struct EditorV2EditSheetStepperCell: View {
    let configuration: EditorV2StepperCellConfiguration
    let onChange: (Int) -> Void

    var body: some View {
        EditorV2Stepper(
            label: configuration.label,
            value: configuration.value,
            min: configuration.min,
            max: configuration.max,
            step: configuration.step,
            valueText: configuration.valueText,
            onChange: onChange
        )
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72)
        .accessibilityIdentifier(configuration.accessibilityIdentifier)
    }
}
