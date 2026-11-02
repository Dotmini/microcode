//
//  SyntaxCache.swift
//  MicroCode - Syntax Highlighting Engine
//
//  Line-based caching for incremental syntax highlighting.
//  Only re-parses lines that have changed, dramatically improving performance.
//
//  Design Pattern: Cache-Aside Pattern
//  - Cache is checked before computation
//  - Invalid entries are lazily recomputed
//  - Dirty tracking enables minimal work
//
//  Copyright © 2025 Dotmini Company Limited. All rights reserved.
//

import Foundation

// MARK: - Line Cache Entry

/// Cached tokenization result for a single line.
/// Entries returned by `SyntaxCache` are materialised views: `tokens` carry absolute offsets and an EMPTY
/// `text`, and `lineContent` is empty (the cache keeps only a content hash, not the line itself).
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

// MARK: - Compact Line Storage

/// A cached token stored LINE-RELATIVE. It carries no absolute UTF-16 offset, no line number and no `String`:
/// 12 bytes instead of an ~100 byte `SyntaxToken` with a heap-allocated `text`.
/// Absolute values are materialised on demand from a line-start table (see `SyntaxCache.materializeTokens`).
struct CompactToken: Sendable {
    /// UTF-16 column of the token start inside its line.
    var col: Int32
    /// UTF-16 length of the token.
    var len: Int32
    /// `SyntaxTokenType.compactIndex`.
    var type: UInt8
    /// `SyntaxLexerState.rawValue` at the end of this token.
    var endState: UInt8
}

/// Cached tokenization result for one line, independent of where the line sits in the document.
/// Inserting or removing lines above it therefore never requires touching this value.
struct CompactLine: Sendable {
    var tokens: [CompactToken]
    /// UTF-16 length of the line (without the newline); used by the legacy offset-less accessors only.
    var length: Int32
    /// Hash of the line content when it was tokenized (replaces storing the whole `String`).
    var contentHash: Int
    var startState: UInt8
    var endState: UInt8
    var isValid: Bool
    
    static let placeholder = CompactLine(tokens: [], length: 0, contentHash: 0, startState: 0, endState: 0, isValid: false)
    
    /// Compacts the output of `LexerProtocol.tokenizeLine`.
    static func make(line: String, lineLength: Int, tokens: [SyntaxToken], startState: SyntaxLexerState, endState: SyntaxLexerState) -> CompactLine {
        var compact: [CompactToken] = []
        compact.reserveCapacity(tokens.count)
        for token in tokens {
            let range = token.range
            compact.append(CompactToken(
                col: Int32(truncatingIfNeeded: range.startColumn),
                len: Int32(truncatingIfNeeded: range.endOffset - range.startOffset),
                type: token.type.compactIndex,
                endState: UInt8(truncatingIfNeeded: token.endState.rawValue)
            ))
        }
        return CompactLine(
            tokens: compact,
            length: Int32(truncatingIfNeeded: lineLength),
            contentHash: line.hashValue,
            startState: UInt8(truncatingIfNeeded: startState.rawValue),
            endState: UInt8(truncatingIfNeeded: endState.rawValue),
            isValid: true
        )
    }
    
    @inline(__always)
    var startLexerState: SyntaxLexerState { SyntaxLexerState(rawValue: Int(startState)) ?? .normal }
    
    @inline(__always)
    var endLexerState: SyntaxLexerState { SyntaxLexerState(rawValue: Int(endState)) ?? .normal }
    
    /// Appends this line's tokens, with absolute offsets/lines, to `out`.
    /// `text` is intentionally empty (see `SyntaxToken.text`).
    @inline(__always)
    func materialize(line: Int, lineStart: Int, into out: inout [SyntaxToken]) {
        let table = SyntaxTokenType.compactTable
        for token in tokens {
            let column = Int(token.col)
            out.append(SyntaxToken(
                type: table[Int(token.type)],
                text: "",
                range: SyntaxTextRange(line: line, column: column, length: Int(token.len), offset: lineStart + column),
                endState: SyntaxLexerState(rawValue: Int(token.endState)) ?? .normal
            ))
        }
    }
}

