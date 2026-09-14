//
//  CRDTEngine.swift
//  MicroCode
//
//  CRDT (Conflict-free Replicated Data Type) Engine
//  RGA-based real-time text synchronization for collaborative editing
//
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Version Vector

/// Dictionary of [siteId: clock] for causal ordering across collaborative peers
typealias VersionVector = [String: Int]

extension Dictionary where Key == String, Value == Int {
    /// Returns the logical clock for a given site ID or 0 if not yet registered
    func getClock(for siteId: String) -> Int {
        self[siteId] ?? 0
    }
    
    /// Increments the clock for a site ID and returns the incremented clock value
    mutating func increment(for siteId: String) -> Int {
        let next = (self[siteId] ?? 0) + 1
        self[siteId] = next
        return next
    }
    
    /// Updates the clock for a site ID if the new clock value is greater
    mutating func updateMax(siteId: String, clock: Int) {
        self[siteId] = Swift.max(self[siteId] ?? 0, clock)
    }
    
    /// Returns true if this version vector dominates (subsumes or equals) another
    func dominates(_ other: VersionVector) -> Bool {
        for (site, clock) in other {
            if (self[site] ?? 0) < clock {
                return false
            }
        }
        return true
    }
    
    /// Merges two version vectors by computing the component-wise maximum
    func merged(with other: VersionVector) -> VersionVector {
        var result = self
        for (site, clock) in other {
            result[site] = Swift.max(result[site] ?? 0, clock)
        }
        return result
    }
}

// MARK: - CRDT Character

/// Represents a single character node in the Replicated Growable Array (RGA)
struct CRDTChar: Identifiable, Codable, Equatable, Sendable {
    /// Unique Lamport identifier formatted as "\(siteId):\(clock)"
    let id: String
    /// The character value
    let value: Character
    /// The originating site identifier
    let siteId: String
    /// The Lamport timestamp clock value
    let clock: Int
    /// The ID of the preceding character when this character was inserted, or nil if at start
    var positionIdentifier: String?
    /// Tombstone marker: marked true upon deletion rather than physical removal
    var isDeleted: Bool
    
    private enum CodingKeys: String, CodingKey {
        case id, value, siteId, clock, positionIdentifier, isDeleted
    }
    
    init(
        id: String? = nil,
        value: Character,
        siteId: String,
        clock: Int,
        positionIdentifier: String? = nil,
        isDeleted: Bool = false
    ) {
        self.id = id ?? "\(siteId):\(clock)"
        self.value = value
        self.siteId = siteId
        self.clock = clock
        self.positionIdentifier = positionIdentifier
        self.isDeleted = isDeleted
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        let valueStr = try container.decode(String.self, forKey: .value)
        self.value = valueStr.first ?? " "
        self.siteId = try container.decode(String.self, forKey: .siteId)
        self.clock = try container.decode(Int.self, forKey: .clock)
        self.positionIdentifier = try container.decodeIfPresent(String.self, forKey: .positionIdentifier)
        self.isDeleted = try container.decode(Bool.self, forKey: .isDeleted)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(String(value), forKey: .value)
        try container.encode(siteId, forKey: .siteId)
        try container.encode(clock, forKey: .clock)
        try container.encodeIfPresent(positionIdentifier, forKey: .positionIdentifier)
        try container.encode(isDeleted, forKey: .isDeleted)
    }
}

// MARK: - CRDT Operation

/// Atomically synchronizable operation for RGA text editing
enum CRDTOperation: Codable, Equatable, Sendable {
    case insert(position: Int, char: Character, siteId: String, clock: Int)
    case delete(position: Int, siteId: String, clock: Int)
    
    var position: Int {
        switch self {
        case .insert(let pos, _, _, _): return pos
        case .delete(let pos, _, _): return pos
        }
    }
    
    var siteId: String {
        switch self {
        case .insert(_, _, let site, _): return site
        case .delete(_, let site, _): return site
        }
    }
    
    var clock: Int {
        switch self {
        case .insert(_, _, _, let clk): return clk
        case .delete(_, _, let clk): return clk
        }
    }
    
    var isInsert: Bool {
        switch self {
        case .insert: return true
        case .delete: return false
        }
    }
    
