//
//  KnowledgeLibraryView.swift
//  AmakaFlow
//
//  Knowledge card list view with search, filter chips, and navigation to detail.
//

import SwiftUI

struct KnowledgeLibraryView: View {
    private let service = KnowledgeService.shared
    @State private var searchText: String = ""
    @State private var selectedFilter: KnowledgeFilter = .all
    @State private var cards: [KnowledgeCard] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showingAddKnowledge: Bool = false

    enum KnowledgeFilter: String, CaseIterable {
        case all = "All"
        case articles = "Articles"
        case videos = "Videos"
        case notes = "Notes"
        case curated = "Curated"
    }

    var filteredCards: [KnowledgeCard] {
        switch selectedFilter {
        case .all:
            return cards
        case .articles:
            return cards.filter { $0.sourceType == "url" }
        case .videos:
            return cards.filter { $0.sourceType == "youtube" }
        case .notes:
            return cards.filter { $0.sourceType == "manual" }
        case .curated:
            return cards.filter { $0.visibility == "curated" }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    searchBar

                    // Filter chips
                    filterChips

                    // Content area
                    if isLoading {
                        Spacer()
                        ProgressView()
                            .tint(Theme.Colors.accentBlue)
                        Spacer()
                    } else if let error = errorMessage {
                        Spacer()
                        Text(error)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.lg)
                        Spacer()
                    } else if filteredCards.isEmpty {
                        Spacer()
                        emptyState
                        Spacer()
                    } else {
                        cardList
                    }
                }
            }
            .navigationTitle("My Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddKnowledge = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(Theme.Colors.accentBlue)
                    }
                    .accessibilityIdentifier("knowledge_add_button")
                }
            }
            .sheet(isPresented: $showingAddKnowledge) {
                AddKnowledgeView()
            }
            .task {
                await loadCards()
            }
        }
        .accessibilityIdentifier("knowledge_library_screen")
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.Colors.textTertiary)

            TextField("Search knowledge...", text: $searchText)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    Task { await performSearch() }
                }
                .accessibilityIdentifier("knowledge_search_field")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Task { await loadCards() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(KnowledgeFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        isSelected: selectedFilter == filter
                    ) {
                        selectedFilter = filter
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    // MARK: - Card List

    private var cardList: some View {
        List {
            ForEach(filteredCards) { card in
                NavigationLink(destination: KnowledgeCardDetailView(card: card)) {
                    KnowledgeCardRow(card: card)
                }
                .listRowBackground(Theme.Colors.surface)
                .listRowSeparatorTint(Theme.Colors.borderLight)
            }
        }
        .listStyle(.plain)
        .background(Theme.Colors.background)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("No knowledge cards yet")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Tap + to add articles, videos, or notes to your library.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
    }

    // MARK: - Data Loading

    private func loadCards() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await service.listCards()
            cards = response.items
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func performSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            await loadCards()
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await service.searchCards(query: query)
            cards = response.items
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - KnowledgeCardRow

private struct KnowledgeCardRow: View {
    let card: KnowledgeCard

    private var sourceIcon: String {
        switch card.sourceType {
        case "youtube": return "play.circle.fill"
        case "url": return "doc.richtext"
        case "manual": return "note.text"
        case "pdf": return "doc.fill"
        case "voice_note": return "mic.fill"
        case "chat_extract": return "bubble.left.fill"
        case "curated": return "star.fill"
        default: return "link"
        }
    }

    private var sourceIconColor: Color {
        switch card.sourceType {
        case "youtube": return Theme.Colors.accentRed
        case "url": return Theme.Colors.accentBlue
        case "manual": return Theme.Colors.accentGreen
        case "pdf": return Theme.Colors.accentOrange
        case "voice_note": return Theme.Colors.accentBlue
        case "chat_extract": return Theme.Colors.accentGreen
        case "curated": return Theme.Colors.accentOrange
        default: return Theme.Colors.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Source type icon
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                    .fill(sourceIconColor.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: sourceIcon)
                    .font(.system(size: 18))
                    .foregroundColor(sourceIconColor)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                // Title
                Text(card.title ?? "Untitled")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)

                // micro summary
                if let micro = card.microSummary, !micro.isEmpty {
                    Text(micro)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }

                // Tag chips (up to 3)
                if !card.tags.isEmpty {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(Array(card.tags.prefix(3)), id: \.self) { tag in
                            Text(tag)
                                .font(Theme.Typography.footnote)
                                .foregroundColor(Theme.Colors.accentBlue)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, 2)
                                .background(Theme.Colors.accentBlue.opacity(0.1))
                                .cornerRadius(Theme.CornerRadius.sm)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }
}

// MARK: - FilterChip

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.captionBold)
                .foregroundColor(isSelected ? .white : Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    isSelected
                        ? Theme.Colors.accentBlue
                        : Theme.Colors.surface
                )
                .cornerRadius(Theme.CornerRadius.xl)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.xl)
                        .stroke(
                            isSelected ? Theme.Colors.accentBlue : Theme.Colors.borderMedium,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Temporary stub — will be replaced in Task 7

private struct AddKnowledgeView: View {
    var body: some View { Text("Add Knowledge") }
}

// MARK: - Preview

#Preview {
    KnowledgeLibraryView()
        .preferredColorScheme(.dark)
}
