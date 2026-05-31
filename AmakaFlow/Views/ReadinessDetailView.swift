//
//  ReadinessDetailView.swift
//  AmakaFlow
//
//  AMA-2054: Readiness detail sheet with per-metric source picker.
//

import SwiftUI

struct ReadinessDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ReadinessDetailViewModel
    @State private var didLoad = false
    @State private var selectedMetric: String?

    init(viewModel: ReadinessDetailViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? ReadinessDetailViewModel())
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            Group {
                switch viewModel.state {
                case .loading:
                    loadingView
                case .content:
                    contentView
                case .empty:
                    emptyView
                case .error:
                    loadErrorView
                }
            }
        }
        .overlay(alignment: .top) {
            if let error = viewModel.ctaError {
                ErrorToast(
                    actionTitle: errorActionTitle,
                    error: error,
                    onRetry: error.isRetryable ? { Task { await viewModel.retryLastAction() } } : nil,
                    onReport: { viewModel.reportError() },
                    onDismiss: { viewModel.dismissError() }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { selectedMetric != nil },
                set: { if !$0 { selectedMetric = nil } }
            )
        ) {
            if let selectedMetric {
                ReadinessSourcePickerSheet(
                    metric: selectedMetric,
                    viewModel: viewModel,
                    onClose: { self.selectedMetric = nil }
                )
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await viewModel.load()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Colors.background)
        .accessibilityIdentifier("readiness_detail_sheet")
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.textPrimary)
            Text("Loading readiness")
                .afMuted()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("readiness_detail_loading")
    }

    private var contentView: some View {
        scrollContainer {
            metricsSection
            trendSection
            infoNote
        }
    }

    private var emptyView: some View {
        scrollContainer {
            AFCard {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "heart.text.square")
                        .font(Theme.Typography.largeTitle)
                        .foregroundColor(Theme.Colors.readyHigh)
                    Text("Connect a recovery device")
                        .afH2()
                    Text("Apple Health, Garmin, or manual entries can feed HRV, sleep, and resting heart rate when data is available.")
                        .afMuted()
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("readiness_detail_empty")
        }
    }

    private var loadErrorView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            topBar

            Spacer()

            AFCard {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.largeTitle)
                        .foregroundColor(Theme.Colors.accentRed)
                    Text("We couldn't load readiness.")
                        .afH2()
                        .multilineTextAlignment(.center)
                    Text("Retry when you’re back online. Source preferences stay unchanged.")
                        .afMuted()
                        .multilineTextAlignment(.center)
                    if loadError?.isRetryable == true {
                        Button {
                            Task { await viewModel.load() }
                        } label: {
                            Text("Retry")
                        }
                        .buttonStyle(AFPrimaryButtonStyle(size: .md))
                        .accessibilityIdentifier("readiness_detail_retry_load")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
        }
    }

    @ViewBuilder
    private func scrollContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                topBar
                    .padding(.horizontal, -Theme.Spacing.lg)

                content()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    private var topBar: some View {
        AFTopBar(
            title: "Readiness",
            subtitle: viewModel.headerSubtitle,
            backIdentifier: "readiness_detail_close",
            backAction: { dismiss() },
            right: { AFChip(text: "Sources", outline: true) }
        )
    }

    private var loadError: CTAError? {
        if case .error(let error) = viewModel.state {
            return error
        }
        return viewModel.ctaError
    }

    private var errorActionTitle: String {
        switch viewModel.lastFailedAction {
        case .load:
            return "Couldn't load readiness"
        case .setSource:
            return "Couldn't update source"
        case .none:
            return "Readiness action failed"
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            AFLabel(text: "Metrics")
                .accessibilityAddTraits(.isHeader)

            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(viewModel.metricRows) { row in
                    metricCard(row)
                }
            }
        }
    }

    private func metricCard(_ row: ReadinessDetailViewModel.MetricRow) -> some View {
        AFCard {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(row.label)
                        .afH3()
                    Text(row.valueText)
                        .font(Theme.Typography.title2)
                        .foregroundColor(row.hasValue ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    Text(row.sourceCaption)
                        .font(Theme.Typography.mono)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                Button {
                    selectedMetric = row.key
                } label: {
                    if row.isUpdating {
                        ProgressView()
                            .tint(Theme.Colors.textPrimary)
                    } else {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text("Change")
                            Image(systemName: "chevron.up.chevron.down")
                        }
                    }
                }
                .buttonStyle(AFGhostButtonStyle(size: .sm, isWide: false))
                .disabled(row.isUpdating)
                .accessibilityIdentifier("readiness_change_source_\(row.key)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readiness_metric_\(row.key)")
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            AFLabel(text: "HRV 7-day trend")
                .accessibilityAddTraits(.isHeader)

            AFCard {
                if viewModel.hasTrendData, let points = viewModel.trend?.points {
                    HRVSparkline(points: points)
                        .frame(height: Theme.Spacing.xl * 3)
                        .accessibilityIdentifier("readiness_hrv_trend")
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("No trend yet")
                            .afH3()
                        Text("HRV samples will appear here after your recovery source syncs multiple days.")
                            .afMuted()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("readiness_hrv_trend_empty")
                }
            }
        }
    }

    private var infoNote: some View {
        AFCard {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("Source choices only affect where each readiness metric comes from. Unsupported sources are shown but disabled until their integrations ship.")
                    .afMuted()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("readiness_sources_note")
    }
}