    var isDelete: Bool {
        switch self {
        case .insert: return false
        case .delete: return true
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type, position, char, siteId, clock
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let position = try container.decode(Int.self, forKey: .position)
        let siteId = try container.decode(String.self, forKey: .siteId)
        let clock = try container.decode(Int.self, forKey: .clock)
        
        switch type {
        case "insert":
            let charStr = try container.decode(String.self, forKey: .char)
            guard let char = charStr.first else {
                throw DecodingError.dataCorruptedError(forKey: .char, in: container, debugDescription: "Empty character in insert operation")
            }
            self = .insert(position: position, char: char, siteId: siteId, clock: clock)
        case "delete":
            self = .delete(position: position, siteId: siteId, clock: clock)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown operation type: \(type)")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .insert(let position, let char, let siteId, let clock):
            try container.encode("insert", forKey: .type)
            try container.encode(position, forKey: .position)
            try container.encode(String(char), forKey: .char)
            try container.encode(siteId, forKey: .siteId)
            try container.encode(clock, forKey: .clock)
        case .delete(let position, let siteId, let clock):
            try container.encode("delete", forKey: .type)
            try container.encode(position, forKey: .position)
            try container.encode(siteId, forKey: .siteId)
            try container.encode(clock, forKey: .clock)
        }
    }
}

// MARK: - CRDT Document

/// Collaborative document containing replicated character structures and causal metadata
struct CRDTDocument: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var filePath: String?
    var characters: [CRDTChar]
    var versionVector: VersionVector
    var lamportClock: Int
    
    init(
        id: String = UUID().uuidString,
        filePath: String? = nil,
        characters: [CRDTChar] = [],
        versionVector: VersionVector = [:],
        lamportClock: Int = 0
    ) {
        self.id = id
        self.filePath = filePath
        self.characters = characters
        self.versionVector = versionVector
        self.lamportClock = lamportClock
    }
    
    /// Plain text extracted from all non-deleted visible characters
    var text: String {
        String(characters.filter { !$0.isDeleted }.map { $0.value })
    }
    
    /// Array of currently visible (non-tombstoned) characters
    var visibleCharacters: [CRDTChar] {
        characters.filter { !$0.isDeleted }
    }
    
    /// Count of currently visible characters
    var visibleCount: Int {
        characters.reduce(0) { $0 + ($1.isDeleted ? 0 : 1) }
    }
    
    /// Maps a 0-based visible index to the underlying index in the characters array
    func arrayIndex(forVisibleIndex visibleIndex: Int) -> Int? {
        guard visibleIndex >= 0 else { return nil }
        var current = 0
        for (idx, char) in characters.enumerated() {
            if !char.isDeleted {
                if current == visibleIndex {
                    return idx
                }
                current += 1
            }
        }
        if visibleIndex == current {
            return characters.count
        }
        return nil
    }
    
    /// Returns the character ID at the given visible index
    func charId(atVisibleIndex visibleIndex: Int) -> String? {
        let visible = visibleCharacters
        guard visibleIndex >= 0 && visibleIndex < visible.count else { return nil }
        return visible[visibleIndex].id
    }
    
    /// Returns the visible index for a character with the given ID
    func visibleIndex(forCharId id: String) -> Int? {
        var current = 0
        for char in characters {
            if char.id == id {
                return char.isDeleted ? nil : current
            }
            if !char.isDeleted {
                current += 1
            }
        }
        return nil
    }
}

// MARK: - CRDT Engine Error

enum CRDTEngineError: LocalizedError {
    case deserializationFailed
    case invalidPosition(Int)
    case documentNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .deserializationFailed:
            return "Failed to deserialize CRDT operation from data."
        case .invalidPosition(let pos):
            return "CRDT position out of bounds: \(pos)."
        case .documentNotFound(let id):
            return "CRDT document not found with ID: \(id)."
        }
    }
}

// MARK: - CRDT Engine Service

@MainActor
class CRDTEngine: ObservableObject {
    static let shared = CRDTEngine()
    
    // MARK: - Published Properties
    
    @Published var isActive: Bool = false
    @Published var peerCount: Int = 0
    @Published var pendingOps: Int = 0
    @Published var localSiteId: String = UUID().uuidString
    @Published var documents: [String: CRDTDocument] = [:]
    
    private var pendingOperationsQueue: [CRDTOperation] = []
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(siteId: String? = nil) {
        if let siteId = siteId {
            self.localSiteId = siteId
        }
    }
    
