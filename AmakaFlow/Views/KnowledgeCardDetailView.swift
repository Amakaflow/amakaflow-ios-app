//
//  KnowledgeCardDetailView.swift
//  AmakaFlow
//
//  Scrollable detail view for a single knowledge card.
//

import SwiftUI

struct KnowledgeCardDetailView: View {
    let card: KnowledgeCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {

                // Title
                Text(card.title ?? "Untitled")
                    .font(Theme.Typography.largeTitle)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // Source URL link
                if let urlString = card.sourceUrl, let url = URL(string: urlString) {
                    Link(destination: url) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "link")
                                .font(.system(size: 13))
                            Text(urlString)
                                .font(Theme.Typography.caption)
                                .lineLimit(1)
                        }
                        .foregroundColor(Theme.Colors.accentBlue)
                    }
                    .accessibilityIdentifier("knowledge_detail_source_url")
                }

                // Tag chips
                if !card.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(card.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(Theme.Typography.captionBold)
                                    .foregroundColor(Theme.Colors.accentBlue)
                                    .padding(.horizontal, Theme.Spacing.md)
                                    .padding(.vertical, Theme.Spacing.xs)
                                    .background(Theme.Colors.accentBlue.opacity(0.1))
                                    .cornerRadius(Theme.CornerRadius.xl)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.CornerRadius.xl)
                                            .stroke(Theme.Colors.accentBlue.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                    }
                }

                Divider()
                    .background(Theme.Colors.borderLight)

                // Summary section
                if let summary = card.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Summary")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text(summary)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("knowledge_detail_summary")
                }

                // Key takeaways section
                if !card.keyTakeaways.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Key Takeaways")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.textPrimary)

                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            ForEach(Array(card.keyTakeaways.enumerated()), id: \.offset) { _, takeaway in
                                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(Theme.Colors.accentGreen)
                                        .padding(.top, 1)

                                    Text(takeaway)
                                        .font(Theme.Typography.body)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("knowledge_detail_takeaways")
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("knowledge_card_detail_screen")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        KnowledgeCardDetailView(card: KnowledgeCard(
            id: "preview-1",
            title: "The Science of Periodization",
            summary: "Periodization is a systematic approach to training that involves progressive cycling of various aspects of a training program during a specific period.",
            microSummary: "Structure training in cycles to peak performance.",
            keyTakeaways: [
                "Progressive overload is essential for continued adaptation.",
                "Deload weeks prevent overtraining and aid recovery.",
                "Macrocycles, mesocycles, and microcycles provide structure."
            ],
            sourceType: "article",
            sourceUrl: "https://example.com/periodization",
            processingStatus: "complete",
            tags: ["training", "periodization", "strength"],
            createdAt: "2026-03-07T00:00:00Z"
        ))
    }
    .preferredColorScheme(.dark)
}
