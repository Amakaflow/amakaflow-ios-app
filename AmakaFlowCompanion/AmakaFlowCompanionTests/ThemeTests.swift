//
//  ThemeTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1991: design-token + primitive foundation.
//

import SwiftUI
import Testing
import UIKit
@testable import AmakaFlowCompanion

@MainActor
struct ThemeTests {
    @Test func readinessThresholdsAndLabels() {
        #expect(Theme.Ready.label(for: 100) == "Ready")
        #expect(Theme.Ready.label(for: 70) == "Ready")
        #expect(Theme.Ready.label(for: 69) == "Moderate")
        #expect(Theme.Ready.label(for: 45) == "Moderate")
        #expect(Theme.Ready.label(for: 44) == "Recover")
        #expect(Theme.Ready.label(for: 0) == "Recover")

        #expect(Theme.Ready.level(for: 70) == .high)
        #expect(Theme.Ready.level(for: 45) == .moderate)
        #expect(Theme.Ready.level(for: 44) == .low)
    }

    @Test func readinessColorsUseLimeAmberCoralScale() {
        #expect(hexString(for: Theme.Ready.color(for: 70)) == "#7AB953")
        #expect(hexString(for: Theme.Ready.color(for: 45)) == "#E0B03C")
        #expect(hexString(for: Theme.Ready.color(for: 44)) == "#E95049")
    }

    @Test func dynamicColorsResolvePerTraitCollection() {
        #expect(hexString(for: Theme.Colors.background, style: .light) == "#FFFFFF")
        #expect(hexString(for: Theme.Colors.background, style: .dark) == "#0A0A0A")

        #expect(hexString(for: Theme.Colors.textPrimary, style: .light) == "#0A0A0A")
        #expect(hexString(for: Theme.Colors.textPrimary, style: .dark) == "#FAFAFA")

        #expect(hexString(for: Theme.Colors.inputBackground, style: .light) == "#F3F3F5")
        #expect(hexString(for: Theme.Colors.inputBackground, style: .dark) == "#1F1F1F")
    }

    @Test func geistFontsAreBundledAndLoadableByPostScriptName() {
        #expect(Theme.Fonts.areLoaded())

        for postScriptName in Theme.Fonts.allPostScriptNames {
            let font = UIFont(name: postScriptName, size: 13)
            #expect(font != nil, "Expected bundled font \(postScriptName) to load")
            #expect(font?.fontName == postScriptName)
        }

        #expect(Theme.Fonts.postScriptName(family: .geist, weight: .regular) == "Geist-Regular")
        #expect(Theme.Fonts.postScriptName(family: .geist, weight: .medium) == "Geist-Medium")
        #expect(Theme.Fonts.postScriptName(family: .geist, weight: .semibold) == "Geist-SemiBold")
        #expect(Theme.Fonts.postScriptName(family: .geist, weight: .bold) == "Geist-Bold")
        #expect(Theme.Fonts.postScriptName(family: .geistMono, weight: .semibold) == "GeistMono-SemiBold")
    }

    private func hexString(for color: Color, style: UIUserInterfaceStyle = .light) -> String {
        let traitCollection = UITraitCollection(userInterfaceStyle: style)
        let resolved = UIColor(color).resolvedColor(with: traitCollection)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }
}
