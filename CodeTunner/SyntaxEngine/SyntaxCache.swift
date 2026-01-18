//
//  SyntaxCache.swift
//  CodeTunner - Syntax Highlighting Engine
//
//  Line-based caching for incremental syntax highlighting.
//  Only re-parses lines that have changed, dramatically improving performance.
//
//  Design Pattern: Cache-Aside Pattern
//  - Cache is checked before computation
//  - Invalid entries are lazily recomputed
//  - Dirty tracking enables minimal work
//
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import Foundation

// MARK: - Line Cache Entry

/// Cached tokenization result for a single line.
public struct LineCacheEntry: Sendable {
    /// The line content when it was tokenized
    public let lineContent: String
    
    /// SyntaxTokens on this line
    public let tokens: [SyntaxToken]
    
    /// Lexer state at the start of this line
    public let startState: SyntaxLexerState
    
    /// Lexer state at the end of this line
    public let endState: SyntaxLexerState
    
    /// Whether this entry is still valid
    public var isValid: Bool
    
    public init(lineContent: String, tokens: [SyntaxToken], startState: SyntaxLexerState, endState: SyntaxLexerState) {
        self.lineContent = lineContent
        self.tokens = tokens
        self.startState = startState
        self.endState = endState
        self.isValid = true
    }
    
    /// Create a copy with shifted token offsets
    public func shifted(by offsetDelta: Int) -> LineCacheEntry {
        if offsetDelta == 0 { return self }
        
        let newTokens = tokens.map { token -> SyntaxToken in
            let oldRange = token.range
            let newRange = SyntaxTextRange(
                startLine: oldRange.startLine, // Lines are re-indexed by cache, but range inside token needs update?
                // Wait, SyntaxTextRange has line/column. If line moves, we need to update line too?
                // The cache dictates the line number (key).
                // But the token stores the line number.
                // Yes, we must update LINE and OFFSET.
                // But wait, handleDocumentChange handles line shifts by keys.
                // Does it iterate to update line numbers in tokens?
                // If I just update offsets, line numbers in tokens will be WRONG relative to their new position!
                
                // Correction: We must update line numbers inside tokens too.
                // But `shifted(by:)` usually assumes offset.
                // Let's call it `shifted(lineDelta: Int, offsetDelta: Int)`
                
                startColumn: oldRange.startColumn,
                endLine: oldRange.endLine, // Assuming single line tokens for cache?
                endColumn: oldRange.endColumn,
                startOffset: oldRange.startOffset + offsetDelta,
                endOffset: oldRange.endOffset + offsetDelta
            )
            // But we actually need to update LINES too. 
            // So I will defer this to the `handleDocumentChange` loop to do it manually or helper.
            return SyntaxToken(type: token.type, text: token.text, range: newRange, endState: token.endState)
        }
        return LineCacheEntry(lineContent: lineContent, tokens: newTokens, startState: startState, endState: endState)
    }
    
    public func shifted(lineDelta: Int, offsetDelta: Int) -> LineCacheEntry {
        if lineDelta == 0 && offsetDelta == 0 { return self }
        
        let newTokens = tokens.map { token -> SyntaxToken in
            let oldRange = token.range
            let newRange = SyntaxTextRange(
                startLine: oldRange.startLine + lineDelta,
                startColumn: oldRange.startColumn,
                endLine: oldRange.endLine + lineDelta,
                endColumn: oldRange.endColumn,
                startOffset: oldRange.startOffset + offsetDelta,
                endOffset: oldRange.endOffset + offsetDelta
            )
            return SyntaxToken(type: token.type, text: token.text, range: newRange, endState: token.endState)
        }
        return LineCacheEntry(lineContent: lineContent, tokens: newTokens, startState: startState, endState: endState)
    }
}


// MARK: - Dirty Region

/// Represents a range of lines that need re-tokenization.
public struct DirtyRegion: Sendable {
    public let startLine: Int
    public let endLine: Int
    
    public init(startLine: Int, endLine: Int) {
        self.startLine = startLine
        self.endLine = endLine
    }
    
    /// Check if a line is within this dirty region
    public func contains(_ line: Int) -> Bool {
        line >= startLine && line <= endLine
    }
    
