//
//  GraphemeHelper.swift
//  MicroCode - IME-First Editor Support
//
//  Provides utilities for safe conversion between NSRange (UTF-16) and
//  Swift String indices, respecting grapheme clusters for Thai, CJK, Arabic, etc.
//
//  Copyright © 2026 SPU AI CLUB. All rights reserved.
//

import Foundation

// MARK: - Grapheme Cluster Safe Range Conversion

extension String {
    
    /// Converts an NSRange (UTF-16 based) to a Swift String Range, respecting grapheme cluster boundaries.
    /// Returns nil if the range is invalid.
    func graphemeRange(from nsRange: NSRange) -> Range<String.Index>? {
        guard nsRange.location != NSNotFound else { return nil }
        
        let utf16 = self.utf16
        guard let start = utf16.index(utf16.startIndex, offsetBy: nsRange.location, limitedBy: utf16.endIndex),
              let end = utf16.index(start, offsetBy: nsRange.length, limitedBy: utf16.endIndex) else {
            return nil
        }
        
        // Convert UTF-16 indices to String indices (grapheme-aligned)
        guard let startIndex = String.Index(start, within: self),
              let endIndex = String.Index(end, within: self) else {
            return nil
        }
        
        return startIndex..<endIndex
    }
    
    /// Converts a Swift String Range to an NSRange (UTF-16 based).
    func nsRange(from range: Range<String.Index>) -> NSRange {
        let utf16 = self.utf16
        let location = utf16.distance(from: utf16.startIndex, to: range.lowerBound.samePosition(in: utf16) ?? utf16.startIndex)
        let length = utf16.distance(from: range.lowerBound.samePosition(in: utf16) ?? utf16.startIndex,
                                    to: range.upperBound.samePosition(in: utf16) ?? utf16.endIndex)
        return NSRange(location: location, length: length)
    }
    
    /// Returns the grapheme cluster index for a given UTF-16 offset.
    /// Thai: `กำ` (2 UTF-16 units) -> grapheme index 1
    func graphemeIndex(forUTF16Offset offset: Int) -> Int {
        guard offset > 0 else { return 0 }
        
        let utf16 = self.utf16
        guard let targetIndex = utf16.index(utf16.startIndex, offsetBy: offset, limitedBy: utf16.endIndex) else {
            return self.count
        }
        
        guard let stringIndex = String.Index(targetIndex, within: self) else {
            return self.count
        }
        
        return self.distance(from: self.startIndex, to: stringIndex)
    }
    
    /// Returns the UTF-16 offset for a given grapheme cluster index.
    func utf16Offset(forGraphemeIndex graphemeIndex: Int) -> Int {
        guard graphemeIndex > 0 else { return 0 }
        
        let targetIndex = self.index(self.startIndex, offsetBy: min(graphemeIndex, self.count))
        guard let utf16Index = targetIndex.samePosition(in: self.utf16) else {
            return self.utf16.count
        }
        
        return self.utf16.distance(from: self.utf16.startIndex, to: utf16Index)
    }
}

// MARK: - NSTextView Grapheme Helpers

#if canImport(AppKit)
import AppKit

extension NSTextView {
    
    /// Moves the cursor to the next grapheme cluster (instead of UTF-16 unit).
    func moveToNextGrapheme() {
        guard let textStorage = self.textStorage else { return }
        let currentLocation = selectedRange().location
        let string = textStorage.string
        
        // Find current String.Index
        let utf16 = string.utf16
        guard let currentUTF16Index = utf16.index(utf16.startIndex, offsetBy: currentLocation, limitedBy: utf16.endIndex),
              let currentStringIndex = String.Index(currentUTF16Index, within: string) else {
            return
        }
        
        // Move to next grapheme
        let nextIndex = string.index(after: currentStringIndex)
        guard let nextUTF16Index = nextIndex.samePosition(in: utf16) else { return }
        
        let newLocation = utf16.distance(from: utf16.startIndex, to: nextUTF16Index)
        setSelectedRange(NSRange(location: newLocation, length: 0))
    }
    
    /// Moves the cursor to the previous grapheme cluster.
    func moveToPreviousGrapheme() {
        guard let textStorage = self.textStorage else { return }
        let currentLocation = selectedRange().location
        guard currentLocation > 0 else { return }
        
        let string = textStorage.string
        
        // Find current String.Index
        let utf16 = string.utf16
        guard let currentUTF16Index = utf16.index(utf16.startIndex, offsetBy: currentLocation, limitedBy: utf16.endIndex),
              let currentStringIndex = String.Index(currentUTF16Index, within: string) else {
            return
        }
        
        // Move to previous grapheme
        let prevIndex = string.index(before: currentStringIndex)
        guard let prevUTF16Index = prevIndex.samePosition(in: utf16) else { return }
        
        let newLocation = utf16.distance(from: utf16.startIndex, to: prevUTF16Index)
        setSelectedRange(NSRange(location: newLocation, length: 0))
    }
    
    /// Selects the grapheme cluster at the current cursor position.
    func selectCurrentGrapheme() {
        guard let textStorage = self.textStorage else { return }
        let currentLocation = selectedRange().location
        let string = textStorage.string
        
        guard !string.isEmpty, currentLocation < string.utf16.count else { return }
        
        let utf16 = string.utf16
        guard let currentUTF16Index = utf16.index(utf16.startIndex, offsetBy: currentLocation, limitedBy: utf16.endIndex),
              let currentStringIndex = String.Index(currentUTF16Index, within: string) else {
            return
        }
        
        // Get the range of the current grapheme cluster
        let graphemeRange = string.rangeOfComposedCharacterSequence(at: currentStringIndex)
        let nsRange = string.nsRange(from: graphemeRange)
        
        setSelectedRange(nsRange)
    }
}
#endif

// MARK: - RTL Detection

extension String {
    
    /// Detects if the string primarily contains RTL characters (Arabic, Hebrew).
    var isRTL: Bool {
        guard let firstChar = self.first else { return false }
        
        // Check unicode properties
        guard let scalar = firstChar.unicodeScalars.first else { return false }
        
        // Arabic: 0x0600-0x06FF, 0x0750-0x077F, 0x08A0-0x08FF
        // Hebrew: 0x0590-0x05FF
        let value = scalar.value
        
        if (value >= 0x0590 && value <= 0x05FF) { return true } // Hebrew
        if (value >= 0x0600 && value <= 0x06FF) { return true } // Arabic
        if (value >= 0x0750 && value <= 0x077F) { return true } // Arabic Supplement
        if (value >= 0x08A0 && value <= 0x08FF) { return true } // Arabic Extended-A
        if (value >= 0xFB50 && value <= 0xFDFF) { return true } // Arabic Presentation Forms-A
        if (value >= 0xFE70 && value <= 0xFEFF) { return true } // Arabic Presentation Forms-B
        
        return false
    }
    
    /// Returns the dominant writing direction of the string.
    var dominantWritingDirection: NSWritingDirection {
        var rtlCount = 0
        var ltrCount = 0
        
        for char in self.prefix(100) { // Sample first 100 chars
            if String(char).isRTL {
                rtlCount += 1
            } else if char.isLetter {
                ltrCount += 1
            }
        }
        
        if rtlCount > ltrCount {
            return .rightToLeft
        } else if ltrCount > rtlCount {
            return .leftToRight
        }
        return .natural
    }
}
