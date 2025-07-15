//
//  AspectRatioSelector.swift
//  TextTune
//
//  Created by Claude on 6/17/25.
//

import SwiftUI

struct AspectRatioSelector: View {
    @Binding var selectedRatio: AspectRatio?
    @Binding var showSelector: Bool
    let image: UIImage
    var onCropComplete: (UIImage) -> Void
    
    @State private var detectedRatio: AspectRatio?
    @State private var croppedImage: UIImage?
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Aspect Ratio")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    showSelector = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal)
            
            // Detected ratio info
            if let detectedRatio = detectedRatio {
                HStack {
                    Text("Detected: \(detectedRatio.displayName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Auto Crop") {
                        let processed = image.cropToAspectRatio(detectedRatio)
                        self.croppedImage = processed
                        self.selectedRatio = detectedRatio
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
                .padding(.horizontal)
            }
            
            // Preview
            ZStack {
                if let croppedImage = croppedImage {
                    Image(uiImage: croppedImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(height: 200)
            .padding(.horizontal)
            
            // Ratio grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ], spacing: 8) {
                    ForEach(AspectRatio.predefined) { ratio in
                        AspectRatioCell(ratio: ratio, isSelected: selectedRatio == ratio)
                            .onTapGesture {
                                selectedRatio = ratio
                                let processed = image.cropToAspectRatio(ratio)
                                self.croppedImage = processed
                            }
                    }
                }
                .padding(.horizontal)
            }
            
            // Apply button
            Button(action: {
                if let croppedImage = croppedImage {
                    onCropComplete(croppedImage)
                    showSelector = false
                }
            }) {
                Text("Apply Crop")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .disabled(croppedImage == nil)
        }
        .padding()
        .onAppear {
            // Detect the aspect ratio when view appears
            self.detectedRatio = image.detectAspectRatio()
            
            // Set initial selected ratio to detected ratio
            if selectedRatio == nil {
                selectedRatio = detectedRatio
            }
        }
    }
}

// Cell representing an aspect ratio option
struct AspectRatioCell: View {
    let ratio: AspectRatio
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            // Visual representation of the ratio
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(CGFloat(ratio.width) / CGFloat(ratio.height), contentMode: .fit)
                .frame(height: 50)
                .overlay(
                    Rectangle()
                        .stroke(isSelected ? Color.blue : Color.gray, lineWidth: isSelected ? 2 : 1)
                )
            
            // Ratio label
            Text(ratio.displayName)
                .font(.caption)
                .foregroundColor(isSelected ? .blue : .primary)
        }
    }
}