private struct ReadinessSourcePickerSheet: View {
    let metric: String
    @ObservedObject var viewModel: ReadinessDetailViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(ReadinessDetailViewModel.allSources) { source in
                        sourceRow(source)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.lg)
            }
        }
        .background(Theme.Colors.surface)
        .overlay(alignment: .top) {
            if let error = viewModel.ctaError, viewModel.lastFailedAction == .setSource(metric: metric) {
                ErrorToast(
                    actionTitle: "Couldn't update source",
                    error: error,
                    onRetry: error.isRetryable ? { Task { await viewModel.retryLastAction() } } : nil,
                    onReport: { viewModel.reportError() },
                    onDismiss: { viewModel.dismissError() }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Colors.surface)
        .accessibilityIdentifier("readiness_source_picker_\(metric)")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Choose source")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(ReadinessDetailViewModel.metricLabel(metric))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: Theme.Spacing.xl, height: Theme.Spacing.xl)
                    .background(Theme.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            }
            .accessibilityLabel("Close source picker")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.lg)
        .background(Theme.Colors.surface)
        .overlay(
            Rectangle()
                .fill(Theme.Colors.borderLight)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func sourceRow(_ source: ReadinessDetailViewModel.SourceOption) -> some View {
        let selected = viewModel.isSourceSelected(source.key, for: metric)
        return Button {
            guard source.enabled else { return }
            Task {
                await viewModel.setSource(metric: metric, source: source.key)
                if viewModel.lastFailedAction != .setSource(metric: metric) {
                    onClose()
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Typography.title2)
                    .foregroundColor(source.enabled ? Theme.Colors.readyHigh : Theme.Colors.textTertiary)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(source.label)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(source.enabled ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)

                        if selected {
                            AFChip(text: "Selected", outline: true)
                        }
                    }

                    Text(source.enabled ? "Available now" : "Coming soon")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                    .stroke(selected ? Theme.Colors.readyHigh : Theme.Colors.borderLight, lineWidth: 1)
            )
            .cornerRadius(Theme.CornerRadius.md)
            .opacity(source.enabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!source.enabled || viewModel.sourceUpdatesInFlight.contains(metric))
        .accessibilityLabel(source.enabled ? source.label : "\(source.label), coming soon")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("readiness_source_\(metric)_\(source.key)")
    }
}

private struct HRVSparkline: View {
    let points: [Components.Schemas.ReadinessTrendPoint]

    private var values: [Double] {
        points.compactMap(\.value)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                sparkPath(in: proxy.size)
                    .stroke(Theme.Colors.readyHigh, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    if let value = point.value {
                        Circle()
                            .fill(Theme.Colors.readyHigh)
                            .frame(width: Theme.Spacing.sm, height: Theme.Spacing.sm)
                            .position(position(for: value, index: index, size: proxy.size))
                    }
                }
            }
        }
    }

    private func sparkPath(in size: CGSize) -> Path {
        var path = Path()
        var segmentStarted = false

        for (index, point) in points.enumerated() {
            guard let value = point.value else {
                segmentStarted = false
                continue
            }
            let pointPosition = position(for: value, index: index, size: size)
            if segmentStarted {
                path.addLine(to: pointPosition)
            } else {
                path.move(to: pointPosition)
                segmentStarted = true
            }
        }

        return path
    }

    private func position(for value: Double, index: Int, size: CGSize) -> CGPoint {
        let minimum = values.min() ?? value
        let maximum = values.max() ?? value
        let range = max(maximum - minimum, 1)
        let xDivisor = max(points.count - 1, 1)
        let x = CGFloat(index) / CGFloat(xDivisor) * size.width
        let normalized = (value - minimum) / range
        let y = size.height - (CGFloat(normalized) * size.height)
        return CGPoint(x: x, y: y)
    }
}

#Preview("Readiness Detail") {
    ReadinessDetailView(viewModel: ReadinessDetailViewModel(apiService: MockAPIService()))
}
