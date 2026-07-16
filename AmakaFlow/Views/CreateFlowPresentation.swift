//
//  CreateFlowPresentation.swift
//  AmakaFlow
//
//  Routes CreateWorkoutSheet doors to import / add flows.
//

import SwiftUI

enum CreateFlowPresentation: Identifiable, Equatable {
    case socialImport(url: String?, platform: SocialImportPlatform?)
    case screenshot
    case knowledge

    var id: String {
        switch self {
        case .socialImport(let url, let platform):
            return "social-\(platform?.rawValue ?? "any")-\(url ?? "")"
        case .screenshot:
            return "screenshot"
        case .knowledge:
            return "knowledge"
        }
    }
}

extension Notification.Name {
    static let libraryContentDidChange = Notification.Name("libraryContentDidChange")
}

enum OpenCreateSheetKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openCreateSheet: () -> Void {
        get { self[OpenCreateSheetKey.self] }
        set { self[OpenCreateSheetKey.self] = newValue }
    }
}

struct CreateFlowSheetsModifier: ViewModifier {
    @Binding var showCreateSheet: Bool
    @Binding var activeFlow: CreateFlowPresentation?
    var onLibraryReload: () -> Void

    func body(content: Content) -> some View {
        content
            .ddBottomSheet(isPresented: $showCreateSheet, detents: [.medium]) {
                CreateWorkoutSheet { door in
                    switch door {
                    case .importURL:
                        activeFlow = .socialImport(url: nil, platform: nil)
                    case .screenshot:
                        activeFlow = .screenshot
                    case .speak, .manual:
                        break
                    }
                }
            }
            .fullScreenCover(item: $activeFlow) { flow in
                switch flow {
                case .socialImport(let url, let platform):
                    SocialImportFlowView(
                        mode: .url(platformHint: platform),
                        initialURL: url,
                        onSaved: onLibraryReload
                    )
                case .screenshot:
                    ImageImportView(onSaved: onLibraryReload)
                case .knowledge:
                    AddKnowledgeView(
                        onSocialURLDetected: { detected in
                            activeFlow = .socialImport(
                                url: SocialImportPlatform.normalizeForIngest(detected),
                                platform: SocialImportPlatform.detect(from: detected)
                            )
                        },
                        onSaved: onLibraryReload
                    )
                }
            }
    }
}

extension View {
    func createFlowSheets(
        showCreateSheet: Binding<Bool>,
        activeFlow: Binding<CreateFlowPresentation?>,
        onLibraryReload: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            CreateFlowSheetsModifier(
                showCreateSheet: showCreateSheet,
                activeFlow: activeFlow,
                onLibraryReload: onLibraryReload
            )
        )
    }
}
