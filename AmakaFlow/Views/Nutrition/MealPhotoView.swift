//
//  MealPhotoView.swift
//  AmakaFlow
//
//  Camera + photo library food analysis view (AMA-1294).
//  Captures or picks a photo, sends base64 to /nutrition/analyze-photo.
//

import SwiftUI
import PhotosUI

struct MealPhotoView: View {
    @ObservedObject var viewModel: FoodLoggingViewModel
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                // Image preview or prompt
                if let image = selectedImage {
                    imagePreview(image)
                } else {
                    capturePrompt
                }

                // Error
                if let error = viewModel.errorMessage, viewModel.selectedTab == .photo {
                    ErrorBanner(message: error)
                }

                // Results
                if !viewModel.photoItems.isEmpty {
                    resultsSection
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .sheet(isPresented: $showCamera) {
            CameraView(image: $selectedImage)
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(image: $selectedImage)
        }
        .onChange(of: selectedImage) { newImage in
            guard let newImage else { return }
            analyzeImage(newImage)
        }
    }

    // MARK: - Capture Prompt

    private var capturePrompt: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(Theme.Colors.accentBlue.opacity(0.5))

            Text("Take a photo of your meal")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            HStack(spacing: Theme.Spacing.md) {
                Button {
                    showCamera = true
                } label: {
                    Label("Camera", systemImage: "camera.fill")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.accentBlue)
                        .cornerRadius(12)
                }

                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.accentBlue)
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.surface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.Colors.accentBlue.opacity(0.3), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xl)
    }

    // MARK: - Image Preview

    private func imagePreview(_ image: UIImage) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 250)
                .cornerRadius(12)

            if viewModel.isLoading {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView()
                        .tint(Theme.Colors.accentBlue)
                    Text("Analyzing your meal...")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.sm)
            }

            Button("Take Another Photo") {
                selectedImage = nil
                viewModel.photoItems = []
                viewModel.photoTotals = nil
                viewModel.photoNotes = nil
                viewModel.errorMessage = nil
            }
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Colors.accentBlue)
        }
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let totals = viewModel.photoTotals {
                MacroTotalsBar(totals: totals)
            }

            ForEach(viewModel.photoItems) { item in
                FoodItemRow(item: item)
            }

            if let notes = viewModel.photoNotes {
                Text(notes)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .padding(Theme.Spacing.sm)
            }
        }
    }

    // MARK: - Analyze

    private func analyzeImage(_ image: UIImage) {
        guard let jpegData = image.jpegData(compressionQuality: 0.7) else {
            viewModel.errorMessage = "Could not process image."
            return
        }
        let base64 = jpegData.base64EncodedString()
        Task {
            await viewModel.analyzePhoto(imageBase64: base64)
        }
    }
}

// MARK: - Camera View (UIKit wrapper)

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Photo Picker (PHPicker wrapper)

struct PhotoPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView

        init(_ parent: PhotoPickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()

            guard let result = results.first else { return }

            if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                result.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.image = image as? UIImage
                    }
                }
            }
        }
    }
}
