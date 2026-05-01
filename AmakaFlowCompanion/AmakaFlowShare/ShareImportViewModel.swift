//
//  ShareImportViewModel.swift
//  AmakaFlowShare
//
//  AMA-1642: state machine for the Share Extension import flow.
//
//  Originally `state` was an `@State` property on `ShareExtensionView`.
//  `ShareViewController` tried to drive it via
//  `hostingController?.rootView.state = .importing`, but
//  `UIHostingController.rootView` returns the SwiftUI view as a value, so
//  assigning to `@State` on that returned value silently drops the
//  mutation — the view never re-rendered into `.importing`, `.success`,
//  or `.error`. Lifting state into an `ObservableObject` with a
//  `@Published` property lets the UIKit controller mutate state and have
//  SwiftUI actually react.
//
//  Extracted into its own file (separately from ShareExtensionView) so
//  the test target can compile-and-link the production types directly
//  without dragging the entire SwiftUI view + PlatformDetector +
//  DetectedPlatform dependency tree into the test bundle.
//

import Combine
import Foundation

/// State for the share extension import flow.
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

/// View model that drives `ShareExtensionView`'s render state. The UIKit
/// container (`ShareViewController`) holds the instance, mutates
/// `state`, and SwiftUI re-renders via `@ObservedObject`.
@MainActor
final class ShareImportViewModel: ObservableObject {
    @Published var state: ShareImportState = .ready
}
