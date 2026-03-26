//
//  ShareCardGenerator.swift
//  AmakaFlow
//
//  Renders WorkoutShareCardView to UIImage/PNG for sharing.
//  Uses ImageRenderer (iOS 16+).
//  AMA-1284
//

import SwiftUI

@MainActor
class ShareCardGenerator {

    /// Render the share card to a UIImage at the given aspect ratio
    @available(iOS 16.0, *)
    static func render(data: WorkoutShareCardData, aspect: ShareCardAspect) -> UIImage? {
        let size = aspect.size
        let view = WorkoutShareCardView(data: data, aspect: aspect)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0 // Already at target resolution
        renderer.proposedSize = .init(width: size.width, height: size.height)

        return renderer.uiImage
    }

    /// Render and share via UIActivityViewController
    @available(iOS 16.0, *)
    static func shareCard(
        data: WorkoutShareCardData,
        aspect: ShareCardAspect,
        from viewController: UIViewController? = nil
    ) {
        guard let image = render(data: data, aspect: aspect) else { return }

        let text = "Just crushed \(data.workoutName)! \(data.formattedDuration) | \(data.exerciseCount) exercises"
        let items: [Any] = [image, text]

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)

        let presenter = viewController ?? topViewController()
        presenter?.present(activityVC, animated: true)
    }

    /// Find the top-most view controller for presentation
    private static func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              var top = window.rootViewController else { return nil }

        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
