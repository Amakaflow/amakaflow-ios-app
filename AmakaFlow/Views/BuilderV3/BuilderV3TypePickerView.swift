//
//  BuilderV3TypePickerView.swift
//  AmakaFlow
//
//  AMA-2372 — Builder v3 type picker (mockup: "What are you building?").
//  Search filters local seeds; category accents + icons match the design
//  handoff. "Start blank" stays pinned so the old door survives.
//

import SwiftUI

struct BuilderV3TypePickerView: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (BuilderV3TypeSeed) -> Void

    @State private var query = ""

    private var filteredSeeds: [BuilderV3TypeSeed] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return BuilderV3TypeRegistry.all }
        return BuilderV3TypeRegistry.all.filter {
            $0.label.localizedCaseInsensitiveContains(trimmed)
                || $0.subtitle.localizedCaseInsensitiveContains(trimmed)
                || $0.category.label.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var visibleCategories: [BuilderV3Category] {
        BuilderV3Category.allCases.filter { category in
            filteredSeeds.contains { $0.category == category }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DailyDriver.screenBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                searchField
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(visibleCategories, id: \.self) { category in
                            categorySection(category)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 110)
                }
                .scrollContentBackground(.hidden)
            }
            startBlankBar
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("builder_v3_type_picker_screen")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What are you building?")
                    .ddDisplayText(22, weight: .heavy)
                    .foregroundColor(DailyDriver.foreground)
                Text("Pick a shape and we set the structure — or start blank and let it emerge.")
                    .font(.system(size: 12.5))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
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

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundDim)
            TextField("Search — 'supersets', 'emom', 'tempo'..", text: $query)
                .ddDisplayText(13.5, weight: .medium)
                .foregroundColor(DailyDriver.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("builder_v3_type_search")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DailyDriver.card2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func categorySection(_ category: BuilderV3Category) -> some View {
        let accent = Color(hex: category.accentHex)
        let seeds = filteredSeeds.filter { $0.category == category }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                Text(category.label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
            }
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(seeds) { seed in
                    BuilderV3TypeTile(seed: seed, accent: accent) { onSelect(seed) }
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
                Text("Start blank — structure comes later")
                    .ddDisplayText(13.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(DailyDriver.card2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(DailyDriver.borderStrong, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
    let accent: Color
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: seed.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accent)
                Text(seed.label)
                    .ddDisplayText(14, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(seed.subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accent.opacity(0.55), lineWidth: 1.25)
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