    /// Merge with another region (union)
    public func merged(with other: DirtyRegion) -> DirtyRegion {
        DirtyRegion(
            startLine: min(startLine, other.startLine),
            endLine: max(endLine, other.endLine)
        )
    }
}

// MARK: - Syntax Cache

/// Caches tokenization results per line for incremental updates.
/// Thread-safe for concurrent access.
public final class SyntaxCache: @unchecked Sendable {
    
    /// Cache entries indexed by line number
    private var cache: [Int: LineCacheEntry] = [:]
    
    /// Pending dirty regions
    private var dirtyRegions: [DirtyRegion] = []
    
    /// Total number of lines in the document
    private(set) var lineCount: Int = 0
    
    /// Lock for thread safety
    private let lock = NSRecursiveLock()
    
    /// Cached flattened tokens for performance
    private var _flattenedTokens: [SyntaxToken]?
    
    public init() {}
    
    // MARK: - Cache Access
    
    /// Get cached entry for a line
    public func entry(forLine line: Int) -> LineCacheEntry? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let entry = cache[line], entry.isValid else {
            return nil
        }
        return entry
    }
    
    /// Store cache entry for a line
    public func setEntry(_ entry: LineCacheEntry, forLine line: Int) {
        lock.lock()
        defer { lock.unlock() }
        cache[line] = entry
        _flattenedTokens = nil // Invalidate flattened cache
    }
    
    /// Get all cached tokens (if fully cached)
    public func allSyntaxTokens() -> [SyntaxToken] {
        lock.lock()
        defer { lock.unlock() }
        
        if let cached = _flattenedTokens {
            return cached
        }
        
        var tokens: [SyntaxToken] = []
        for line in 0..<lineCount {
            if let entry = cache[line], entry.isValid {
                tokens.append(contentsOf: entry.tokens)
            }
        }
        
        _flattenedTokens = tokens
        return tokens
    }
    
    // MARK: - Dirty Tracking
    
    /// Mark a range of lines as dirty
    public func markDirty(fromLine start: Int, toLine end: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        let newRegion = DirtyRegion(startLine: start, endLine: end)
        
        // Merge with existing regions if overlapping
        var merged = newRegion
        dirtyRegions = dirtyRegions.compactMap { region in
            if region.endLine >= start - 1 && region.startLine <= end + 1 {
                merged = merged.merged(with: region)
                return nil
            }
            return region
        }
        dirtyRegions.append(merged)
        
        // Invalidate cache entries in the region
        for line in start...end {
            cache[line]?.isValid = false
        }
    }
    
    /// Mark a single line as dirty
    public func markDirty(line: Int) {
        markDirty(fromLine: line, toLine: line)
    }
    
    /// Get and clear dirty regions
    public func popDirtyRegions() -> [DirtyRegion] {
        lock.lock()
        defer { lock.unlock() }
        
        let regions = dirtyRegions
        dirtyRegions.removeAll()
        return regions
    }
    
    /// Check if any lines are dirty
    public var hasDirtyRegions: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !dirtyRegions.isEmpty
    }
    
    // MARK: - Document Changes
    
    /// Handle document content change
    /// - Parameters:
    ///   - changeStart: Line where change started
    ///   - linesRemoved: Number of lines removed
    ///   - linesAdded: Number of lines added
    ///   - charDelta: Number of characters added (positive) or removed (negative)
    public func handleDocumentChange(changeStart: Int, linesRemoved: Int, linesAdded: Int, charDelta: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        let lineDelta = linesAdded - linesRemoved
        
        // If nothing changed, return
        if lineDelta == 0 && charDelta == 0 { return }
        
        // OPTIMIZATION: If line count didn't change (simple edit), avoid rebuilding entire cache
        if lineDelta == 0 {
            // Only need to shift offsets for lines AFTER the change
            // We can iterate just the keys or use in-place updates if we traverse
            // But Map iteration is safer.
            // Actually, we must mutate entries.
            // Since dictionary keys (line numbers) don't change, we don't need newCache!
            // We just need to update values for keys > changeStart + linesAdded
            
            // However, iterating all keys is still O(N).
            // But we avoid allocating a whole new Dictionary.
            
            for (line, entry) in cache {
                // Fix: Do NOT shift the modified line itself (line == changeStart).
                // It contains modified content, so its old tokens are invalid and determining exact
                // shift per token is complex/impossible without re-lexing.
                // We rely on dirty region marking to re-lex it.
                // Only shift lines strictly AFTER the modified region.
                if line > changeStart + linesAdded {
                   cache[line] = entry.shifted(lineDelta: 0, offsetDelta: charDelta)
                }
            }
            
            // Mark dirty
            let dirtyEnd = changeStart + linesAdded
            let start = changeStart
            let end = max(changeStart, dirtyEnd - 1)
            
            // Mark new region dirty inline
            let newRegion = DirtyRegion(startLine: start, endLine: end)
            var merged = newRegion
            dirtyRegions = dirtyRegions.compactMap { region in
                if region.endLine >= start - 1 && region.startLine <= end + 1 {
                    merged = merged.merged(with: region)
                    return nil
                }
                return region
            }
            dirtyRegions.append(merged)
            for line in start...end {
                cache[line]?.isValid = false
            }
            
            return
        }
        
        // Use a new cache to rebuild with shifted keys/values
        var newCache: [Int: LineCacheEntry] = [:]
        
        for (line, entry) in cache {
            if line < changeStart {
                // Lines before change are unaffected
                newCache[line] = entry
            } else if line >= changeStart + linesRemoved {
                // Lines after change: Shift line index AND token offsets
                let newLine = line + lineDelta
                let newEntry = entry.shifted(lineDelta: lineDelta, offsetDelta: charDelta)
                newCache[newLine] = newEntry
            }
            // Lines in the removed range are dropped
        }
        
        cache = newCache
        lineCount += lineDelta
        
        lineCount += lineDelta
        
        // Mark affected lines as dirty
        // CRITICAL FIX: When lines are added (e.g. split line), we must mark the start line AND the new lines as dirty.
        // If linesAdded = 1 (split), we affect line N and line N+1.
        // Range should be changeStart...changeStart + linesAdded
        let dirtyEndLine = changeStart + linesAdded
        markDirty(fromLine: changeStart, toLine: dirtyEndLine)
    }
    
    /// Handle insertion of new lines
    public func handleLinesInserted(at line: Int, count: Int, charCount: Int) {
        handleDocumentChange(changeStart: line, linesRemoved: 0, linesAdded: count, charDelta: charCount)
    }
    
    /// Handle deletion of lines
    public func handleLinesDeleted(from startLine: Int, count: Int, charCount: Int) {
        handleDocumentChange(changeStart: startLine, linesRemoved: count, linesAdded: 0, charDelta: -charCount)
    }
    
    /// Handle single line modification
    public func handleLineModified(at line: Int, newContent: String) {
        lock.lock()
        
        // Check if the line actually changed
        if let existingEntry = cache[line], existingEntry.lineContent == newContent {
            lock.unlock()
            return // No change
        }
        
        lock.unlock()
        
        markDirty(line: line)
    }
    
    // MARK: - Reset
    
    /// Clear the entire cache
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        cache.removeAll()
        dirtyRegions.removeAll()
    }
    
    /// Initialize cache for a new document
    public func initialize(withLineCount count: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        cache.removeAll()
        dirtyRegions.removeAll()
        lineCount = count
        
        // Mark entire document as dirty
        if count > 0 {
            dirtyRegions.append(DirtyRegion(startLine: 0, endLine: count - 1))
        }
    }
}

