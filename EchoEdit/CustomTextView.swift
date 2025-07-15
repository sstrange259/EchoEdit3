//
//  CustomTextView.swift
//  TextTune
//
//  Created by Steven Strange on 6/13/25.
//

import UIKit


// Custom UITextView subclass that handles its own suggestion drawing
class CustomTextView: UITextView {
    var suggestionText: String = "" {
        didSet {
            if oldValue != suggestionText {
                setNeedsDisplay()
            }
        }
    }
    
    // Computed property to get the visible portion of the text view
    var scrollVisibleRect: CGRect {
        let contentOffset = self.contentOffset
        return CGRect(
            x: contentOffset.x,
            y: contentOffset.y,
            width: self.bounds.width,
            height: self.bounds.height
        )
    }
    
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setupTextView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextView()
    }
    
    private func setupTextView() {
        // Disable line wrapping by making the text container very wide
        textContainer.widthTracksTextView = false
        textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: self.bounds.height)
        
        // Ensure single line
        textContainer.maximumNumberOfLines = 1
        textContainer.lineBreakMode = .byClipping
        
        // Configure scrolling
        isScrollEnabled = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = true
        alwaysBounceVertical = false
        
        // Add right inset to prevent cursor from being clipped
        contentInset.right = bounds.width
        
        // Disable auto layout constraints on content size
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }
    
    // Ensure cursor is always visible after text updates
    override func layoutSubviews() {
        super.layoutSubviews()
        scrollToCaret()
    }
    
    func scrollToCaret() {
        // Only scroll if we have a selection
        if let selectedRange = selectedTextRange {
            let caretRect = caretRect(for: selectedRange.end)
            
            // Always make the caret visible at the right edge of the text field
            // This will make text shift to the left as new text is typed
            if caretRect.maxX > bounds.width {
                // Calculate how much to scroll horizontally
                // Position the caret exactly at the right edge
                let newOffsetX = caretRect.maxX - bounds.width
                
                // Make sure we don't scroll past the beginning of content
                let adjustedOffsetX = max(0, newOffsetX)
                
                // Apply the new content offset with no animation for smooth typing
                setContentOffset(CGPoint(x: adjustedOffsetX, y: contentOffset.y), animated: false)
            } 
            // If caret moves left of visible area, scroll to make it visible
            else if caretRect.minX < contentOffset.x {
                let newOffsetX = max(0, caretRect.minX - 10) // 10pt padding from left
                setContentOffset(CGPoint(x: newOffsetX, y: contentOffset.y), animated: false)
            }
        }
    }
    
    override var intrinsicContentSize: CGSize {
        // Allow horizontal content to extend beyond bounds
        let originalSize = super.intrinsicContentSize
        return CGSize(width: UIView.noIntrinsicMetric, height: originalSize.height)
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        // Only draw suggestion when text is empty
        if text.isEmpty && !suggestionText.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor.tertiaryLabel
            ]
            
            let suggestionRect = CGRect(
                x: textContainerInset.left,
                y: textContainerInset.top,
                width: bounds.width - textContainerInset.left - textContainerInset.right,
                height: bounds.height - textContainerInset.top - textContainerInset.bottom
            )
            
            suggestionText.draw(in: suggestionRect, withAttributes: attributes)
        }
    }
}