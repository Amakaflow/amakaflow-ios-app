//
//  ActualsSyncCounterBanner.swift
//  AmakaFlow
//
//  AMA-2387: Today backfill counter — real ingest only (ACTUALS.md §5).
//

import SwiftUI

struct ActualsSyncCounterBanner: View {
    let progress: ActualsSyncProgress

    var body: some View {
        Text(progress.displayString)
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundDim)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundColor(DailyDriver.borderStrong)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(progress.displayString)
            .accessibilityIdentifier(ActualsCopy.syncCounterAccessibilityID)
    }
}

#if DEBUG
#Preview("Sync counter") {
    ActualsSyncCounterBanner(
        progress: ActualsSyncProgress(ingested: 3, total: 12)
    )
    .padding()
    .background(DailyDriver.screenBackground)
}
#endif
