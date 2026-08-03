//
//  BuilderV3TypePickerView.swift
//  AmakaFlow
//
//  AMA-2372 — Builder v3 type picker. Build from scratch must land here, not
//  on an empty Editor v2 — every tile seeds structure from
//  `BuilderV3TypeRegistry` (no seed API). "Start blank" stays pinned at the
//  bottom so skipping the picker is still one tap away.
//

import SwiftUI

struct BuilderV3TypePickerView: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (BuilderV3TypeSeed) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            DailyDriver.screenBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(BuilderV3Category.allCases, id: \.self) { category in
                            categorySection(category)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 100)
                }
                .scrollContentBackground(.hidden)
            }
            startBlankBar
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("builder_v3_type_picker_screen")
    }

    private var header: some View {
        HStack {
            Text("Build from scratch")
                .ddDisplayText(20, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("builder_v3_type_picker_close")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func categorySection(_ category: BuilderV3Category) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category.label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(BuilderV3TypeRegistry.seeds(for: category)) { seed in
                    BuilderV3TypeTile(seed: seed) { onSelect(seed) }
                }
            }
        }
    }

    private var startBlankBar: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [DailyDriver.screenBackground.opacity(0), DailyDriver.screenBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)
            Button {
                onSelect(BuilderV3TypeRegistry.blank)
            } label: {
                Text("Start blank")
                    .ddDisplayText(14, weight: .bold)
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DailyDriver.card2)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .background(DailyDriver.screenBackground)
            .accessibilityIdentifier("builder_v3_start_blank")
        }
    }
}

private struct BuilderV3TypeTile: View {
    let seed: BuilderV3TypeSeed
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(seed.label)
                    .ddDisplayText(14, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(seed.subtitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(seed.accessibilityId)
    }
}

#if DEBUG
#Preview {
    BuilderV3TypePickerView { _ in }
}
#endif