    // MARK: - Document Creation & Text Extraction
    
    /// Initializes a collaborative CRDTDocument from existing text
    func createDocument(
        content: String,
        filePath: String? = nil,
        id: String = UUID().uuidString
    ) -> CRDTDocument {
        let site = localSiteId
        var chars: [CRDTChar] = []
        chars.reserveCapacity(content.count)
        var prevId: String? = nil
        var clock = 0
        
        for char in content {
            clock += 1
            let charId = "\(site):\(clock)"
            let crdtChar = CRDTChar(
                id: charId,
                value: char,
                siteId: site,
                clock: clock,
                positionIdentifier: prevId,
                isDeleted: false
            )
            chars.append(crdtChar)
            prevId = charId
        }
        
        var vector: VersionVector = [:]
        if clock > 0 {
            vector[site] = clock
        }
        
        let doc = CRDTDocument(
            id: id,
            filePath: filePath,
            characters: chars,
            versionVector: vector,
            lamportClock: clock
        )
        
        documents[id] = doc
        return doc
    }
    
    /// Extracts plain text from the document
    func getText(from document: CRDTDocument) -> String {
        document.text
    }
    
    // MARK: - Operation Generation
    
    /// Generates a local insert operation at a specified visible position
    func generateInsert(
        at position: Int,
        char: Character,
        in document: CRDTDocument
    ) -> CRDTOperation {
        let currentClock = Swift.max(document.lamportClock, document.versionVector.getClock(for: localSiteId))
        let nextClock = currentClock + 1
        let clampedPosition = Swift.max(0, Swift.min(position, document.visibleCount))
        return CRDTOperation.insert(
            position: clampedPosition,
            char: char,
            siteId: localSiteId,
            clock: nextClock
        )
    }
    
    /// Generates a local delete operation at a specified visible position
    func generateDelete(
        at position: Int,
        in document: CRDTDocument
    ) -> CRDTOperation {
        let currentClock = Swift.max(document.lamportClock, document.versionVector.getClock(for: localSiteId))
        let nextClock = currentClock + 1
        let maxPos = Swift.max(0, document.visibleCount - 1)
        let clampedPosition = Swift.max(0, Swift.min(position, maxPos))
        return CRDTOperation.delete(
            position: clampedPosition,
            siteId: localSiteId,
            clock: nextClock
        )
    }
    
    // MARK: - Operation Application
    
    /// Applies a local edit to the document
    func applyLocal(operation: CRDTOperation, to document: inout CRDTDocument) {
        switch operation {
        case .insert(let position, let char, let siteId, let clock):
            document.lamportClock = Swift.max(document.lamportClock, clock)
            document.versionVector.updateMax(siteId: siteId, clock: clock)
            
            let visible = document.visibleCharacters
            let anchorId: String?
            let insertIndex: Int
            
            if position <= 0 {
                anchorId = nil
                insertIndex = 0
            } else if position - 1 < visible.count {
                let anchor = visible[position - 1]
                anchorId = anchor.id
                let idx = document.characters.firstIndex(where: { $0.id == anchor.id }) ?? (document.characters.count - 1)
                insertIndex = idx + 1
            } else if let last = document.characters.last {
                anchorId = last.id
                insertIndex = document.characters.count
            } else {
                anchorId = nil
                insertIndex = 0
            }
            
            let newChar = CRDTChar(
                id: "\(siteId):\(clock)",
                value: char,
                siteId: siteId,
                clock: clock,
                positionIdentifier: anchorId,
                isDeleted: false
            )
            
            let safeIndex = Swift.min(insertIndex, document.characters.count)
            document.characters.insert(newChar, at: safeIndex)
            
        case .delete(let position, let siteId, let clock):
            document.lamportClock = Swift.max(document.lamportClock, clock)
            document.versionVector.updateMax(siteId: siteId, clock: clock)
            
            let visible = document.visibleCharacters
            guard position >= 0 && position < visible.count else { return }
            let target = visible[position]
            if let idx = document.characters.firstIndex(where: { $0.id == target.id }) {
                document.characters[idx].isDeleted = true
            }
        }
        
        if documents[document.id] != nil {
            documents[document.id] = document
        }
    }
    
