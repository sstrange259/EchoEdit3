//
//  AspectRatio.swift
//  TextTune
//
//  Created by Claude on 6/17/25.
//

import Foundation
import UIKit

struct AspectRatio: Identifiable, Equatable {
    let id = UUID()
    let width: Int
    let height: Int
    let name: String
    
    var ratio: Double {
        return Double(width) / Double(height)
    }
    
    var displayName: String {
        return "\(width):\(height)"
    }
    
    static func ==(lhs: AspectRatio, rhs: AspectRatio) -> Bool {
        return lhs.width == rhs.width && lhs.height == rhs.height
    }
}

// Standard aspect ratios
extension AspectRatio {
    static let predefined: [AspectRatio] = [
        AspectRatio(width: 1, height: 1, name: "Square"),
        AspectRatio(width: 1, height: 2, name: "Portrait"),
        AspectRatio(width: 2, height: 1, name: "Landscape"),
        AspectRatio(width: 2, height: 3, name: "Portrait 2:3"),
        AspectRatio(width: 3, height: 2, name: "Landscape 3:2"),
        AspectRatio(width: 4, height: 7, name: "Portrait 4:7"),
        AspectRatio(width: 5, height: 8, name: "Portrait 5:8"),
        AspectRatio(width: 8, height: 5, name: "Landscape 8:5"),
        AspectRatio(width: 7, height: 4, name: "Landscape 7:4"),
        AspectRatio(width: 9, height: 5, name: "Landscape 9:5"),
        AspectRatio(width: 5, height: 9, name: "Portrait 5:9"),
        AspectRatio(width: 9, height: 16, name: "Portrait 9:16"),
        AspectRatio(width: 16, height: 9, name: "Landscape 16:9"),
        AspectRatio(width: 13, height: 19, name: "Portrait 13:19"),
        AspectRatio(width: 19, height: 13, name: "Landscape 19:13"),
        AspectRatio(width: 7, height: 9, name: "Portrait 7:9"),
        AspectRatio(width: 9, height: 7, name: "Landscape 9:7")
    ]
    
    // Find the closest aspect ratio
    static func findClosest(to ratio: Double) -> AspectRatio {
        var closestRatio = predefined.first!
        var minDifference = abs(closestRatio.ratio - ratio)
        
        for aspectRatio in predefined {
            let difference = abs(aspectRatio.ratio - ratio)
            if difference < minDifference {
                minDifference = difference
                closestRatio = aspectRatio
            }
        }
        
        return closestRatio
    }
}

// Image processing extension
extension UIImage {
    // Calculate the image's aspect ratio
    var aspectRatio: Double {
        return Double(size.width) / Double(size.height)
    }
    
    // Detect and return the closest predefined aspect ratio
    func detectAspectRatio() -> AspectRatio {
        return AspectRatio.findClosest(to: self.aspectRatio)
    }
    
    // Crop image to match a specific aspect ratio
    func cropToAspectRatio(_ targetRatio: AspectRatio) -> UIImage {
        let currentRatio = self.aspectRatio
        let targetRatioValue = targetRatio.ratio
        
        // If ratios are already very close, return the original image
        if abs(currentRatio - targetRatioValue) < 0.01 {
            return self
        }
        
        let cropRect: CGRect
        
        // Determine if we need to crop width or height
        if currentRatio > targetRatioValue {
            // Current image is wider than target ratio, crop width
            let newWidth = size.height * CGFloat(targetRatioValue)
            let offsetX = (size.width - newWidth) / 2
            cropRect = CGRect(x: offsetX, y: 0, width: newWidth, height: size.height)
        } else {
            // Current image is taller than target ratio, crop height
            let newHeight = size.width / CGFloat(targetRatioValue)
            let offsetY = (size.height - newHeight) / 2
            cropRect = CGRect(x: 0, y: offsetY, width: size.width, height: newHeight)
        }
        
        // Perform the crop
        if let cgImage = self.cgImage?.cropping(to: cropRect) {
            return UIImage(cgImage: cgImage, scale: self.scale, orientation: self.imageOrientation)
        }
        
        // Return original if cropping fails
        return self
    }
    
    // Auto-detect and crop to closest aspect ratio
    func autoCropToClosestAspectRatio() -> UIImage {
        let closestRatio = self.detectAspectRatio()
        return self.cropToAspectRatio(closestRatio)
    }
}