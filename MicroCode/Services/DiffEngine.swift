import Foundation
import Combine
import SwiftUI

// Copyright © 2025 Dotmini Software. All rights reserved.

public enum HunkType {
    case addition
    case deletion
    case modification
}

public enum HunkStatus {
    case pending
    case accepted
    case rejected
}

public struct DiffHunk: Identifiable {
    public let id: UUID
    public let oldRange: Range<Int>
    public let newRange: Range<Int>
    public let oldLines: [String]
    public let newLines: [String]
    public let type: HunkType
    public var status: HunkStatus
    
    public init(id: UUID = UUID(), oldRange: Range<Int>, newRange: Range<Int>, oldLines: [String], newLines: [String], type: HunkType, status: HunkStatus = .pending) {
        self.id = id
        self.oldRange = oldRange
        self.newRange = newRange
        self.oldLines = oldLines
        self.newLines = newLines
        self.type = type
        self.status = status
    }
}

public struct DiffResult {
    public let oldContent: String
    public let newContent: String
    public var hunks: [DiffHunk]
    public let additions: Int
    public let deletions: Int
}

public struct FileDiffSession: Identifiable {
    public let id: UUID
    public let filePath: String
    public var diffResult: DiffResult
    public let timestamp: Date
    
    public init(id: UUID = UUID(), filePath: String, diffResult: DiffResult, timestamp: Date = Date()) {
        self.id = id
        self.filePath = filePath
        self.diffResult = diffResult
        self.timestamp = timestamp
    }
}

@MainActor
public class DiffEngine: ObservableObject {
    public static let shared = DiffEngine()
    
    @Published public var activeDiff: DiffResult?
    @Published public var currentHunkIndex: Int = 0
    @Published public var sessions: [FileDiffSession] = []
    
    public init() {}
    
    public func computeDiff(old: String, new: String) -> DiffResult {
        let oldLines = old.components(separatedBy: .newlines)
        let newLines = new.components(separatedBy: .newlines)
        
        let operations = myersDiff(old: oldLines, new: newLines)
        let hunks = groupOperationsIntoHunks(operations: operations, oldLines: oldLines, newLines: newLines)
        
        var additions = 0
        var deletions = 0
        
        for hunk in hunks {
            // Estimate additions and deletions purely on changes, ignoring context keeps
            // A more accurate count would iterate hunk.newLines/oldLines without context
            // But we can approximate by range differences if needed, or by counting actual changes.
        }
        
        // Count actual changes from operations
        for op in operations {
            switch op {
            case .insert: additions += 1
            case .delete: deletions += 1
            case .keep: break
            }
        }
        
        let result = DiffResult(oldContent: old, newContent: new, hunks: hunks, additions: additions, deletions: deletions)
        self.activeDiff = result
        self.currentHunkIndex = 0
        
        return result
    }
    
    public func acceptHunk(_ hunk: DiffHunk) {
        guard var diff = activeDiff, let index = diff.hunks.firstIndex(where: { $0.id == hunk.id }) else { return }
        diff.hunks[index].status = .accepted
        activeDiff = diff
    }
    
    public func rejectHunk(_ hunk: DiffHunk) {
        guard var diff = activeDiff, let index = diff.hunks.firstIndex(where: { $0.id == hunk.id }) else { return }
        diff.hunks[index].status = .rejected
        activeDiff = diff
    }
    
    public func acceptAll() {
        guard var diff = activeDiff else { return }
        for i in 0..<diff.hunks.count {
            if diff.hunks[i].status == .pending {
                diff.hunks[i].status = .accepted
            }
        }
        activeDiff = diff
    }
    
    public func rejectAll() {
        guard var diff = activeDiff else { return }
        for i in 0..<diff.hunks.count {
            if diff.hunks[i].status == .pending {
                diff.hunks[i].status = .rejected
            }
        }
        activeDiff = diff
    }
    
    public func applyDecisions() -> String {
        guard let diff = activeDiff else { return "" }
        let oldLines = diff.oldContent.components(separatedBy: .newlines)
        var resultLines: [String] = []
        
        var oldLineIndex = 0
        for hunk in diff.hunks {
            while oldLineIndex < hunk.oldRange.lowerBound {
                if oldLineIndex < oldLines.count {
                    resultLines.append(oldLines[oldLineIndex])
                }
                oldLineIndex += 1
            }
            
            switch hunk.status {
            case .accepted:
                resultLines.append(contentsOf: hunk.newLines)
            case .rejected, .pending:
                resultLines.append(contentsOf: hunk.oldLines)
            }
            oldLineIndex = hunk.oldRange.upperBound
        }
        
        while oldLineIndex < oldLines.count {
            resultLines.append(oldLines[oldLineIndex])
            oldLineIndex += 1
        }
        
        return resultLines.joined(separator: "\n")
    }
    
    public func nextHunk() {
        guard let diff = activeDiff, !diff.hunks.isEmpty else { return }
        if currentHunkIndex < diff.hunks.count - 1 {
            currentHunkIndex += 1
        }
    }
    
    public func previousHunk() {
        guard let diff = activeDiff, !diff.hunks.isEmpty else { return }
        if currentHunkIndex > 0 {
            currentHunkIndex -= 1
        }
    }
    
    // MARK: - Myers Diff Algorithm
    
