// Copyright © 2025 Dotmini Software. All rights reserved.

import Foundation
import Combine
import SwiftUI

/// Represents a specific point where an edit is predicted
public struct EditPoint: Identifiable, Equatable, Codable {
    public var id = UUID()
    public let line: Int
    public let column: Int
    public let suggestedContent: String
    public let confidenceScore: Double
    public let priority: Int
    public let reason: String
    
    enum CodingKeys: String, CodingKey {
        case line, column, suggestedContent, confidenceScore, priority, reason
    }
    
    public init(line: Int, column: Int, suggestedContent: String, confidenceScore: Double, priority: Int, reason: String) {
        self.line = line
        self.column = column
        self.suggestedContent = suggestedContent
        self.confidenceScore = confidenceScore
        self.priority = priority
        self.reason = reason
    }
}

/// A collection of EditPoints for a prediction session
public struct SuperTabPrediction: Equatable {
    public let points: [EditPoint]
    
    public init(points: [EditPoint]) {
        self.points = points.sorted { 
            if $0.line == $1.line {
                return $0.column < $1.column
            }
            return $0.line < $1.line
        }
    }
}

/// Visual marker for UI rendering
public struct EditPointMarker: Identifiable, Equatable {
    public var id: UUID { editPoint.id }
    public let editPoint: EditPoint
    public let isCurrent: Bool
}

public enum SuperTabError: LocalizedError {
    case invalidResponse
    case parsingError
    
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from AI model"
        case .parsingError: return "Failed to parse AI predictions"
        }
    }
}

@MainActor
public class SuperTabEngine: ObservableObject {
    public static let shared = SuperTabEngine()
    
    @Published public private(set) var currentEditPoint: EditPoint?
    @Published public private(set) var allPredictions: [EditPoint] = []
    @Published public private(set) var isActive: Bool = false
    @Published public private(set) var currentIndex: Int = 0
    
    private var predictionTask: Task<Void, Never>?
    private var debounceTimer: AnyCancellable?
    
    private init() {}
    
    /// Triggers prediction with debouncing
    public func triggerPrediction(content: String, cursorLine: Int, cursorColumn: Int, fileExtension: String) {
        debounceTimer?.cancel()
        
        // Cancel existing active prediction cycle if the cursor moved outside the current edit point
        if isActive, let current = currentEditPoint {
            if cursorLine != current.line {
                dismiss()
            }
        }
        
        debounceTimer = Just(())
            .delay(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.performPrediction(content: content, cursorLine: cursorLine, cursorColumn: cursorColumn, fileExtension: fileExtension)
            }
    }
    
    private func performPrediction(content: String, cursorLine: Int, cursorColumn: Int, fileExtension: String) {
        predictionTask?.cancel()
        
        predictionTask = Task {
            do {
                isActive = true
                
                // Extract context window: 2000 chars before, 1000 after
                let (prefix, suffix) = extractContext(content: content, line: cursorLine, column: cursorColumn)
                
                let predictions = try await fetchPredictions(prefix: prefix, suffix: suffix, extension: fileExtension)
                
                guard !Task.isCancelled else { return }
                
                if !predictions.isEmpty {
                    self.allPredictions = SuperTabPrediction(points: predictions).points
                    self.currentIndex = 0
                    self.currentEditPoint = self.allPredictions.first
                } else {
                    dismiss()
                }
            } catch {
                if !Task.isCancelled {
                    dismiss()
                    print("SuperTabEngine error: \(error)")
                }
            }
        }
    }
    
    /// Accept the current prediction and advance to the next one
    public func acceptCurrentAndAdvance() -> EditPoint? {
        guard isActive, let accepted = currentEditPoint else { return nil }
        
        currentIndex += 1
        if currentIndex < allPredictions.count {
            currentEditPoint = allPredictions[currentIndex]
        } else {
            dismiss()
        }
        
        return accepted
    }
    
    /// Clear all predictions and hide UI
    public func dismiss() {
        predictionTask?.cancel()
        isActive = false
        allPredictions = []
        currentEditPoint = nil
        currentIndex = 0
    }
    
    /// Get markers for visual rendering in the editor
    public func getMarkers() -> [EditPointMarker] {
        guard isActive else { return [] }
        return allPredictions.map { EditPointMarker(editPoint: $0, isCurrent: $0.id == currentEditPoint?.id) }
    }
    
    private func fetchPredictions(prefix: String, suffix: String, extension fileExtension: String) async throws -> [EditPoint] {
        let systemPrompt = """
        You are an advanced code prediction engine. Analyze the provided code context and predict the NEXT 2-5 locations where the user is likely to edit or add code.
        For each prediction, provide the line number, column number, suggested text, confidence score (0.0 to 1.0), priority (1 is highest), and a brief reason.
        
        Respond ONLY with a JSON array of predictions matching this structure:
        [
            {
                "line": Int,
                "column": Int,
                "suggestedContent": "String",
                "confidenceScore": Double,
                "priority": Int,
                "reason": "String"
            }
        ]
        """
        
        let userPrompt = """
        File extension: \(fileExtension)
        
        Code before cursor:
        ```
        \(prefix)
        ```
        
        Code after cursor:
        ```
        \(suffix)
        ```
        """
        
        let messages = [
            (role: "system", content: systemPrompt),
            (role: "user", content: userPrompt)
        ]
        
        // Use LocalLLMService for provider and model defaults if available
        let provider = LocalLLMService.shared.activeEndpoint ?? "anthropic"
        let model = LocalLLMService.shared.activeModel ?? "claude-3-5-sonnet-20240620"
        
        let stream = try await AIClient.shared.streamCompletion(
            messages: messages,
            model: model,
            provider: provider,
            tools: nil,
            stream: false
        )
        
        var jsonString = ""
        for try await chunk in stream {
            jsonString += chunk
        }
        
        // Clean up JSON payload if wrapped in markdown
        if jsonString.hasPrefix("```json") {
            jsonString = jsonString.replacingOccurrences(of: "```json", with: "")
            jsonString = jsonString.replacingOccurrences(of: "```", with: "")
        } else if jsonString.hasPrefix("```") {
            jsonString = jsonString.replacingOccurrences(of: "```", with: "")
        }
        
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = jsonString.data(using: .utf8) else {
            throw SuperTabError.parsingError
        }
        
        let decoder = JSONDecoder()
        do {
            let points = try decoder.decode([EditPoint].self, from: data)
            return points
        } catch {
            print("Failed to decode SuperTab response: \(error)")
            throw SuperTabError.parsingError
        }
    }
    
    private func extractContext(content: String, line: Int, column: Int) -> (String, String) {
        let lines = content.components(separatedBy: .newlines)
        
        var charIndex = 0
        for (i, l) in lines.enumerated() {
            if i < line {
                charIndex += l.count + 1 // +1 for newline character
            } else if i == line {
                charIndex += min(column, l.count)
                break
            }
        }
        
        let prefixStart = max(0, charIndex - 2000)
        let suffixEnd = min(content.count, charIndex + 1000)
        
        let prefixStartIdx = content.index(content.startIndex, offsetBy: prefixStart, limitedBy: content.endIndex) ?? content.startIndex
        let charIdx = content.index(content.startIndex, offsetBy: charIndex, limitedBy: content.endIndex) ?? content.endIndex
        let suffixEndIdx = content.index(content.startIndex, offsetBy: suffixEnd, limitedBy: content.endIndex) ?? content.endIndex
        
        let prefix = String(content[prefixStartIdx..<charIdx])
        let suffix = String(content[charIdx..<suffixEndIdx])
        
        return (prefix, suffix)
    }
}