    /// Merges a remote edit with conflict resolution (Lamport timestamp + site ID total ordering)
    func applyRemote(operation: CRDTOperation, to document: inout CRDTDocument) {
        switch operation {
        case .insert(let position, let char, let siteId, let clock):
            // Idempotency check: ignore already applied characters
            if document.characters.contains(where: { $0.clock == clock && $0.siteId == siteId }) {
                return
            }
            
            document.lamportClock = Swift.max(document.lamportClock, clock)
            document.versionVector.updateMax(siteId: siteId, clock: clock)
            
            let visible = document.visibleCharacters
            let anchorId: String?
            let anchorIndex: Int
            
            if position <= 0 {
                anchorId = nil
                anchorIndex = -1
            } else if position - 1 < visible.count {
                let anchor = visible[position - 1]
                anchorId = anchor.id
                anchorIndex = document.characters.firstIndex(where: { $0.id == anchor.id }) ?? -1
            } else if let last = document.characters.last {
                anchorId = last.id
                anchorIndex = document.characters.count - 1
            } else {
                anchorId = nil
                anchorIndex = -1
            }
            
            let newChar = CRDTChar(
                id: "\(siteId):\(clock)",
                value: char,
                siteId: siteId,
                clock: clock,
                positionIdentifier: anchorId,
                isDeleted: false
            )
            
            var insertIndex = anchorIndex + 1
            var skippedIds = Set<String>()
            
            // Replicated Growable Array (RGA) conflict resolution scan
            while insertIndex < document.characters.count {
                let existing = document.characters[insertIndex]
                
                // If existing character was inserted after the exact same anchor
                if existing.positionIdentifier == anchorId {
                    if comparePriority(clock1: clock, siteId1: siteId, clock2: existing.clock, siteId2: existing.siteId) {
                        // Incoming has higher priority -> insert here before existing
                        break
                    } else {
                        // Existing has higher priority -> skip existing and its child descendants
                        skippedIds.insert(existing.id)
                        insertIndex += 1
                        continue
                    }
                }
                
                // If existing is a child descendant of a character we skipped
                if let parentId = existing.positionIdentifier, skippedIds.contains(parentId) {
                    skippedIds.insert(existing.id)
                    insertIndex += 1
                    continue
                }
                
                // Reached an unrelated element boundary
                break
            }
            
            let safeIndex = Swift.min(insertIndex, document.characters.count)
            document.characters.insert(newChar, at: safeIndex)
            
        case .delete(let position, let siteId, let clock):
            document.lamportClock = Swift.max(document.lamportClock, clock)
            document.versionVector.updateMax(siteId: siteId, clock: clock)
            
            let visible = document.visibleCharacters
            guard position >= 0 && position < visible.count else { return }
            let target = visible[position]
            if let idx = document.characters.firstIndex(where: { $0.id == target.id }) {
                document.characters[idx].isDeleted = true
            }
        }
        
        if documents[document.id] != nil {
            documents[document.id] = document
        }
    }
    
    // MARK: - Conflict Resolution
    
    /// Total ordering comparator using Lamport timestamps with site ID tie-breaker
    /// Returns true if (clock1, siteId1) has strictly higher precedence than (clock2, siteId2)
    func comparePriority(clock1: Int, siteId1: String, clock2: Int, siteId2: String) -> Bool {
        if clock1 != clock2 {
            return clock1 > clock2
        }
        return siteId1 > siteId2
    }
    
    // MARK: - Serialization
    
    /// Serializes a CRDTOperation to binary Data
    func serialize(operation: CRDTOperation) -> Data {
        do {
            let encoder = JSONEncoder()
            return try encoder.encode(operation)
        } catch {
            return Data()
        }
    }
    
