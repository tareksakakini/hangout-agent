//
//  ImageCropView.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/2/25.
//

import SwiftUI
import PhotosUI

struct ImageCropView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void
    
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    // Constants for better UX
    private let cropCircleSize: CGFloat = 280
    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 4.0
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Color.black.ignoresSafeArea()
                    
                    // Main image container
                    ZStack {
                        // The actual image
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                SimultaneousGesture(
                                    // Pan gesture
                                    DragGesture()
                                        .onChanged { value in
                                            let newOffset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                            offset = constrainOffset(newOffset, in: geometry.size)
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        },
                                    
                                    // Zoom gesture
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let newScale = lastScale * value
                                            scale = min(max(newScale, minScale), maxScale)
                                            
                                            // Constrain offset when scaling
                                            offset = constrainOffset(offset, in: geometry.size)
                                        }
                                        .onEnded { _ in
                                            lastScale = scale
                                            lastOffset = offset
                                        }
                                )
                            )
                            .onAppear {
                                setupInitialScale(in: geometry.size)
                            }
                        
                        // Crop overlay with circular preview
                        CircularCropOverlay(
                            cropSize: cropCircleSize,
                            screenSize: geometry.size
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
            .navigationTitle("Crop Profile Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        cropImage()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupInitialScale(in screenSize: CGSize) {
        // Calculate the optimal initial scale to fit the image nicely in the crop circle
        let imageSize = image.size
        _ = imageSize.width / imageSize.height // Remove unused variable warning
        
        let fitWidth = cropCircleSize
        let fitHeight = cropCircleSize
        
        let scaleToFitWidth = fitWidth / imageSize.width
        let scaleToFitHeight = fitHeight / imageSize.height
        
        // Use the larger scale factor to ensure the image covers the crop area
        let initialScale = max(scaleToFitWidth, scaleToFitHeight) * 1.1 // 10% larger for better coverage
        
        scale = min(max(initialScale, minScale), maxScale)
        lastScale = scale
    }
    
    private func constrainOffset(_ proposedOffset: CGSize, in screenSize: CGSize) -> CGSize {
        // Calculate the actual displayed image size
        let imageSize = image.size
        let imageAspectRatio = imageSize.width / imageSize.height
        
        // Determine how the image is displayed (aspect fit)
        let displayWidth: CGFloat
        let displayHeight: CGFloat
        
        if imageAspectRatio > screenSize.width / screenSize.height {
            // Image is wider relative to screen
            displayWidth = screenSize.width
            displayHeight = screenSize.width / imageAspectRatio
        } else {
            // Image is taller relative to screen
            displayHeight = screenSize.height
            displayWidth = screenSize.height * imageAspectRatio
        }
        
        // Apply current scale
        let scaledWidth = displayWidth * scale
        let scaledHeight = displayHeight * scale
        
        // Calculate maximum allowed offset to keep crop area filled
        let maxOffsetX = max(0, (scaledWidth - cropCircleSize) / 2)
        let maxOffsetY = max(0, (scaledHeight - cropCircleSize) / 2)
        
        // Break down the complex calculation
        let constrainedWidth = max(proposedOffset.width, -maxOffsetX)
        let finalWidth = min(constrainedWidth, maxOffsetX)
        
        let constrainedHeight = max(proposedOffset.height, -maxOffsetY)
        let finalHeight = min(constrainedHeight, maxOffsetY)
        
        return CGSize(width: finalWidth, height: finalHeight)
    }
    
    private func cropImage() {
        let imageSize = image.size
        let outputSize = CGSize(width: 400, height: 400) // Final circular image size
        
        // Calculate the crop rectangle in image coordinates
        let imageAspectRatio = imageSize.width / imageSize.height
        
        // Determine the displayed image size (how it appears on screen)
        let screenBounds = UIScreen.main.bounds
        let displayWidth: CGFloat
        let displayHeight: CGFloat
        
        if imageAspectRatio > 1 {
            displayWidth = screenBounds.width
            displayHeight = screenBounds.width / imageAspectRatio
        } else {
            displayHeight = screenBounds.height
            displayWidth = screenBounds.height * imageAspectRatio
        }
        
        // Scale factor from display coordinates to image coordinates
        let scaleToImage = max(imageSize.width / displayWidth, imageSize.height / displayHeight)
        
        // Calculate the crop area in image coordinates
        let cropSizeInImage = cropCircleSize * scaleToImage / scale
        
        // Center of the crop area, accounting for user's pan
        let cropCenterX = (imageSize.width / 2) - (offset.width * scaleToImage / scale)
        let cropCenterY = (imageSize.height / 2) - (offset.height * scaleToImage / scale)
        
        // Define the crop rectangle
        let cropRect = CGRect(
            x: cropCenterX - cropSizeInImage / 2,
            y: cropCenterY - cropSizeInImage / 2,
            width: cropSizeInImage,
            height: cropSizeInImage
        )
        
        // Ensure crop rect is within image bounds
        let clampedCropRect = CGRect(
            x: max(0, min(cropRect.origin.x, imageSize.width - cropRect.width)),
            y: max(0, min(cropRect.origin.y, imageSize.height - cropRect.height)),
            width: min(cropRect.width, imageSize.width),
            height: min(cropRect.height, imageSize.height)
        )
        
        // Perform the crop
        guard let cgImage = image.cgImage?.cropping(to: clampedCropRect) else {
            // Fallback
            let fallbackImage = resizeImageToCircle(image, to: outputSize)
            onCrop(fallbackImage)
            return
        }
        
        let croppedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        let finalImage = resizeImageToCircle(croppedImage, to: outputSize)
        
        onCrop(finalImage)
    }
    
    private func resizeImageToCircle(_ image: UIImage, to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            
            // Create circular clipping path
            context.cgContext.addEllipse(in: rect)
            context.cgContext.clip()
            
            // Draw the image
            image.draw(in: rect)
        }
    }
}
