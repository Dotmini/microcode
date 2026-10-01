//
//  GoogleColabKernel.swift
//  MicroCode
//
//  ComputeKernel implementation for Google Colab Cloud GPU/TPU.
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import Foundation

class GoogleColabKernel: ComputeKernel {
    let id = UUID().uuidString
    let target: ComputeTarget = .googleColab
    var state: ComputeKernelState = .idle
    
    func start() async throws {
        state = .starting
        state = .idle
    }
    
    func stop() async throws {
        state = .stopping
        await MainActor.run {
            GoogleColabService.shared.disconnect()
        }
        state = .idle
    }
    
    func cancel() async throws {
        state = .stopping
        state = .idle
    }
    
    func execute(code: String, language: String, progress: @escaping (String) -> Void) async throws -> String {
        state = .running
        defer { state = .idle }
        
        progress("⚡️ [Google Colab Cloud GPU/TPU Engine Activated]\n")
        
        return try await MainActor.run {
            GoogleColabService.shared
        }.execute(code: code, language: language, progress: progress)
    }
}