    private enum Operation {
        case insert(Int, String) // index in new, element
        case delete(Int, String) // index in old, element
        case keep(Int, Int, String) // index in old, index in new, element
    }
    
    private func myersDiff(old: [String], new: [String]) -> [Operation] {
        let n = old.count
        let m = new.count
        let max = n + m
        if max == 0 { return [] }
        
        var v = [Int](repeating: 0, count: 2 * max + 1)
        var trace = [[Int]]()
        
        v[max + 1] = 0
        
        for d in 0...max {
            trace.append(v)
            for k in stride(from: -d, through: d, by: 2) {
                let index = k + max
                var x = 0
                
                if k == -d || (k != d && v[index - 1] < v[index + 1]) {
                    x = v[index + 1]
                } else {
                    x = v[index - 1] + 1
                }
                
                var y = x - k
                
                while x < n && y < m && old[x] == new[y] {
                    x += 1
                    y += 1
                }
                
                v[index] = x
                
                if x >= n && y >= m {
                    return backtrack(trace: trace, old: old, new: new, max: max)
                }
            }
        }
        return []
    }
    
    private func backtrack(trace: [[Int]], old: [String], new: [String], max: Int) -> [Operation] {
        var x = old.count
        var y = new.count
        var operations = [Operation]()
        
        for d in stride(from: trace.count - 1, through: 0, by: -1) {
            let v = trace[d]
            let k = x - y
            let index = k + max
            
            var prevK = 0
            if k == -d || (k != d && v[index - 1] < v[index + 1]) {
                prevK = k + 1
            } else {
                prevK = k - 1
            }
            
            let prevIndex = prevK + max
            let prevX = v[prevIndex]
            let prevY = prevX - prevK
            
            while x > prevX && y > prevY {
                x -= 1
                y -= 1
                operations.append(.keep(x, y, old[x]))
            }
            
            if d > 0 {
                if x == prevX {
                    y -= 1
                    operations.append(.insert(y, new[y]))
                } else {
                    x -= 1
                    operations.append(.delete(x, old[x]))
                }
            }
        }
        return operations.reversed()
    }
    
    private func groupOperationsIntoHunks(operations: [Operation], oldLines: [String], newLines: [String]) -> [DiffHunk] {
        var hunks = [DiffHunk]()
        var i = 0
        
        while i < operations.count {
            var nextChangeIdx = i
            while nextChangeIdx < operations.count {
                if case .keep = operations[nextChangeIdx] {
                    nextChangeIdx += 1
                } else {
                    break
                }
            }
            
            if nextChangeIdx == operations.count { break }
            
            let startKeepIdx = max(i, nextChangeIdx - 3)
            
            var hunkOldLines = [String]()
            var hunkNewLines = [String]()
            
            var oldStart = -1
            var newStart = -1
            var oldEnd = -1
            var newEnd = -1
            
            var hasAddition = false
            var hasDeletion = false
            
            var j = startKeepIdx
            var consecutiveKeeps = 0
            
            while j < operations.count {
                let op = operations[j]
                switch op {
                case .keep(let oldIdx, let newIdx, let val):
                    if oldStart == -1 { oldStart = oldIdx }
                    if newStart == -1 { newStart = newIdx }
                    oldEnd = oldIdx + 1
                    newEnd = newIdx + 1
                    hunkOldLines.append(val)
                    hunkNewLines.append(val)
                    if j > nextChangeIdx {
                        consecutiveKeeps += 1
                    }
                case .insert(let newIdx, let val):
                    if newStart == -1 { newStart = newIdx }
                    newEnd = newIdx + 1
                    hunkNewLines.append(val)
                    consecutiveKeeps = 0
                    hasAddition = true
                case .delete(let oldIdx, let val):
                    if oldStart == -1 { oldStart = oldIdx }
                    oldEnd = oldIdx + 1
                    hunkOldLines.append(val)
                    consecutiveKeeps = 0
                    hasDeletion = true
                }
                
                if consecutiveKeeps > 6 {
                    break
                }
                j += 1
            }
            
            if oldStart == -1 {
                oldStart = 0
                for k in j..<operations.count {
                    if case .keep(let oIdx, _, _) = operations[k] { oldStart = oIdx; break }
                    else if case .delete(let oIdx, _) = operations[k] { oldStart = oIdx; break }
                }
                oldEnd = oldStart
            }
            
            if newStart == -1 {
                newStart = 0
                for k in j..<operations.count {
                    if case .keep(_, let nIdx, _) = operations[k] { newStart = nIdx; break }
                    else if case .insert(let nIdx, _) = operations[k] { newStart = nIdx; break }
                }
                newEnd = newStart
            }
            
            while consecutiveKeeps > 3 {
                hunkOldLines.removeLast()
                hunkNewLines.removeLast()
                oldEnd -= 1
                newEnd -= 1
                consecutiveKeeps -= 1
            }
            
            let type: HunkType = (hasAddition && hasDeletion) ? .modification : (hasAddition ? .addition : .deletion)
            
            let hunk = DiffHunk(
                oldRange: oldStart..<oldEnd,
                newRange: newStart..<newEnd,
                oldLines: hunkOldLines,
                newLines: hunkNewLines,
                type: type
            )
            hunks.append(hunk)
            
            i = j - consecutiveKeeps + 3
            if i <= nextChangeIdx { i = j }
        }
        
        return hunks
    }
}
