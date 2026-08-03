//
//  CreateFlowPresentation.swift
//  AmakaFlow
//
//  Routes CreateWorkoutSheet doors to import / add flows.
//

import SwiftUI

enum CreateFlowPresentation: Identifiable, Equatable {
    case createWithAI
    case socialImport(url: String?, platform: SocialImportPlatform?)
    case screenshot
    case knowledge
    case manualEditor

    var id: String {
        switch self {
        case .createWithAI:
            return "create-with-ai"
        case .socialImport(let url, let platform):
            return "social-\(platform?.rawValue ?? "any")-\(url ?? "")"
        case .screenshot:
            return "screenshot"
        case .knowledge:
            return "knowledge"
        case .manualEditor:
            return "manual-editor"
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

    @State private var speakUnavailableAlert = false

    func body(content: Content) -> some View {
        content
            .ddBottomSheet(isPresented: $showCreateSheet, detents: [.medium]) {
                CreateWorkoutSheet(onSelect: openDoor)
            }
            .alert("Voice import not available yet", isPresented: $speakUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Use Import from URL or Build from scratch for now.")
            }
            .fullScreenCover(item: $activeFlow) { flow in
                switch flow {
                case .createWithAI:
                    CreateWithAIPromptView(onSaved: onLibraryReload)
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
                case .manualEditor:
                    BuilderV3EntryView(onSaved: onLibraryReload)
                        .ddSuppressFloatingChrome()
                }
            }
    }

    private func openDoor(_ door: CreateWorkoutDoor) {
        switch door {
        case .createWithAI:
            activeFlow = .createWithAI
        case .importURL:
            activeFlow = .socialImport(url: nil, platform: nil)
        case .screenshot:
            activeFlow = .screenshot
        case .manual:
            activeFlow = .manualEditor
        case .speak:
            speakUnavailableAlert = true
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
