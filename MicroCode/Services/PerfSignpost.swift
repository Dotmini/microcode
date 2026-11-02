//
//  PerfSignpost.swift
//  MicroCode
//
//  Lightweight performance instrumentation used to turn "no stutter" into a measurable budget.
//
//  - `Perf.measure("name") { ... }` emits an `OSSignposter` interval (visible in Instruments: Time Profiler /
//    Animation Hitches / os_signpost track, subsystem `com.microcode`, category `Perf`) and records a *budget
//    violation* when the wrapped main-thread work takes longer than one 120 Hz frame (8.3 ms by default).
//  - `PerfBudgetCounter.shared.snapshot()` exposes violation counts / worst case for diagnostics and CI.
//  - `PerfPublishRateMonitor` counts `objectWillChange` emissions of a store per second so the SwiftUI
//    invalidation fan-out of large ObservableObjects can be measured before it is refactored.
//
//  Overhead when no budget is exceeded: two clock reads + one signpost interval (no allocation).
//

import Combine
import Foundation
import os

enum Perf {
    static let signposter = OSSignposter(subsystem: "com.microcode", category: "Perf")
    /// One 120 Hz ProMotion frame.
    static let mainThreadBudgetMs: Double = 8.3

    @inline(__always)
    static func measure<T>(_ name: StaticString, budgetMs: Double = Perf.mainThreadBudgetMs, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            signposter.endInterval(name, state)
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000
            if elapsedMs > budgetMs {
                PerfBudgetCounter.shared.record(name: "\(name)", elapsedMs: elapsedMs, budgetMs: budgetMs)
            }
        }
        return try body()
    }
}

final class PerfBudgetCounter: @unchecked Sendable {
    struct Entry: Sendable {
        var violations = 0
        var worstMs: Double = 0
        var totalOverMs: Double = 0
    }

    static let shared = PerfBudgetCounter()
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var lastLogUptime: [String: UInt64] = [:]
    private let logger = Logger(subsystem: "com.microcode", category: "PerfBudget")

    func record(name: String, elapsedMs: Double, budgetMs: Double) {
        lock.lock()
        var entry = entries[name, default: Entry()]
        entry.violations += 1
        entry.worstMs = max(entry.worstMs, elapsedMs)
        entry.totalOverMs += elapsedMs - budgetMs
        entries[name] = entry
        let now = DispatchTime.now().uptimeNanoseconds
        let shouldLog = now &- (lastLogUptime[name] ?? 0) > 1_000_000_000
        if shouldLog { lastLogUptime[name] = now }
        lock.unlock()
        if shouldLog {
            logger.notice("budget exceeded: \(name, privacy: .public) \(elapsedMs, format: .fixed(precision: 2)) ms (budget \(budgetMs, format: .fixed(precision: 1)) ms, total violations \(entry.violations))")
        }
    }

    func snapshot() -> [String: Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func reset() {
        lock.lock()
        entries.removeAll()
        lastLogUptime.removeAll()
        lock.unlock()
    }
}

/// Counts `objectWillChange` emissions per second. Enable with
/// `defaults write com.dotmini.microcode microcode.perfTelemetry -bool YES`.
@MainActor
final class PerfPublishRateMonitor {
    static let shared = PerfPublishRateMonitor()
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "microcode.perfTelemetry") }

    private var cancellables: [String: AnyCancellable] = [:]
    private var counts: [String: Int] = [:]
    private var timer: Timer?
    private let logger = Logger(subsystem: "com.microcode", category: "PerfPublishRate")
    /// Publishes per second above which a store is reported (a 60 Hz view tree cannot show more than this anyway).
    private let warnThreshold = 30

    func watch(_ label: String, publisher: ObservableObjectPublisher) {
        guard Self.isEnabled, cancellables[label] == nil else { return }
        cancellables[label] = publisher.sink { [weak self] _ in
            self?.counts[label, default: 0] += 1
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.flushWindow() }
            }
        }
    }

    private func flushWindow() {
        for (label, count) in counts where count >= warnThreshold {
            logger.notice("\(label, privacy: .public) published \(count) objectWillChange/s (threshold \(self.warnThreshold)); every observing view re-evaluates body each time")
        }
        counts.removeAll(keepingCapacity: true)
    }
}
