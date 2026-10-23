//
//  PerformanceManager.swift
//  MicroCode
//
//  QoS Thread Management for Apple Silicon P-Core/E-Core optimization
//  Copyright © 2025 Dotmini Company Limited. All rights reserved.
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
    
    // MARK: - Apple Silicon Hardware Topology
    
    /// Total logical CPU cores on this Mac (e.g. 8 on M2, 12 on M2 Pro/M3 Pro, 16 on M3 Max)
    nonisolated static let totalCores: Int = {
        max(1, ProcessInfo.processInfo.activeProcessorCount)
    }()
    
    /// Physical Performance Cores (P-Cores, perflevel0 on Apple Silicon)
    nonisolated static let pCoreCount: Int = {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &count, &size, nil, 0) == 0, count > 0 {
            return Int(count)
        }
        return max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
    }()
    
    /// Physical Efficiency Cores (E-Cores, perflevel1 on Apple Silicon)
    nonisolated static let eCoreCount: Int = {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel1.physicalcpu", &count, &size, nil, 0) == 0, count > 0 {
            return Int(count)
        }
        return max(1, ProcessInfo.processInfo.activeProcessorCount - pCoreCount)
    }()

    // MARK: - QoS Dispatch Queues (True Multi-Core Concurrent Pools)
    
    /// P-Core Multi-Core Pool: UI-critical parallel tasks requiring immediate response (< 16ms)
    /// Use for: Viewport syntax highlighting, interactive diffing, fast buffer indexing
    nonisolated let userInteractiveQueue = DispatchQueue(
        label: "com.microcode.ui.interactive",
        qos: .userInteractive,
        attributes: .concurrent
    )
    
    /// P-Core Multi-Core Pool: User-initiated actions with visible feedback
    /// Use for: Multi-file search/replace, parallel file reading, symbol extraction
    nonisolated let userInitiatedQueue = DispatchQueue(
        label: "com.microcode.user.initiated",
        qos: .userInitiated,
        attributes: .concurrent
    )
    
    /// E-Core Multi-Core Pool: Long-running utility tasks
    /// Use for: RepoMap building, workspace indexing, linting, AI output compression
    nonisolated let utilityQueue = DispatchQueue(
        label: "com.microcode.utility",
        qos: .utility,
        attributes: .concurrent
    )
    
    /// E-Core Multi-Core Pool: Background processing (lowest priority)
    /// Use for: ML training, large file archiving, cache compaction
    nonisolated let backgroundQueue = DispatchQueue(
        label: "com.microcode.background",
        qos: .background,
        attributes: .concurrent
    )
    
    // MARK: - Signpost IDs for Instruments
    
    nonisolated private let signpostLog = OSLog.performance
    
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
    
    // MARK: - P-Core Execution (High Priority, Nonisolated Multi-Core)
    
    /// Execute work on P-Core with `.userInteractive` QoS without hopping through `@MainActor`.
    nonisolated func runOnPCore<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
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
    
    /// Execute throwing work on P-Core without hopping through `@MainActor`.
    nonisolated func runOnPCoreThrowing<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
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
    
    // MARK: - E-Core Execution (Low Priority, Nonisolated Multi-Core)
    
    /// Execute work on E-Core with `.utility` QoS without hopping through `@MainActor`.
    nonisolated func runOnECore<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
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
    nonisolated func runInBackground<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        return await withCheckedContinuation { continuation in
            backgroundQueue.async {
                let result = work()
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Execute throwing work on E-Core without hopping through `@MainActor`.
    nonisolated func runOnECoreThrowing<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
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
    
    // MARK: - Hardware-Aware Lock-Free Multi-Core Parallel Map (`dispatch_apply`)
    
    /// Synchronously partitions `items` across all available CPU cores using GCD's kernel work-stealing
    /// `DispatchQueue.concurrentPerform`. Each worker writes to its own disjoint slice buffer (zero lock contention).
    nonisolated static func parallelMap<T: Sendable, R: Sendable>(
        _ items: [T],
        minItemsPerCore: Int = 4,
        transform: @Sendable (T) -> R
    ) -> [R] {
        let count = items.count
        if count == 0 { return [] }
        if count == 1 { return [transform(items[0])] }
        
        let maxWorkers = max(2, totalCores)
        let workerCount = min(maxWorkers, max(1, (count + minItemsPerCore - 1) / max(1, minItemsPerCore)))
        if workerCount <= 1 {
            return items.map(transform)
        }
        
        let chunkSize = (count + workerCount - 1) / workerCount
        var chunkOutputs = Array<[R]>(repeating: [], count: workerCount)
        
        chunkOutputs.withUnsafeMutableBufferPointer { outBuffer in
            let baseAddress = outBuffer.baseAddress!
            let rawPtr = UnsafeMutableRawPointer(baseAddress)
            let sendableAddr = UInt(bitPattern: rawPtr)
            DispatchQueue.concurrentPerform(iterations: workerCount) { workerIdx in
                let start = workerIdx * chunkSize
                let end = min(count, start + chunkSize)
                guard start < end else { return }
                var local: [R] = []
                local.reserveCapacity(end - start)
                for idx in start..<end {
                    local.append(transform(items[idx]))
                }
                let slotPtr = UnsafeMutablePointer<[R]>(bitPattern: sendableAddr)! + workerIdx
                slotPtr.pointee = local
            }
        }
        
        var flattened: [R] = []
        flattened.reserveCapacity(count)
        for chunk in chunkOutputs {
            flattened.append(contentsOf: chunk)
        }
        return flattened
    }

    // MARK: - Batch Processing (Sliding-Window Multi-Core TaskGroup)
    
    /// Process items concurrently across cores with a true sliding-window TaskGroup.
    nonisolated func processBatch<T: Sendable, R: Sendable>(
        items: [T],
        maxConcurrent: Int = PerformanceManager.totalCores,
        priority: TaskPriority = .utility,
        transform: @escaping @Sendable (T) async -> R
    ) async -> [R] {
        guard !items.isEmpty else { return [] }
        let concurrency = max(1, min(items.count, maxConcurrent))
        return await withTaskGroup(of: (Int, R).self) { group in
            var results = [(Int, R)]()
            results.reserveCapacity(items.count)
            var nextIndex = 0
            
            // Seed initial worker window across all cores
            while nextIndex < concurrency {
                let idx = nextIndex
                let item = items[idx]
                group.addTask(priority: priority) {
                    (idx, await transform(item))
                }
                nextIndex += 1
            }
            
            // As soon as any core finishes a task, feed it the next item immediately
            while let completed = await group.next() {
                results.append(completed)
                if nextIndex < items.count {
                    let idx = nextIndex
                    let item = items[idx]
                    group.addTask(priority: priority) {
                        (idx, await transform(item))
                    }
                    nextIndex += 1
                }
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
    
    // MARK: - Memory Monitoring (Event-Driven UMA Kernel Pressure + Low-Frequency Sampling)
    
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    private func startMemoryMonitoring() {
        updateMemoryStats()
        
        // Event-driven kernel memory pressure listener (0% idle CPU overhead, preserves App Nap / E-Core deep sleep)
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let event = source.data
            if event.contains(.critical) {
                if self.memoryPressureLevel != .critical { self.memoryPressureLevel = .critical }
            } else if event.contains(.warning) {
                if self.memoryPressureLevel != .warning { self.memoryPressureLevel = .warning }
            } else {
                if self.memoryPressureLevel != .normal { self.memoryPressureLevel = .normal }
            }
            self.updateMemoryStats()
        }
        source.resume()
        self.memoryPressureSource = source
    }
    
    func updateMemoryStats() {
        let footprint = getResidentMemory()
        // Only publish if changed by >= 1 MB to avoid unnecessary SwiftUI observer notifications
        if currentMemoryUsage == 0 || abs(Int64(footprint) - Int64(currentMemoryUsage)) >= 1_048_576 {
            currentMemoryUsage = footprint
        }
        
        let availableMemory = getAvailableMemory()
        let nextPressure: MemoryPressure
        if availableMemory < 256_000_000 { // < 256MB true reclaimable UMA memory
            nextPressure = .critical
            os_log(.error, log: .performance, "⚠️ Critical UMA memory pressure: %{public}llu bytes available", availableMemory)
        } else if availableMemory < 768_000_000 { // < 768MB
            nextPressure = .warning
        } else {
            nextPressure = .normal
        }
        if memoryPressureLevel != nextPressure {
            memoryPressureLevel = nextPressure
        }
    }
    
    /// Get current process Apple Silicon UMA physical footprint (`phys_footprint`),
    /// matching Activity Monitor and macOS Jetsam accounting.
    nonisolated func getResidentMemory() -> UInt64 {
        var vmInfo = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let vmKern = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }
        if vmKern == KERN_SUCCESS && vmInfo.phys_footprint > 0 {
            return UInt64(vmInfo.phys_footprint)
        }
        
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
    
    /// Get system available UMA memory (free + inactive/reclaimable file-backed pages).
    nonisolated func getAvailableMemory() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            let reclaimablePages = UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.speculative_count)
            return reclaimablePages * pageSize
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