// MARK: - Incremental Lexer

/// Wraps a lexer to provide incremental tokenization using a cache.
public final class IncrementalLexer: @unchecked Sendable {
    
    /// The underlying lexer
    public let baseLexer: LexerProtocol
    
    /// The syntax cache
    public let cache: SyntaxCache
    
    public init(lexer: LexerProtocol) {
        self.baseLexer = lexer
        self.cache = SyntaxCache()
    }
    
    /// Initialize with a document
    public func initialize(with document: String) {
        let lines = document.components(separatedBy: "\n")
        cache.initialize(withLineCount: lines.count)
        
        // Initial tokenization is deferred to the first retokenizeDirtyRegions call
        // This prevents blocking the main thread during document load
    }
    
    /// Full document tokenization (used for initial load)
    public func tokenizeDocument(_ document: String) -> [SyntaxToken] {
        let lines = document.components(separatedBy: "\n")
        var allSyntaxTokens: [SyntaxToken] = []
        var currentState: SyntaxLexerState = .normal
        var currentOffset = 0
        
        for (lineNumber, line) in lines.enumerated() {
            let startState = currentState
            let (tokens, endState) = baseLexer.tokenizeLine(line, lineNumber: lineNumber, startState: startState, startOffset: currentOffset)
            
            // Cache the result
            let entry = LineCacheEntry(
                lineContent: line,
                tokens: tokens,
                startState: startState,
                endState: endState
            )
            cache.setEntry(entry, forLine: lineNumber)
            
            allSyntaxTokens.append(contentsOf: tokens)
            currentState = endState
            currentOffset += line.utf16.count + 1
        }
        
        return allSyntaxTokens
    }
    
