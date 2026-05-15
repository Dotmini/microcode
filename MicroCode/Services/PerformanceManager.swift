//
//  PerformanceManager.swift
//  MicroCode
//
//  QoS Thread Management for Apple Silicon P-Core/E-Core optimization
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import Foundation
import os

// MARK: - Performance Logging

extension OSLog {
    static let performance = OSLog(subsystem: "com.microcode", category: "Performance")
    static let qos = OSLog(subsystem: "com.microcode", category: "QoS")
}

// MARK: - Performance Manager

/// Centralized QoS-aware task dispatching for Apple Silicon optimization.
/// Uses Quality of Service classes to target P-Cores (Performance) or E-Cores (Efficiency).
@MainActor
class PerformanceManager: ObservableObject {
    static let shared = PerformanceManager()
    
    // MARK: - QoS Dispatch Queues
    
    /// P-Core: UI-critical tasks requiring immediate response (< 16ms)
    /// Use for: Keystroke handling, scrolling, animations
    let userInteractiveQueue = DispatchQueue(
        label: "com.microcode.ui.interactive",
        qos: .userInteractive
    )
    
    /// P-Core: User-initiated actions with visible feedback
    /// Use for: File save, search, syntax highlighting
    let userInitiatedQueue = DispatchQueue(
        label: "com.microcode.user.initiated",
        qos: .userInitiated
    )
    
    /// E-Core: Long-running utility tasks
    /// Use for: Code analysis, indexing, linting
    let utilityQueue = DispatchQueue(
        label: "com.microcode.utility",
        qos: .utility,
        attributes: .concurrent
    )
    
    /// E-Core: Background processing (lowest priority)
    /// Use for: ML training, large file parsing, cleanup tasks
    let backgroundQueue = DispatchQueue(
        label: "com.microcode.background",
        qos: .background,
        attributes: .concurrent
    )
    
    // MARK: - Signpost IDs for Instruments
    
    private let signpostLog = OSLog.performance
    
    // MARK: - Memory Monitoring
    
    @Published var currentMemoryUsage: UInt64 = 0
    @Published var memoryPressureLevel: MemoryPressure = .normal
    
    enum MemoryPressure {
        case normal
        case warning
        case critical
    }
    
    private init() {
        startMemoryMonitoring()
    }
    
    // MARK: - P-Core Execution (High Priority)
    
    /// Execute work on P-Core with `.userInteractive` QoS.
    /// For UI-critical operations requiring immediate response.
    func runOnPCore<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "P-Core Task", signpostID: signpostID)
        
        defer {
            os_signpost(.end, log: signpostLog, name: "P-Core Task", signpostID: signpostID)
        }
        
        return await withCheckedContinuation { continuation in
            userInteractiveQueue.async {
                let result = work()
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Execute throwing work on P-Core.
    func runOnPCoreThrowing<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            userInteractiveQueue.async {
                do {
                    let result = try work()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - E-Core Execution (Low Priority)
    
    /// Execute work on E-Core with `.utility` QoS.
    /// For long-running tasks that shouldn't block UI.
    func runOnECore<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "E-Core Task", signpostID: signpostID)
        
        defer {
            os_signpost(.end, log: signpostLog, name: "E-Core Task", signpostID: signpostID)
        }
        
        return await withCheckedContinuation { continuation in
            utilityQueue.async {
                let result = work()
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Execute work on E-Core with `.background` QoS (lowest priority).
    /// For tasks that can be deferred when system is busy.
    func runInBackground<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        return await withCheckedContinuation { continuation in
            backgroundQueue.async {
                let result = work()
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Execute throwing work on E-Core.
    func runOnECoreThrowing<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            utilityQueue.async {
                do {
                    let result = try work()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Batch Processing
    
    /// Process items concurrently on E-Core with rate limiting.
    func processBatch<T: Sendable, R: Sendable>(
        items: [T],
        maxConcurrent: Int = 4,
        transform: @escaping @Sendable (T) -> R
    ) async -> [R] {
        await withTaskGroup(of: (Int, R).self) { group in
            var results = [(Int, R)]()
            results.reserveCapacity(items.count)
            
            for (index, item) in items.enumerated() {
                group.addTask(priority: .utility) {
                    (index, transform(item))
                }
                
                // Rate limit
                if index % maxConcurrent == maxConcurrent - 1 {
                    if let result = await group.next() {
                        results.append(result)
                    }
                }
            }
            
            for await result in group {
                results.append(result)
            }
            
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
    
    // MARK: - Signpost Helpers for Instruments
    
    /// Begin a signpost interval for Instruments profiling.
    func beginSignpost(name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: name, signpostID: id)
        return id
    }
    
    /// End a signpost interval.
    func endSignpost(name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: signpostLog, name: name, signpostID: id)
    }
    
    /// Execute work within a signpost interval for Instruments.
    func withSignpost<T>(name: StaticString, _ work: () throws -> T) rethrows -> T {
        let id = beginSignpost(name: name)
        defer { endSignpost(name: name, id: id) }
        return try work()
    }
    
    /// Async version of signpost wrapper.
    func withSignpostAsync<T>(name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let id = beginSignpost(name: name)
        defer { endSignpost(name: name, id: id) }
        return try await work()
    }
    
    // MARK: - Memory Monitoring
    
    private func startMemoryMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMemoryStats()
            }
        }
    }
    
    private func updateMemoryStats() {
        currentMemoryUsage = getResidentMemory()
        
        // Check memory pressure
        let availableMemory = getAvailableMemory()
        if availableMemory < 100_000_000 { // < 100MB
            memoryPressureLevel = .critical
            os_log(.error, log: .performance, "⚠️ Critical memory pressure: %{public}llu bytes available", availableMemory)
        } else if availableMemory < 500_000_000 { // < 500MB
            memoryPressureLevel = .warning
            os_log(.info, log: .performance, "Memory pressure warning: %{public}llu bytes available", availableMemory)
        } else {
            memoryPressureLevel = .normal
        }
    }
    
    /// Get current process resident memory size.
    func getResidentMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
    
    /// Get system available memory (approximation).
    func getAvailableMemory() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            return UInt64(stats.free_count) * pageSize
        }
        return 0
    }
    
    /// Format memory size for display.
    func formatMemory(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Task Priority Extension

extension Task where Failure == Never {
    /// Create a task running on E-Core.
    static func background<T: Sendable>(
        operation: @escaping @Sendable () async -> T
    ) -> Task<T, Never> {
        Task<T, Never>(priority: .background) {
            await operation()
        }
    }
    
    /// Create a task running on P-Core.
    static func highPriority<T: Sendable>(
        operation: @escaping @Sendable () async -> T
    ) -> Task<T, Never> {
        Task<T, Never>(priority: .userInitiated) {
            await operation()
        }
    }
}
