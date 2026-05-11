import AppKit
import Combine
import SwiftUI

@MainActor
class GhostTextManager {
    let textView: NSTextView
    let ghostField: NSTextField
    private var cancellables = Set<AnyCancellable>()
    
    init(textView: NSTextView) {
        self.textView = textView
        
        ghostField = NSTextField(labelWithString: "")
        ghostField.font = textView.font
        ghostField.textColor = NSColor.systemGray.withAlphaComponent(0.6)
        ghostField.backgroundColor = .clear
        ghostField.isBordered = false
        ghostField.isEditable = false
        ghostField.isSelectable = false
        ghostField.wantsLayer = true
        
        textView.addSubview(ghostField)
        
        // Listen to AIAutocompleteService
        AIAutocompleteService.shared.$currentSuggestion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] suggestion in
                self?.updateGhostText(suggestion)
            }
            .store(in: &cancellables)
    }
    
    func updateGhostText(_ suggestion: AutocompleteSuggestion?) {
        guard let suggestion = suggestion, !suggestion.text.isEmpty else {
            ghostField.stringValue = ""
            ghostField.isHidden = true
            return
        }
        
        let range = textView.selectedRange()
        guard range.location == suggestion.range.location else {
            // Cursor moved since suggestion
            ghostField.stringValue = ""
            ghostField.isHidden = true
            AIAutocompleteService.shared.clearSuggestion()
            return
        }
        
        // Find position of cursor
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
              
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
        var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let location = layoutManager.location(forGlyphAt: glyphIndex)
        
        // Position ghost text right after cursor
        let xOffset = lineRect.minX + location.x
        let yOffset = lineRect.minY
        
        // Handle multiline ghost text
        ghostField.stringValue = suggestion.text
        ghostField.font = textView.font
        ghostField.sizeToFit()
        
        ghostField.frame = NSRect(x: xOffset, y: yOffset, width: max(500, ghostField.frame.width), height: max(lineRect.height, ghostField.frame.height))
        ghostField.isHidden = false
    }
    
    func acceptSuggestion() -> Bool {
        guard !ghostField.isHidden, let suggestion = AIAutocompleteService.shared.currentSuggestion else {
            return false
        }
        
        // Insert text
        let range = textView.selectedRange()
        if textView.shouldChangeText(in: range, replacementString: suggestion.text) {
            textView.textStorage?.replaceCharacters(in: range, with: suggestion.text)
            textView.didChangeText()
            
            // Move cursor
            textView.setSelectedRange(NSRange(location: range.location + suggestion.text.count, length: 0))
        }
        
        ghostField.isHidden = true
        AIAutocompleteService.shared.clearSuggestion()
        return true
    }
    
    func clear() {
        ghostField.isHidden = true
        AIAutocompleteService.shared.clearSuggestion()
    }
}
