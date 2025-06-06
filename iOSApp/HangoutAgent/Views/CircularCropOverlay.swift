//
//  CircularCropOverlay.swift
//  HangoutAgent
//
//  Created by Tarek Sakakini on 6/4/25.
//


import SwiftUI
import PhotosUI

struct CircularCropOverlay: View {
    let cropSize: CGFloat
    let screenSize: CGSize
    
    private var darkOverlayWithCutout: some View {
        ZStack {
            // Dark overlay covering the entire screen
            Color.black.opacity(0.6)
            
            // Clear circle for the crop area
            Circle()
                .frame(width: cropSize, height: cropSize)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
    
    private var borderElements: some View {
        ZStack {
            // Outer border
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 3)
                .frame(width: cropSize, height: cropSize)
            
            // Inner subtle shadow for depth
            Circle()
                .stroke(Color.black.opacity(0.2), lineWidth: 1)
                .frame(width: cropSize - 6, height: cropSize - 6)
            
            // Corner indicators for better visual guidance
            cornerIndicators
        }
    }
    
    private var cornerIndicators: some View {
        let positions = [
            CGPoint(x: cropSize / 2 + 10, y: 0),
            CGPoint(x: 0, y: cropSize / 2 + 10),
            CGPoint(x: -(cropSize / 2 + 10), y: 0),
            CGPoint(x: 0, y: -(cropSize / 2 + 10))
        ]
        
        return ForEach(Array(positions.enumerated()), id: \.offset) { index, position in
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .offset(x: position.x, y: position.y)
                .opacity(0.7)
        }
    }
    
    private var instructionText: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    Text("Pan")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                VStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    Text("Pinch to Zoom")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.bottom, 50)
        }
    }
    
    var body: some View {
        darkOverlayWithCutout
            .overlay(borderElements)
            .overlay(instructionText)
    }
}