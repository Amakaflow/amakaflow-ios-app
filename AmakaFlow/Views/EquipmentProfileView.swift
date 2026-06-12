//
//  EquipmentProfileView.swift
//  AmakaFlow
//
//  AMA-1995: Equipment Profile screen.
//

import SwiftUI

struct EquipmentProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EquipmentProfileViewModel
    @State private var didLoad = false

    init(viewModel: EquipmentProfileViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? EquipmentProfileViewModel())
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            Group {
                switch viewModel.state {
                case .loading:
                    loadingView
                case .content, .empty:
                    formView(showEmptyBanner: viewModel.state == .empty)
                case .error:
                    loadErrorView
                }
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowSaveBar {
                saveBar
            }
        }
        .overlay(alignment: .top) {
            if let error = viewModel.ctaError {
                ErrorToast(
                    actionTitle: viewModel.lastFailedAction == .load ? "Couldn't load equipment" : "Couldn't save equipment",
                    error: error,
                    onRetry: error.isRetryable ? { Task { await viewModel.retryLastAction() } } : nil,
                    onReport: { viewModel.reportError() },
                    onDismiss: { viewModel.dismissError() }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await viewModel.load()
        }
        .accessibilityIdentifier("equipment_profile_screen")
    }

    private var shouldShowSaveBar: Bool {
        switch viewModel.state {
        case .content, .empty:
            return true
        case .loading, .error:
            return false
        }
    }

    private var loadError: CTAError? {
        if case .error(let error) = viewModel.state {
            return error
        }
        return viewModel.ctaError
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.textPrimary)
            Text("Loading your equipment")
                .afMuted()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("equipment_profile_loading")
    }

    private var loadErrorView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            AFTopBar(
                title: "Equipment",
                subtitle: "Tell coach what you can train with.",
                backIdentifier: "equipment_profile_back",
                backAction: { dismiss() }
            ) {
                EmptyView()
            }

            Spacer()

            AFCard {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(Theme.Colors.accentRed)
                    Text("We couldn't load your equipment profile.")
                        .afH2()
                        .multilineTextAlignment(.center)
                    Text("Retry when you’re back online. Nothing has been changed.")
                        .afMuted()
                        .multilineTextAlignment(.center)
                    if loadError?.isRetryable == true {
                        Button {
                            Task { await viewModel.load() }
                        } label: {
                            Text("Retry")
                        }
                        .buttonStyle(AFPrimaryButtonStyle(size: .md))
                        .accessibilityIdentifier("equipment_profile_retry_load")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
        }
    }

    private func formView(showEmptyBanner: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                AFTopBar(
                    title: "Equipment",
                    subtitle: "Coach will only suggest workouts you can actually do.",
                    backIdentifier: "equipment_profile_back",
                    backAction: { dismiss() }
                ) {
                    AFChip(text: "Profile", outline: true)
                }
                .padding(.horizontal, -Theme.Spacing.lg)

                if showEmptyBanner {
                    emptyBanner
                }

                searchField

                VStack(spacing: Theme.Spacing.md) {
                    let categories = viewModel.filteredCategories()
                    if categories.isEmpty {
                        searchEmptyState
                    } else {
                        ForEach(categories) { category in
                            categoryCard(category)
                        }
                    }
                }

                trainingLocationCard
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, 120)
        }
    }

    private var emptyBanner: some View {
        AFCard {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundColor(Theme.Colors.readyHigh)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bodyweight basics are on")
                        .afH3()
                    Text("No saved equipment yet. We start with pull-up bar, rings, and paralettes so the form is honest instead of a blank broken state.")
                        .afMuted()
                }
            }
        }
        .accessibilityIdentifier("equipment_profile_empty_state")
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.Colors.textTertiary)
            TextField("Search equipment", text: $viewModel.searchText)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("equipment_profile_search")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 12)
        .background(Theme.Colors.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
    }

    private var searchEmptyState: some View {
        AFCard {
            VStack(spacing: Theme.Spacing.sm) {
                Text("No equipment found")
                    .afH3()
                Text("Try a different search term.")
                    .afMuted()
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("equipment_profile_search_empty")
    }

    private func categoryCard(_ category: EquipmentProfileViewModel.Category) -> some View {
        AFCard(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        viewModel.toggleCategory(category)
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.title)
                                .afH2()
                            Text(category.subtitle)
                                .afMuted()
                        }
                        Spacer()
                        Text("\(selectedCount(in: category))")
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.Colors.chipBackground)
                            .clipShape(Capsule())
                        Image(systemName: viewModel.isCollapsed(category) ? "chevron.down" : "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .padding(Theme.Spacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("equipment_category_\(category.id)")

                if !viewModel.isCollapsed(category) {
                    Divider().background(Theme.Colors.borderLight)
                    VStack(spacing: 0) {
                        ForEach(category.items) { item in
                            equipmentRow(item: item, category: category)
                            if item.id != category.items.last?.id {
                                Divider().padding(.leading, Theme.Spacing.md)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func equipmentRow(
        item: EquipmentProfileViewModel.EquipmentItem,
        category: EquipmentProfileViewModel.Category
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                viewModel.toggleItem(item, in: category)
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    checkbox(isOn: viewModel.isSelected(item, in: category))
                    Text(item.label)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("equipment_item_\(category.id)_\(item.id)")
            .accessibilityValue(viewModel.isSelected(item, in: category) ? "Selected" : "Not selected")

            if category.id == "strength", item.id == "dumbbells", viewModel.isSelected(item, in: category) {
                dumbbellSlider
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.md)
                    .transition(.opacity)
            }
        }
    }

    private func checkbox(isOn: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isOn ? Theme.Colors.primary : Color.clear)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isOn ? Theme.Colors.primary : Theme.Colors.borderMedium, lineWidth: 1.2)
                )
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.Colors.primaryForeground)
            }
        }
    }

    private var dumbbellSlider: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Dumbbell range")
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text("Up to \(viewModel.dumbbellRangeKg) kg")
                    .font(Theme.Typography.mono)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { Double(viewModel.dumbbellRangeKg) },
                    set: { viewModel.setDumbbellRangeKg(Int($0.rounded())) }
                ),
                in: 5...100,
                step: 1
            )
            .tint(Theme.Colors.readyHigh)
            .accessibilityIdentifier("equipment_dumbbell_range_slider")
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.backgroundSubtle)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
    }

    private var trainingLocationCard: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    AFLabel(text: "Where do you train?")
                    Text("Pick one default location for this equipment set.")
                        .afMuted()
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                    ForEach(EquipmentProfileViewModel.TrainingLocation.allCases) { location in
                        Button {
                            viewModel.selectLocation(location)
                        } label: {
                            Text(location.label)
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(viewModel.trainingLocation == location ? Theme.Colors.primaryForeground : Theme.Colors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(viewModel.trainingLocation == location ? Theme.Colors.primary : Theme.Colors.chipBackground)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("equipment_location_\(location.rawValue)")
                        .accessibilityAddTraits(viewModel.trainingLocation == location ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Divider().background(Theme.Colors.borderLight)
            Button {
                Task { await viewModel.save() }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if viewModel.isSaving {
                        ProgressView()
                            .tint(Theme.Colors.primaryForeground)
                    }
                    Text(viewModel.isSaving ? "Saving…" : "Save equipment")
                }
            }
            .buttonStyle(AFPrimaryButtonStyle(size: .lg))
            .disabled(!viewModel.saveEnabled)
            .accessibilityIdentifier(viewModel.saveAccessibilityIdentifier)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)
            .padding(.top, Theme.Spacing.sm)
        }
        .background(Theme.Colors.background)
    }

    private func selectedCount(in category: EquipmentProfileViewModel.Category) -> Int {
        category.items.filter { viewModel.isSelected($0, in: category) }.count
    }
}

#Preview("Equipment Profile") {
    NavigationStack {
        EquipmentProfileView(viewModel: EquipmentProfileViewModel(apiService: FixtureAPIService()))
    }
    .preferredColorScheme(.dark)
}
