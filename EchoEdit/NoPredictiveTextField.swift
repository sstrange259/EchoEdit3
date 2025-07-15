//
//  NoPredictiveTextField.swift
//  TextTune
//
//  Created by Steven Strange on 6/13/25.
//

import SwiftUI
import UIKit

// MARK: - Custom Text Input with Suggestion
struct NoPredictiveTextField: UIViewRepresentable {
    @Binding var text: String
    var suggestion: String
    
    func makeUIView(context: Context) -> CustomTextView {
        let textView = CustomTextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.text = text
        textView.backgroundColor = .clear
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.textColor = UIColor.label
        textView.suggestionText = suggestion
        
        // Configure for single-line, non-wrapping behavior
        textView.isScrollEnabled = true
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.maximumNumberOfLines = 1
        textView.textContainer.lineBreakMode = .byClipping
        
        // Disable return key functionality
        textView.returnKeyType = .done
        
        // This specifically disables the predictive suggestions bar
        textView.inputAssistantItem.leadingBarButtonGroups = []
        textView.inputAssistantItem.trailingBarButtonGroups = []
        
        return textView
    }
    
    func updateUIView(_ textView: CustomTextView, context: Context) {
        // Only update if the text has changed from outside
        if textView.text != text {
            // Store current selection/cursor position
            let oldSelectedRange = textView.selectedTextRange
            
            // Update the text
            textView.text = text
            
            // If there was no selection, put cursor at the end
            if oldSelectedRange == nil {
                let endPosition = textView.endOfDocument
                textView.selectedTextRange = textView.textRange(from: endPosition, to: endPosition)
            }
            
            // Ensure the cursor is visible
            textView.scrollToCaret()
        }
        
        // Update suggestion text
        if textView.suggestionText != suggestion {
            textView.suggestionText = suggestion
            textView.setNeedsDisplay()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        
        init(text: Binding<String>) {
            self._text = text
        }
        
        func textViewDidChange(_ textView: UITextView) {
            // Remove any newline characters
            if textView.text.contains("\n") {
                textView.text = textView.text.replacingOccurrences(of: "\n", with: "")
            }
            
            // Update binding
            text = textView.text
            
            // Scroll to keep the end of text visible
            if textView.text.count > 0 {
                let range = NSMakeRange(textView.text.count - 1, 0)
                textView.scrollRangeToVisible(range)
            }
            
            // Force redraw to update suggestion visibility
            textView.setNeedsDisplay()
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            if let selectedRange = textView.selectedTextRange {
                let rect = textView.caretRect(for: selectedRange.start)
                let visibleRect = textView.convert(rect, to: textView)
                textView.scrollRectToVisible(visibleRect, animated: false)
            }
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Prevent new lines
            if text == "\n" {
                textView.resignFirstResponder()
                return false
            }
            return true
        }
    }
}