    /// Incremental re-tokenization of dirty regions only
    public func retokenizeDirtyRegions(in document: String) -> [SyntaxToken] {
        // ZOMBIE KILLER: Check if this task is already cancelled
        if Task.isCancelled { return [] }
        
        let lines = document.components(separatedBy: "\n")
        let dirtyRegions = cache.popDirtyRegions()
        
        guard !dirtyRegions.isEmpty else {
            return cache.allSyntaxTokens()
        }
        
        for region in dirtyRegions {
            // ZOMBIE KILLER: Stop processing if cancelled
            if Task.isCancelled { return [] }
            retokenizeRegion(startLine: region.startLine, endLine: region.endLine, lines: lines)
        }
        
        return cache.allSyntaxTokens()
    }
    
    /// Re-tokenize a specific region
    private func retokenizeRegion(startLine: Int, endLine: Int, lines: [String]) {
        guard startLine >= 0 && startLine < lines.count else { return }
        
        // Get the state from the previous line (if exists)
        var currentState: SyntaxLexerState = .normal
        if startLine > 0, let prevEntry = cache.entry(forLine: startLine - 1) {
            currentState = prevEntry.endState
        }
        
        // Calculate starting offset (Optimized)
        var currentOffset = 0
        if startLine > 0, let prevEntry = cache.entry(forLine: startLine - 1), let lastToken = prevEntry.tokens.last {
             // Use cached offset from previous line if available (O(1))
             currentOffset = lastToken.range.endOffset
        } else {
             // Fallback to O(N) scan only if cache missing (rare inside stable doc)
             for i in 0..<startLine {
                 if i < lines.count {
                     currentOffset += lines[i].utf16.count + 1 // +1 for newline
                 }
             }
        }
        
        // SyntaxTokenize lines until the end state stabilizes
        var lineNumber = startLine
        
        while lineNumber < lines.count {
            // ZOMBIE KILLER: Stop processing if cancelled
            if Task.isCancelled { return }
            
            // Check if we've passed the dirty region
            if lineNumber > endLine {
                // If the next line is valid and the state matches what we expect, we can stop propagation.
                // We access the cache directly. If it returns an entry, it means it's VALID (not dirty).
                if let existingEntry = cache.entry(forLine: lineNumber) {
                    if existingEntry.startState == currentState {
                        // Optimization: State stabilized, stop processing.
                        break
                    }
                }
            }
            
            let line = lines[lineNumber]
            let startState = currentState
            let (tokens, newEndState) = baseLexer.tokenizeLine(line, lineNumber: lineNumber, startState: startState, startOffset: currentOffset)
            
            // Cache the result
            let entry = LineCacheEntry(
                lineContent: line,
                tokens: tokens, // Note: tokens already contain absolute offsets based on startOffset
                startState: startState,
                endState: newEndState
            )
            cache.setEntry(entry, forLine: lineNumber)
            
            // Prepare for next line
            currentState = newEndState
            currentOffset += line.utf16.count + 1
            lineNumber += 1
        }
    }
    
    /// Handle a text edit
    public func handleEdit(at line: Int, newContent: String) {
        cache.handleLineModified(at: line, newContent: newContent)
    }
    
    /// Handle multiple lines changed
    public func handleLinesChanged(from startLine: Int, to endLine: Int) {
        cache.markDirty(fromLine: startLine, toLine: endLine)
    }
}
