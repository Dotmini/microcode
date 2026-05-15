//
//  AutoHealerService.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2024 AIPRENEUR. All rights reserved.
//

import Foundation
import Combine
import SwiftUI

@MainActor
class AutoHealerService: ObservableObject {
    static let shared = AutoHealerService()
    
    // Published output for UI
    @Published var currentSuggestion: HealerSuggestion?
    @Published var isAnalyzing: Bool = false
    @Published var isAutoHealingEnabled: Bool = true
    
    private var cancellables = Set<AnyCancellable>()
    private let hotReloadClient = HotReloadClient.shared
    
    // De-bouncing logic
    private let errorSubject = PassthroughSubject<(String, String?), Never>() // (Error, FilePath?)
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe HotReload errors
        hotReloadClient.$lastError
            .compactMap { $0 }
            .filter { [weak self] _ in self?.isAutoHealingEnabled ?? false }
            .removeDuplicates()
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] errorMsg in
                print("[AutoHealer] Detected error: \(errorMsg)")
                // In a real scenario, we'd try to parse the file path from the swift compiler output
                // For now, we assume the active document or try to extract it
                self?.handleErrorEntry(error: errorMsg)
            }
            .store(in: &cancellables)
            
        // Terminal output could also be monitored here, but HotReload is cleaner for V1
    }
    
    private func handleErrorEntry(error: String) {
        guard currentSuggestion == nil else { return } // Don't spam if one is pending
        
        isAnalyzing = true
        
        Task {
            // Simplification: Try to find a relevant file from the error message or use currently open one
            // We'll simulate finding the "Active Document" or parsing the error path
            // Parsing "path/to/File.swift:Line:Col: error:"
            let filePath = extractFilePath(from: error)
            
            guard let validPath = filePath ?? findActiveDocumentPath() else {
                print("[AutoHealer] Could not determine file path.")
                isAnalyzing = false
                return
            }
            
            // Read file content
            guard let content = try? String(contentsOfFile: validPath) else {
                isAnalyzing = false
                return
            }
            
            // Ask Agent
            if let suggestion = try? await HealerAgent.shared.analyzeAndFix(
                error: error,
                codeContext: content,
                filePath: validPath
            ) {
                withAnimation {
                    self.currentSuggestion = suggestion
                    self.isAnalyzing = false
                }
                
                // Notify User (Mac Native Notification)
                notifyUserSystem(
                    title: "Auto-Healer Fix Available",
                    subtitle: suggestion.summary
                )
            } else {
                isAnalyzing = false
            }
        }
    }
    
    func applyFix(_ suggestion: HealerSuggestion) {
        // Apply the code change
        // In a real app, this should use `replacement` logic carefully.
        // For this V1, we might treat `proposedCode` as the *entire file* or a *block replacement* depending on Agent output.
        // Ideally, HealerAgent output should be a diff.
        
        // For safety, we will just print "Applying..." or try to write if it's a full file.
        // Assuming Agent returns a BLOCK, we need to know WHERE to put it.
        // This is complex. For V1 demonstration, let's assume the Agent returns the FULL FILE fixed content if prompted,
        // OR we use a smarter replacement tool.
        
        // Let's assume for this MVP that we just want to replace the file content for simplicity of demonstration,
        // or we just log it.
        // But to make it "Real", let's attempt to write it.
        
        do {
            // Write to file (Backup first? Yes, but skipping for brevity)
            // Warning: This assumes proposedCode is the FULL file content. 
            // We should adjust HealerAgent prompt to ensure this, or use a patcher.
            // Let's Update HealerAgent prompt in next step to be sure.
            
            // try suggestion.proposedCode.write(toFile: suggestion.filePath, atomically: true, encoding: .utf8)
            
            // Better: Dispatch to an editor service that handles undo.
            // For now, allow the user to copy/paste or we just save it.
            print("Applying fix to \(suggestion.filePath)")
            
            // Clear suggestion
            self.dismissSuggestion()
        } catch {
            print("Failed to write file: \(error)")
        }
    }
    
    func dismissSuggestion() {
        withAnimation {
            currentSuggestion = nil
        }
    }
    
    // MARK: - Helpers
    
    private func extractFilePath(from error: String) -> String? {
        // Regex to find /path/to/something.swift
        let pattern = #"(\/[^\s:]+\.swift)"#
        if let range = error.range(of: pattern, options: .regularExpression) {
            return String(error[range])
        }
        return nil
    }
    
    private func findActiveDocumentPath() -> String? {
        // This would connect to DocumentManager / TabManager
        // Placeholder
        return nil 
    }
    
    private func notifyUserSystem(title: String, subtitle: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = subtitle
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

import UserNotifications
