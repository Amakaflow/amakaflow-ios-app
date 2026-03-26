//
//  ShareViewController.swift
//  AmakaFlowShare
//
//  Share Extension entry point — extracts URLs from shared content,
//  shows a mini preview with platform detection, and imports workouts.
//  AMA-1257: iOS Share Extension — one-tap workout import from any app
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

class ShareViewController: UIViewController {

    private var hostingController: UIHostingController<ShareExtensionView>?
    private var extractedURLs: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        extractURLsFromContext()
    }

    // MARK: - URL Extraction

    private func extractURLsFromContext() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish(success: false)
            return
        }

        let group = DispatchGroup()
        var foundURLs: [String] = []

        for item in items {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                // Try URL type first
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                        defer { group.leave() }
                        if let url = item as? URL {
                            foundURLs.append(url.absoluteString)
                        }
                    }
                }

                // Also try plain text — Instagram shares URLs embedded in text
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                        defer { group.leave() }
                        if let text = item as? String {
                            let urls = PlatformDetector.extractURLs(from: text)
                            foundURLs.append(contentsOf: urls)
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            // Deduplicate
            let unique = Array(NSOrderedSet(array: foundURLs)) as? [String] ?? foundURLs
            if unique.isEmpty {
                self.finish(success: false)
                return
            }
            self.extractedURLs = unique
            self.showShareUI(urls: unique)
        }
    }

    // MARK: - SwiftUI Hosting

    private func showShareUI(urls: [String]) {
        let shareView = ShareExtensionView(
            urls: urls,
            onImport: { [weak self] in self?.performImport() },
            onCancel: { [weak self] in self?.finish(success: false) }
        )

        let hosting = UIHostingController(rootView: shareView)
        hosting.view.backgroundColor = .clear
        self.hostingController = hosting

        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)

        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.55),
        ])

        hosting.didMove(toParent: self)
    }

    // MARK: - Import

    private func performImport() {
        guard !extractedURLs.isEmpty else { return }

        // Update UI state
        hostingController?.rootView.state = .importing

        // Import all URLs concurrently
        Task {
            var successCount = 0
            var lastTitle: String?
            var lastError: String?

            for urlString in extractedURLs {
                let platform = PlatformDetector.detect(from: urlString)
                do {
                    let response = try await URLImportService.shared.importURL(urlString, platform: platform)

                    // Save success result to shared container
                    let result = SharedContainerManager.ImportResult(
                        url: urlString,
                        platform: platform.name,
                        title: response.title,
                        workoutType: response.workoutType,
                        success: true,
                        errorMessage: nil,
                        timestamp: Date()
                    )
                    SharedContainerManager.saveImportResult(result)
                    successCount += 1
                    lastTitle = response.title
                } catch {
                    // Save error result to shared container
                    let result = SharedContainerManager.ImportResult(
                        url: urlString,
                        platform: platform.name,
                        title: nil,
                        workoutType: nil,
                        success: false,
                        errorMessage: error.localizedDescription,
                        timestamp: Date()
                    )
                    SharedContainerManager.saveImportResult(result)
                    lastError = error.localizedDescription
                }
            }

            await MainActor.run {
                if successCount == extractedURLs.count {
                    // All succeeded
                    let title = lastTitle ?? "Workout imported"
                    let displayTitle = extractedURLs.count > 1
                        ? "\(successCount) workouts imported"
                        : title
                    hostingController?.rootView.state = .success(displayTitle)

                    URLImportService.sendLocalNotification(
                        title: "Workout Imported",
                        body: displayTitle,
                        success: true
                    )

                    // Auto-dismiss after short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.finish(success: true)
                    }
                } else if successCount > 0 {
                    // Partial success
                    let msg = "\(successCount)/\(extractedURLs.count) imported"
                    hostingController?.rootView.state = .success(msg)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.finish(success: true)
                    }
                } else {
                    // All failed
                    hostingController?.rootView.state = .error(lastError ?? "Unknown error")
                }
            }
        }
    }

    // MARK: - Finish

    private func finish(success: Bool) {
        if success {
            extensionContext?.completeRequest(returningItems: [])
        } else {
            extensionContext?.cancelRequest(withError:
                NSError(domain: "com.amakaflow.share", code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Cancelled or failed"]))
        }
    }
}