// MARK: - Syntax Cache

/// Caches tokenization results per line for incremental updates.
/// Thread-safe for concurrent access.
///
/// Storage is a contiguous array of line-relative `CompactLine`s indexed by line number.
/// An edit that adds/removes lines is a single array splice, and entries of lines that were not
/// edited are never rewritten (their column-relative tokens stay valid wherever the line moves).
/// Absolute offsets are produced only when tokens are handed out for a requested line range.
public final class SyntaxCache: @unchecked Sendable {
    public static let shared = SyntaxCache()
    
    /// Cache entries indexed by line number (contiguous; `lines.count` is the document line count)
    private var lines: [CompactLine] = []
    
    /// Pending dirty regions
    private var dirtyRegions: [DirtyRegion] = []
    
    /// Total number of lines in the document
    var lineCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return lines.count
    }
    
    /// Lock for thread safety
    private let lock = NSRecursiveLock()
    
    public init() {}
    
    // MARK: - Cache Access
    
    /// Get cached entry for a line.
    /// The materialised tokens carry absolute offsets derived from the cached per-line lengths
    /// (O(line number)); this is exact only while no dirty regions are pending. Prefer
    /// `entry(forLine:lineStart:)` with the engine's line-start table.
    @available(*, deprecated, message: "Use entry(forLine:lineStart:) with the document's line-start offset")
    public func entry(forLine line: Int) -> LineCacheEntry? {
        lock.lock()
        defer { lock.unlock() }
        
        guard line >= 0, line < lines.count, lines[line].isValid else { return nil }
        var start = 0
        for i in 0..<line { start += Int(lines[i].length) + 1 }
        return makeEntry(line: line, lineStart: start)
    }
    
    /// Get cached entry for a line, materialising absolute token offsets from `lineStart`
    /// (the UTF-16 offset of the first character of `line` in the document).
    public func entry(forLine line: Int, lineStart: Int) -> LineCacheEntry? {
        lock.lock()
        defer { lock.unlock() }
        
        guard line >= 0, line < lines.count, lines[line].isValid else { return nil }
        return makeEntry(line: line, lineStart: lineStart)
    }
    
    private func makeEntry(line: Int, lineStart: Int) -> LineCacheEntry {
        let compact = lines[line]
        var tokens: [SyntaxToken] = []
        tokens.reserveCapacity(compact.tokens.count)
        compact.materialize(line: line, lineStart: lineStart, into: &tokens)
        return LineCacheEntry(lineContent: "", tokens: tokens, startState: compact.startLexerState, endState: compact.endLexerState)
    }
    
    /// Store cache entry for a line
    public func setEntry(_ entry: LineCacheEntry, forLine line: Int) {
        lock.lock()
        defer { lock.unlock() }
        storeEntry(entry, forLine: line)
    }
    
    /// Store multiple cache entries in a single lock acquisition (eliminates thousands of per-line lock round-trips)
    public func setEntriesBatch(_ entries: [(line: Int, entry: LineCacheEntry)]) {
        guard !entries.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        for (line, entry) in entries {
            storeEntry(entry, forLine: line)
        }
    }
    
    /// Must be called with `lock` held.
    private func storeEntry(_ entry: LineCacheEntry, forLine line: Int) {
        guard line >= 0 else { return }
        if line >= lines.count {
            lines.append(contentsOf: repeatElement(CompactLine.placeholder, count: line + 1 - lines.count))
        }
        let tokens = entry.tokens
        var compact = CompactLine.make(
            line: entry.lineContent,
            lineLength: entry.lineContent.utf16.count,
            tokens: tokens,
            startState: entry.startState,
            endState: entry.endState
        )
        compact.isValid = entry.isValid
        lines[line] = compact
    }
    
    /// Get all cached tokens (if fully cached).
    /// Offsets are derived from the cached per-line lengths, which is exact only while no dirty regions are pending.
    /// Prefer `allSyntaxTokens(lineStarts:)` when the document's line-start table is at hand.
    public func allSyntaxTokens() -> [SyntaxToken] {
        lock.lock()
        defer { lock.unlock() }
        
        var tokens: [SyntaxToken] = []
        var start = 0
        for (line, entry) in lines.enumerated() {
            if entry.isValid {
                entry.materialize(line: line, lineStart: start, into: &tokens)
            }
            start += Int(entry.length) + 1
        }
        return tokens
    }
    
    /// Get all cached tokens, materialising absolute offsets from `lineStarts`
    /// (`lineStarts[i]` = UTF-16 offset of the first character of line `i`).
    public func allSyntaxTokens(lineStarts: [Int]) -> [SyntaxToken] {
        lock.lock()
        defer { lock.unlock() }
        return materializeTokens(fromLine: 0, toLine: lines.count - 1, lineStarts: lineStarts)
    }
    
    /// Materialise the tokens of lines `startLine...endLine` (inclusive) with absolute offsets.
    /// Cost is O(tokens in the requested range), independent of document size.
    public func tokens(fromLine startLine: Int, toLine endLine: Int, lineStarts: [Int]) -> [SyntaxToken] {
        lock.lock()
        defer { lock.unlock() }
        return materializeTokens(fromLine: startLine, toLine: endLine, lineStarts: lineStarts)
    }
    
    /// Must be called with `lock` held.
    private func materializeTokens(fromLine startLine: Int, toLine endLine: Int, lineStarts: [Int]) -> [SyntaxToken] {
        let first = max(0, startLine)
        let last = min(endLine, lines.count - 1, lineStarts.count - 1)
        guard first <= last else { return [] }
        
        var estimate = 0
        for line in first...last where lines[line].isValid { estimate += lines[line].tokens.count }
        var tokens: [SyntaxToken] = []
        tokens.reserveCapacity(estimate)
        for line in first...last where lines[line].isValid {
            lines[line].materialize(line: line, lineStart: lineStarts[line], into: &tokens)
        }
        return tokens
    }
    
    // MARK: - Internal Line Access (used by IncrementalLexer)
    
    /// End state of `line` if it holds a valid entry.
    func validEndState(ofLine line: Int) -> SyntaxLexerState? {
        lock.lock()
        defer { lock.unlock() }
        guard line >= 0, line < lines.count, lines[line].isValid else { return nil }
        return lines[line].endLexerState
    }
    
    /// Start state of `line` if it holds a valid entry.
    func validStartState(ofLine line: Int) -> SyntaxLexerState? {
        lock.lock()
        defer { lock.unlock() }
        guard line >= 0, line < lines.count, lines[line].isValid else { return nil }
        return lines[line].startLexerState
    }
    
    /// UTF-16 length of a (valid or stale) cached line.
    func cachedLength(ofLine line: Int) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard line >= 0, line < lines.count else { return nil }
        return Int(lines[line].length)
    }
    
    /// Commit freshly tokenized lines starting at `startLine` in one lock acquisition.
    func commit(_ newLines: [CompactLine], fromLine startLine: Int) {
        guard !newLines.isEmpty, startLine >= 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        let end = startLine + newLines.count
        if end > lines.count {
            lines.append(contentsOf: repeatElement(CompactLine.placeholder, count: end - lines.count))
        }
        lines.replaceSubrange(startLine..<end, with: newLines)
    }
    
    /// Replace the whole cache content with `newLines` (cold open).
    func replaceAll(_ newLines: [CompactLine]) {
        lock.lock()
        defer { lock.unlock() }
        lines = newLines
    }
    
    // MARK: - Dirty Tracking
    
    /// Merge `[start, end]` into the dirty list. Must be called with `lock` held.
    private func addDirtyRegion(startLine start: Int, endLine end: Int) {
        var merged = DirtyRegion(startLine: start, endLine: end)
        
        // Merge with existing regions if overlapping
        dirtyRegions = dirtyRegions.compactMap { region in
            if region.endLine >= start - 1 && region.startLine <= end + 1 {
                merged = merged.merged(with: region)
                return nil
            }
            return region
        }
        dirtyRegions.append(merged)
        
        // Invalidate cache entries in the region
        let first = max(0, start)
        let last = min(end, lines.count - 1)
        if first <= last {
            for line in first...last {
                lines[line].isValid = false
            }
        }
    }
    
    /// Mark a range of lines as dirty
    public func markDirty(fromLine start: Int, toLine end: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard end >= start else { return }
        addDirtyRegion(startLine: start, endLine: end)
    }
    
    /// Mark a single line as dirty
    public func markDirty(line: Int) {
        markDirty(fromLine: line, toLine: line)
    }
    
    /// Get and clear dirty regions (returned in ascending line order so that each region sees an up-to-date carry state)
    public func popDirtyRegions() -> [DirtyRegion] {
        lock.lock()
        defer { lock.unlock() }
        
        let regions = dirtyRegions.sorted { $0.startLine < $1.startLine }
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
    ///   - charDelta: Number of characters added (positive) or removed (negative).
    ///     Unused by the line-relative cache (offsets are never stored); kept for source compatibility.
    ///
    /// Cost: one array splice (memmove of the tail) when the line count changes, O(1) otherwise.
    /// Entries of unaffected lines are not rewritten.
    public func handleDocumentChange(changeStart: Int, linesRemoved: Int, linesAdded: Int, charDelta: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        let removed = max(0, linesRemoved)
        let added = max(0, linesAdded)
        let lineDelta = added - removed
        let start = max(0, changeStart)
        
        if lineDelta != 0 {
            // Lines in the removed range are dropped and replaced by `added` invalid placeholders.
            // Every later line keeps its entry and merely moves to a new index.
            let from = min(start, lines.count)
            let to = min(lines.count, from + removed)
            lines.replaceSubrange(from..<to, with: repeatElement(CompactLine.placeholder, count: added))
            shiftDirtyRegions(changeStart: start, removed: removed, lineDelta: lineDelta)
        }
        
        // Mark affected lines as dirty.
        // The edit touches the line it starts on and, when it spans/creates newlines, every line up to the line
        // that now holds the tail of the edit (changeStart + linesAdded). That last line is the old line
        // (changeStart + linesRemoved) whose content changed, so it must be re-lexed too.
        addDirtyRegion(startLine: start, endLine: start + added)
    }
    
    /// Re-map already pending dirty regions after `removed` lines at `changeStart` were replaced by
    /// `removed + lineDelta` lines. Must be called with `lock` held.
    private func shiftDirtyRegions(changeStart: Int, removed: Int, lineDelta: Int) {
        guard !dirtyRegions.isEmpty else { return }
        let removedEnd = changeStart + removed
        @inline(__always) func remap(_ line: Int) -> Int {
            if line < changeStart { return line }
            if line >= removedEnd { return line + lineDelta }
            return changeStart // inside the replaced block; the edit's own dirty region covers it
        }
        dirtyRegions = dirtyRegions.compactMap { region in
            let s = remap(region.startLine)
            let e = remap(region.endLine)
            return e >= s ? DirtyRegion(startLine: s, endLine: e) : nil
        }
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
        if line >= 0, line < lines.count, lines[line].isValid, lines[line].contentHash == newContent.hashValue {
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
        
        lines.removeAll()
        dirtyRegions.removeAll()
    }
    
    /// Purge memory completely without keeping capacity
    public func purgeMemory() {
        lock.lock()
        defer { lock.unlock() }
        
        lines.removeAll(keepingCapacity: false)
        dirtyRegions.removeAll(keepingCapacity: false)
    }
    
    /// Initialize cache for a new document
    public func initialize(withLineCount count: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        lines = [CompactLine](repeating: .placeholder, count: max(0, count))
        dirtyRegions.removeAll()
        
        // Mark entire document as dirty
        if count > 0 {
            dirtyRegions.append(DirtyRegion(startLine: 0, endLine: count - 1))
        }
    }
}

// MARK: - Incremental Lexer

/// Wraps a lexer to provide incremental tokenization using a cache.
///
/// All `retokenize*` entry points accept an optional `lineStarts` table (`lineStarts[i]` = UTF-16 offset of the
/// first character of line `i`, i.e. the engine's `cachedLineOffsets`). With it, an edit costs O(dirty lines):
/// only the dirty lines are cut out of the document (`NSString.substring(with:)`) and absolute offsets are
/// materialised from the table. Without it (or if it is inconsistent with the cache / the text) the lexer
/// falls back to one O(document) scan for `"\n"` to build the table itself.
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
        // Count lines without materialising them (equivalent to `components(separatedBy: "\n").count`).
        var lineCount = 1
        for byte in document.utf8 where byte == 0x0A { lineCount += 1 }
        cache.initialize(withLineCount: lineCount)
        
        // Initial tokenization is deferred to the first retokenizeDirtyRegions call
        // This prevents blocking the main thread during document load
    }
    
    /// Full document tokenization (used for initial load)
    public func tokenizeDocument(_ document: String) -> [SyntaxToken] {
        let lines = document.components(separatedBy: "\n")
        var allSyntaxTokens: [SyntaxToken] = []
        var compactLines: [CompactLine] = []
        compactLines.reserveCapacity(lines.count)
        var currentState: SyntaxLexerState = .normal
        var currentOffset = 0
        
        for (lineNumber, line) in lines.enumerated() {
            let startState = currentState
            let (tokens, endState) = baseLexer.tokenizeLine(line, lineNumber: lineNumber, startState: startState, startOffset: currentOffset)
            
            // Cache the result (line-relative)
            let lineLength = line.utf16.count
            compactLines.append(CompactLine.make(line: line, lineLength: lineLength, tokens: tokens, startState: startState, endState: endState))
            
            allSyntaxTokens.append(contentsOf: tokens)
            currentState = endState
            currentOffset += lineLength + 1
        }
        
        cache.replaceAll(compactLines)
        return allSyntaxTokens
    }
    
    /// Incremental re-tokenization of dirty regions only
    public func retokenizeDirtyRegions(in document: String, lineStarts: [Int]? = nil) -> [SyntaxToken] {
        // ZOMBIE KILLER: Check if this task is already cancelled
        if Task.isCancelled { return [] }
        
        guard let pass = runDirtyPass(in: document, lineStarts: lineStarts) else {
            // Nothing dirty: materialise from the cache.
            if let starts = lineStarts, starts.count == cache.lineCount {
                return cache.allSyntaxTokens(lineStarts: starts)
            }
            return cache.allSyntaxTokens()
        }
        if pass.cancelled { return [] }
        return cache.allSyntaxTokens(lineStarts: pass.starts)
    }
    
    /// Result of an incremental re-tokenization pass.
    /// When `isFullDocument` is false, `tokens` and `dirtyCharRange` cover ONLY the lines that actually changed,
    /// cutting Main-Thread `NSTextStorage` attribute updates from O(entire file) down to O(1 edited line).
    public struct IncrementalHighlightUpdate: Sendable {
        public let tokens: [SyntaxToken]
        public let dirtyCharRange: NSRange?
        public let isFullDocument: Bool
    }
    
    public func retokenizeDirtyRegionsIncremental(in document: String, lineStarts: [Int]? = nil) -> IncrementalHighlightUpdate {
        if Task.isCancelled {
            return IncrementalHighlightUpdate(tokens: [], dirtyCharRange: nil, isFullDocument: false)
        }
        
        guard let pass = runDirtyPass(in: document, lineStarts: lineStarts) else {
            return IncrementalHighlightUpdate(tokens: [], dirtyCharRange: NSRange(location: 0, length: 0), isFullDocument: false)
        }
        if pass.cancelled {
            return IncrementalHighlightUpdate(tokens: [], dirtyCharRange: nil, isFullDocument: false)
        }
        
        if pass.isInitialFullPass || pass.minLine > pass.maxLine || (pass.maxLine - pass.minLine) > 80 {
            return IncrementalHighlightUpdate(
                tokens: cache.allSyntaxTokens(lineStarts: pass.starts),
                dirtyCharRange: nil,
                isFullDocument: true
            )
        }
        
        let sliceTokens = cache.tokens(fromLine: pass.minLine, toLine: pass.maxLine, lineStarts: pass.starts)
        let length = max(0, pass.maxOffset - pass.minOffset)
        return IncrementalHighlightUpdate(
            tokens: sliceTokens,
            dirtyCharRange: NSRange(location: pass.minOffset, length: length),
            isFullDocument: false
        )
    }
    
    // MARK: - Dirty Pass
    
    /// Outcome of `runDirtyPass`.
    private struct DirtyPass {
        var starts: [Int]
        var minLine = Int.max
        var maxLine = Int.min
        var minOffset = Int.max
        var maxOffset = Int.min
        var isInitialFullPass = false
        var cancelled = false
    }
    
    /// Pop the dirty regions, re-lex them against `document` and commit the result to the cache.
    /// Returns nil when nothing was dirty.
    private func runDirtyPass(in document: String, lineStarts providedStarts: [Int]?) -> DirtyPass? {
        var regions = cache.popDirtyRegions()
        guard !regions.isEmpty else { return nil }
        
        var starts: [Int]
        var computedOwnStarts = false
        if let provided = providedStarts, !provided.isEmpty, provided[0] == 0, provided.count == cache.lineCount {
            starts = provided
        } else {
            starts = Self.computeLineStarts(of: document)
            computedOwnStarts = true
        }
        
        while true {
            // The cache must mirror the document's line structure; if it drifted, rebuild it and re-lex everything.
            if starts.count != cache.lineCount {
                cache.initialize(withLineCount: starts.count)
                regions = cache.popDirtyRegions()
            }
            
            var pass = DirtyPass(starts: starts)
            let totalLines = starts.count
            pass.isInitialFullPass = regions.count == 1
                && regions[0].startLine == 0
                && regions[0].endLine >= max(0, totalLines - 1)
                && totalLines > 8
            
            // Fast Multi-Core Parallel Path for Initial Full-Document Tokenization (>= 400 lines)
            if pass.isInitialFullPass && totalLines >= 400 {
                let lines = document.components(separatedBy: "\n")
                if lines.count != starts.count {
                    starts = Self.computeLineStarts(of: lines)
                    computedOwnStarts = true
                    continue
                }
                if !retokenizeFullDocumentParallel(lines: lines, lineStarts: starts) {
                    pass.cancelled = true
                    restore(regions: regions[...])
                }
                return pass
            }
            
            let ns = document as NSString
            var layoutMismatch = false
            
            for (index, region) in regions.enumerated() {
                // ZOMBIE KILLER: Stop processing if cancelled (re-queue what was not finished)
                if Task.isCancelled {
                    restore(regions: regions[index...])
                    pass.cancelled = true
                    return pass
                }
                guard let span = retokenizeRegion(
                    startLine: region.startLine,
                    endLine: region.endLine,
                    document: ns,
                    lineStarts: starts,
                    layoutMismatch: &layoutMismatch
                ) else {
                    if layoutMismatch { break }
                    if Task.isCancelled {
                        restore(regions: regions[index...])
                        pass.cancelled = true
                        return pass
                    }
                    continue
                }
                pass.minLine = min(pass.minLine, span.startLine)
                pass.maxLine = max(pass.maxLine, span.endLine)
                pass.minOffset = min(pass.minOffset, span.startOffset)
                pass.maxOffset = max(pass.maxOffset, span.endOffset)
            }
            
            if layoutMismatch && !computedOwnStarts {
                // The supplied table disagrees with the text (e.g. separators other than "\n"): rebuild it ourselves.
                starts = Self.computeLineStarts(of: document)
                computedOwnStarts = true
                continue
            }
            return pass
        }
    }
    
    /// Put regions that were popped but not (fully) processed back, so that a cancelled pass does not lose them.
    private func restore(regions: ArraySlice<DirtyRegion>) {
        for region in regions {
            cache.markDirty(fromLine: region.startLine, toLine: region.endLine)
        }
    }
    
    /// One O(document) scan for `"\n"`: `result[i]` = UTF-16 offset of the first character of line `i`.
    static func computeLineStarts(of document: String) -> [Int] {
        var starts: [Int] = [0]
        var offset = 0
        for unit in document.utf16 {
            offset += 1
            if unit == 0x0A { starts.append(offset) }
        }
        return starts
    }
    
    /// Line starts for lines already split on `"\n"`.
    private static func computeLineStarts(of lines: [String]) -> [Int] {
        var starts = [Int](repeating: 0, count: lines.count)
        var running = 0
        for i in 0..<lines.count {
            starts[i] = running
            running += lines[i].utf16.count + 1
        }
        return starts
    }
    
    /// Multi-Core Parallel Document Lexer:
    /// Partitions `lines` into many small chunks (`workerCount * 8`) executed with `DispatchQueue.concurrentPerform`.
    /// `concurrentPerform` hands out iterations dynamically, so fast Apple-Silicon P-cores simply process more
    /// chunks than the slower E-cores (static one-chunk-per-core splits are bounded by the slowest core).
    /// Cross-chunk multiline comment/string state is reconciled afterwards and the result is committed in 1 batch lock.
    /// Returns false if the task was cancelled (nothing committed).
    private func retokenizeFullDocumentParallel(lines: [String], lineStarts: [Int]) -> Bool {
        let totalLines = lines.count
        guard totalLines > 0 else { return true }
        
        let workerCount = min(PerformanceManager.totalCores, max(2, totalLines / 200))
        let targetChunks = workerCount * 8
        let chunkSize = max(32, (totalLines + targetChunks - 1) / targetChunks)
        let chunkCount = (totalLines + chunkSize - 1) / chunkSize
        let lexer = self.baseLexer
        
        var compact = [CompactLine](repeating: .placeholder, count: totalLines)
        
        compact.withUnsafeMutableBufferPointer { buf in
            // Each iteration writes a disjoint index range, so concurrent writes through the raw address are race-free.
            let rawAddr = UInt(bitPattern: UnsafeMutableRawPointer(buf.baseAddress!))
            DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIdx in
                let start = chunkIdx * chunkSize
                let end = min(totalLines, start + chunkSize)
                guard start < end else { return }
                
                let slots = UnsafeMutablePointer<CompactLine>(bitPattern: rawAddr)!
                var state: SyntaxLexerState = .normal
                
                for lineNum in start..<end {
                    let line = lines[lineNum]
                    let (tokens, nextState) = lexer.tokenizeLine(
                        line,
                        lineNumber: lineNum,
                        startState: state,
                        startOffset: lineStarts[lineNum]
                    )
                    slots[lineNum] = CompactLine.make(
                        line: line,
                        lineLength: line.utf16.count,
                        tokens: tokens,
                        startState: state,
                        endState: nextState
                    )
                    state = nextState
                }
            }
        }
        
        if Task.isCancelled { return false }
        
        // Reconcile chunk boundaries if a multiline comment/string crossed from chunk (c - 1) into chunk c
        for chunkIdx in 1..<max(1, chunkCount) {
            let start = chunkIdx * chunkSize
            let end = min(totalLines, start + chunkSize)
            var carryState = compact[start - 1].endLexerState
            for lineNum in start..<end {
                if compact[lineNum].startLexerState == carryState {
                    break // State converged!
                }
                let line = lines[lineNum]
                let (tokens, nextState) = lexer.tokenizeLine(
                    line,
                    lineNumber: lineNum,
                    startState: carryState,
                    startOffset: lineStarts[lineNum]
                )
                compact[lineNum] = CompactLine.make(
                    line: line,
                    lineLength: line.utf16.count,
                    tokens: tokens,
                    startState: carryState,
                    endState: nextState
                )
                carryState = nextState
            }
        }
        
        cache.replaceAll(compact)
        return true
    }
    
    /// Cut line `index` (without its newline) out of `document` using the line-start table.
    /// Returns nil if the table does not describe a "\n"-separated line at that position.
    @inline(__always)
    private func extractLine(_ index: Int, from document: NSString, lineStarts: [Int]) -> String? {
        let docLength = document.length
        let start = lineStarts[index]
        let end: Int
        if index + 1 < lineStarts.count {
            end = lineStarts[index + 1] - 1
            guard start >= 0, start <= end, end < docLength, document.character(at: end) == 0x0A else { return nil }
        } else {
            end = docLength
            guard start >= 0, start <= end else { return nil }
        }
        return document.substring(with: NSRange(location: start, length: end - start))
    }
    
    /// Re-tokenize a specific region and return the actual line & UTF-16 offset span that was updated.
    /// Only the dirty lines are extracted from `document`; nothing proportional to the document size is touched.
    /// Sets `layoutMismatch` and returns nil if `lineStarts` does not match the text.
    @discardableResult
    private func retokenizeRegion(
        startLine: Int,
        endLine: Int,
        document: NSString,
        lineStarts: [Int],
        layoutMismatch: inout Bool
    ) -> (startLine: Int, endLine: Int, startOffset: Int, endOffset: Int)? {
        let totalLines = lineStarts.count
        guard startLine >= 0 && startLine < totalLines else { return nil }
        
        // Get the state from the previous line (if exists)
        var currentState: SyntaxLexerState = .normal
        if startLine > 0, let prevState = cache.validEndState(ofLine: startLine - 1) {
            currentState = prevState
        }
        
        let regionStartOffset = lineStarts[startLine]
        
        // SyntaxTokenize lines until the end state stabilizes
        var lineNumber = startLine
        var lastProcessedLine = startLine
        var regionEndOffset = regionStartOffset
        var batch: [CompactLine] = []
        batch.reserveCapacity(max(1, min(totalLines - startLine, endLine - startLine + 4)))
        
        while lineNumber < totalLines {
            // ZOMBIE KILLER: Stop processing if cancelled
            if Task.isCancelled { return nil }
            
            // Check if we've passed the dirty region
            if lineNumber > endLine {
                // If the next line is valid and the state matches what we expect, we can stop propagation.
                if let existingStartState = cache.validStartState(ofLine: lineNumber), existingStartState == currentState {
                    // Optimization: State stabilized, stop processing.
                    break
                }
            }
            
            guard let line = extractLine(lineNumber, from: document, lineStarts: lineStarts) else {
                layoutMismatch = true
                return nil
            }
            let lineLength = line.utf16.count
            let startState = currentState
            let (tokens, newEndState) = baseLexer.tokenizeLine(line, lineNumber: lineNumber, startState: startState, startOffset: lineStarts[lineNumber])
            
            batch.append(CompactLine.make(line: line, lineLength: lineLength, tokens: tokens, startState: startState, endState: newEndState))
            
            // Prepare for next line
            currentState = newEndState
            lastProcessedLine = lineNumber
            regionEndOffset = lineStarts[lineNumber] + lineLength
            lineNumber += 1
        }
        
        cache.commit(batch, fromLine: startLine)
        return (startLine, lastProcessedLine, regionStartOffset, regionEndOffset)
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
