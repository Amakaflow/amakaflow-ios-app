//
//  ShareExtensionView.swift
//  AmakaFlowShare
//
//  SwiftUI mini preview UI for the share extension.
//  Shows platform detection, URL preview, and one-tap import button.
//  AMA-1257: iOS Share Extension — one-tap workout import from any app
//

import SwiftUI

/// State for the share extension import flow
enum ShareImportState: Equatable {
    case loading          // Extracting URL from shared content
    case ready            // URL extracted, waiting for user action
    case importing        // POST in flight
    case success(String)  // Import succeeded — shows workout title
    case error(String)    // Import failed — shows error message

    static func == (lhs: ShareImportState, rhs: ShareImportState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading), (.ready, .ready), (.importing, .importing):
            return true
        case (.success(let a), .success(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// View model that drives ShareExtensionView's render state.
///
/// AMA-1642: previously `state` was an `@State` property on `ShareExtensionView`.
/// `ShareViewController` tried to drive it via
/// `hostingController?.rootView.state = .importing`, but `UIHostingController.rootView`
/// returns the SwiftUI view as a value, so assigning to `@State` on that returned
/// value silently drops the mutation — the view never re-rendered into `.importing`,
/// `.success`, or `.error`. Lifting the state into an `ObservableObject` driven by
/// `@Published` lets the UIKit controller mutate state and have SwiftUI react.
@MainActor
final class ShareImportViewModel: ObservableObject {
    @Published var state: ShareImportState = .ready
}

/// The mini preview UI shown in the share sheet
struct ShareExtensionView: View {
    let urls: [String]
    let onImport: () -> Void
    let onCancel: () -> Void
    @ObservedObject var viewModel: ShareImportViewModel

    /// The primary URL to display
    private var primaryURL: String {
        urls.first ?? ""
    }

    /// Detected platform for the primary URL
    private var platform: DetectedPlatform {
        PlatformDetector.detect(from: primaryURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Header
            HStack {
                Button("Cancel") { onCancel() }
                    .foregroundColor(.secondary)
                Spacer()
                Text("Import Workout")
                    .font(.headline)
                Spacer()
                // Spacer for balance
                Text("Cancel").opacity(0) // invisible counterweight
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Platform card
            VStack(spacing: 12) {
                // Platform icon + name
                HStack(spacing: 12) {
                    Image(systemName: platform.iconSystemName)
                        .font(.title2)
                        .foregroundColor(Color(hex: platform.accentColorHex))
                        .frame(width: 40, height: 40)
                        .background(Color(hex: platform.accentColorHex).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(platform.name)
                            .font(.subheadline.weight(.semibold))
                        Text(primaryURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    Spacer()
                }

                // Bulk indicator
                if urls.count > 1 {
                    HStack {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                        Text("\(urls.count) URLs detected")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // State-dependent content
                switch viewModel.state {
                case .loading:
                    ProgressView("Extracting URL...")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                case .ready:
                    Button(action: onImport) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(urls.count > 1 ? "Import \(urls.count) Workouts" : "Import Workout")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                case .importing:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Importing...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                case .success(let title):
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(title)
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                case .error(let message):
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Import Failed")
                                .font(.subheadline.weight(.medium))
                        }
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Try Again") { onImport() }
                            .font(.subheadline.weight(.medium))
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(16)

            Spacer()
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Color hex initializer (self-contained for extension)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}
