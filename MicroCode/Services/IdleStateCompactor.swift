//
//  IdleStateCompactor.swift
//  MicroCode
//
//  High-performance, zero-jank Idle State Manager and Memory Compactor.
//  Executes on background E-Core to maintain an ultra-lean idle memory footprint (<= 50MB)
//  without causing UI stutters or frame drops.
//  Copyright © 2026 Dotmini Company Limited. All rights reserved.
//

import Foundation
import AppKit
import os

/// Manages application idle lifecycle and executes transparent state compression.
@MainActor
public final class IdleStateCompactor: ObservableObject {
    public static let shared = IdleStateCompactor()
    
    public enum LifecycleState: String, Sendable {
        case active = "Active"
        case settling = "Settling"
        case idleCompressed = "Idle (Compressed)"
    }
    
    @Published public private(set) var currentState: LifecycleState = .active
    @Published public private(set) var lastCompactedMemoryBytes: UInt64 = 0
    @Published public private(set) var totalMemorySavedBytes: Int = 0
    @Published public private(set) var isCompacting: Bool = false
    
    private var idleTimer: Timer?
    private var lastUserActivity: Date = Date()
    private var eventMonitor: Any?
    private let defaultIdleThreshold: TimeInterval = 3.5 // Inactivity threshold
    private var isMonitoringStarted: Bool = false
    
    private init() {}
    
    /// Starts monitoring user interaction and idle state transitions.
    public func startMonitoring() {
        guard !isMonitoringStarted else { return }
        isMonitoringStarted = true
        setupEventMonitors()
        resetIdleTimer(delay: 2.5) // Initial startup settling delay
    }
    
    /// Record active user interaction (keystroke, click, scroll).
    public func recordActivity() {
        lastUserActivity = Date()
        if currentState != .active {
            currentState = .active
            // Immediate wakeup: decompress only the currently selected file tab in O(1)
            AppState.shared?.decompressActiveFile()
        }
        resetIdleTimer(delay: defaultIdleThreshold)
    }
    
    private func resetIdleTimer(delay: TimeInterval) {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performIdleCompaction()
            }
        }
    }
    
    private func setupEventMonitors() {
        // Local monitor for user actions inside any MicroCode window
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            self?.recordActivity()
            return event
        }
        
        // Listen to window focus and backgrounding
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.performIdleCompaction()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recordActivity()
        }
    }
    
    /// Executes idle state compression and memory compaction.
    public func performIdleCompaction() {
        guard !isCompacting else { return }
        isCompacting = true
        currentState = .idleCompressed
        
        Task.detached(priority: .background) {
            var bytesSaved = 0
            
            // 1. Compress inactive open file buffers in AppState
            if let appState = await AppState.shared {
                bytesSaved += await appState.compressInactiveFiles()
            }
            
            // 2. Clear syntax highlight line caches (recomputed lazily when scrolling)
            SyntaxCache.shared.purgeMemory()
            
            // 3. Purge system and network image/URL caches
            URLCache.shared.removeAllCachedResponses()
            
            // 4. Instruct Darwin kernel to release dirty heap pages back to macOS
            #if os(macOS)
            malloc_zone_pressure_relief(malloc_default_zone(), 0)
            #endif
            
            let residentMemory = await PerformanceManager.shared.getResidentMemory()
            
            await MainActor.run {
                self.lastCompactedMemoryBytes = residentMemory
                self.totalMemorySavedBytes += bytesSaved
                self.isCompacting = false
                
                os_log(.info, log: .performance, "🍃 Idle Memory Compaction complete: Resident RAM is %{public}llu bytes, compressed %{public}d bytes", residentMemory, bytesSaved)
            }
        }
    }
}
