//
//  HealerAgent.swift
//  MicroCode
//
//  Specialized AI Agent for Auto-Healing functionality.
//  Uses AIClient directly for streaming analysis.
//

import Foundation
import Combine
import MicroCodeSupport

@MainActor
class HealerAgent: ObservableObject {
    static let shared = HealerAgent()
    
    private let aiClient = AIClient.shared
    
    /// Analyzes a build error or runtime exception and returns a fix suggestion
    func analyzeAndFix(error: String, codeContext: String, filePath: String, aiContext: AuthenticAIContext? = nil) async throws -> HealerSuggestion? {
        var prompt = """
        I encountered a build error or runtime crash in my Swift project.
        
        File: \(filePath)
        
        Error Message:
        \(error)
        
        Code Context (around the error):
        ```swift
        \(codeContext)
        ```
        """
        
        if let ctx = aiContext {
            prompt += "\n\nSemantic Context:\n\(ctx.llmContextDescription())"
        }
        
        prompt += """
        \n
        Please analyze this error. If you can determine a fix:
        1. Explain the cause briefly.
        2. Provide the FIXED code block for the specific range.
        
        Your Goal: provide a replacement code block that fixes the issue.
        """
        
        let systemPrompt = """
        You are an expert Swift debugger and code healer.
        Your job is to fix compilation errors and bugs based on logs.
        
        Analyze the error and the code.
        If you are confident in the fix, output the following structured response:
        
        SUMMARY: <Short description of fix>
        EXPLANATION: <Why it broke and why this fixes it>
        FIX_CODE:
        ```swift
        <The complete corrected block of code>
        ```
        
        Do NOT use tools. Just analyze and provide the code.
        """
        
        // Detect provider from current app settings
        let defaults = UserDefaults.standard
        let provider = defaults.string(forKey: "aiProvider") ?? "gemini"
        let model = defaults.string(forKey: "aiModel") ?? "gemini-2.5-flash"
        let apiKey = defaults.string(forKey: "\(provider)_api_key") ?? ""
        
        let detectedProvider = StreamableAIProvider.detect(from: model)
        
        // Use non-streaming sync call
        var fullResponse = ""
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            aiClient.sendMessage(
                prompt: prompt,
                systemPrompt: systemPrompt,
                provider: detectedProvider,
                model: model,
                apiKey: apiKey,
                onToken: { _ in },
                onComplete: { text in
                    fullResponse = text
                    continuation.resume()
                },
                onError: { error in
                    fullResponse = "Error: \(error)"
                    continuation.resume()
                }
            )
        }
        
        return parseHealerResponse(fullResponse, filePath: filePath)
    }
    
    private func parseHealerResponse(_ response: String, filePath: String) -> HealerSuggestion? {
        guard response.contains("FIX_CODE:") else { return nil }
        
        var summary = "Fix detected"
        var explanation = ""
        var fixCode = ""
        
        let lines = response.components(separatedBy: .newlines)
        var parsingCode = false
        
        for line in lines {
            if line.starts(with: "SUMMARY:") {
                summary = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            } else if line.starts(with: "EXPLANATION:") {
                explanation = String(line.dropFirst(12)).trimmingCharacters(in: .whitespaces)
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("```swift") {
                parsingCode = true
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") && parsingCode {
                parsingCode = false
            } else if parsingCode {
                fixCode += line + "\n"
            }
        }
        
        guard !fixCode.isEmpty else { return nil }
        
        return HealerSuggestion(
            id: UUID(),
            summary: summary,
            explanation: explanation,
            filePath: filePath,
            originalError: "Error detected in file",
            proposedCode: fixCode
        )
    }
}

struct HealerSuggestion: Identifiable, Equatable {
    let id: UUID
    let summary: String
    let explanation: String
    let filePath: String
    let originalError: String
    let proposedCode: String
}