    /// Deserializes binary Data into a CRDTOperation, returning nil if data is malformed
    func deserialize(data: Data) -> CRDTOperation? {
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(CRDTOperation.self, from: data)
        } catch {
            return nil
        }
    }
    
    /// Deserializes binary Data into a CRDTOperation with explicit error throwing
    func deserializeOrThrow(data: Data) throws -> CRDTOperation {
        let decoder = JSONDecoder()
        return try decoder.decode(CRDTOperation.self, from: data)
    }
    
    // MARK: - CollaborationService Integration
    
    /// Converts line and column coordinates into a 0-based character offset within plain text
    func characterOffset(in text: String, line: Int, column: Int) -> Int {
        let lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else { return 0 }
        
        let zeroBasedLine = line > 0 ? line - 1 : line
        let clampedLine = Swift.max(0, Swift.min(zeroBasedLine, lines.count - 1))
        
        var offset = 0
        for i in 0..<clampedLine {
            offset += lines[i].count + 1 // +1 for the newline character
        }
        
        let lineContent = lines[clampedLine]
        let zeroBasedCol = column > 0 ? column - 1 : column
        let clampedCol = Swift.max(0, Swift.min(zeroBasedCol, lineContent.count))
        offset += clampedCol
        
        return Swift.min(offset, text.count)
    }
    
    /// Converts a character offset to 1-based line and column coordinates
    func lineAndColumn(in text: String, offset: Int) -> (line: Int, column: Int) {
        let clampedOffset = Swift.max(0, Swift.min(offset, text.count))
        let prefix = String(text.prefix(clampedOffset))
        let lines = prefix.components(separatedBy: "\n")
        let line = lines.count
        let column = (lines.last?.count ?? 0) + 1
        return (line, column)
    }
    
    /// Transforms a CollaborationMessage.TextChange into an equivalent sequence of CRDTOperations
    func transformTextChange(
        _ change: CollaborationMessage.TextChange,
        in document: CRDTDocument
    ) -> [CRDTOperation] {
        let text = getText(from: document)
        let startOffset = characterOffset(in: text, line: change.startLine, column: change.startColumn)
        let endOffset = characterOffset(in: text, line: change.endLine, column: change.endColumn)
        
        var ops: [CRDTOperation] = []
        var simDoc = document
        
        // 1. Generate delete operations for the replaced text range
        let deleteCount = Swift.max(0, endOffset - startOffset)
        for _ in 0..<deleteCount {
            let delOp = generateDelete(at: startOffset, in: simDoc)
            ops.append(delOp)
            applyLocal(operation: delOp, to: &simDoc)
        }
        
        // 2. Generate insert operations for incoming new characters
        var insertPos = startOffset
        for char in change.text {
            let insOp = generateInsert(at: insertPos, char: char, in: simDoc)
            ops.append(insOp)
            applyLocal(operation: insOp, to: &simDoc)
            insertPos += 1
        }
        
        return ops
    }
    
    /// Applies a CollaborationMessage.TextChange to a document and returns the generated CRDT operations
    @discardableResult
    func applyTextChange(
        _ change: CollaborationMessage.TextChange,
        to document: inout CRDTDocument
    ) -> [CRDTOperation] {
        let ops = transformTextChange(change, in: document)
        for op in ops {
            applyLocal(operation: op, to: &document)
        }
        return ops
    }
    
    // MARK: - Session & Queue Management
    
    /// Starts a collaboration session with an optional custom site ID
    func startSession(siteId: String? = nil) {
        if let siteId = siteId {
            self.localSiteId = siteId
        }
        self.isActive = true
    }
    
    /// Stops the active collaboration session and clears transient state
    func stopSession() {
        self.isActive = false
        self.peerCount = 0
        self.pendingOps = 0
        self.pendingOperationsQueue.removeAll()
    }
    
    /// Updates the connected peer count
    func updatePeerCount(_ count: Int) {
        self.peerCount = Swift.max(0, count)
    }
    
    /// Appends an operation to the pending queue
    func queueOperation(_ op: CRDTOperation) {
        pendingOperationsQueue.append(op)
        pendingOps = pendingOperationsQueue.count
    }
    
    /// Flushes and returns all currently queued pending operations
    func flushPendingOperations() -> [CRDTOperation] {
        let ops = pendingOperationsQueue
        pendingOperationsQueue.removeAll()
        pendingOps = 0
        return ops
    }
    
    /// Clears any pending operations
    func clearPendingOperations() {
        pendingOperationsQueue.removeAll()
        pendingOps = 0
    }
    
    /// Retrieves a document by its ID
    func document(for id: String) -> CRDTDocument? {
        documents[id]
    }
    
    /// Registers or updates a document
    func setDocument(_ document: CRDTDocument, for id: String) {
        documents[id] = document
    }
    
    /// Removes a document from local memory
    func removeDocument(for id: String) {
        documents.removeValue(forKey: id)
    }
}
