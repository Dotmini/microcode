import Foundation

// Minimal stand-in for MicroCode/Services/PerformanceManager.swift (only `totalCores` is used by SyntaxCache.swift).
enum PerformanceManager {
    static let totalCores: Int = max(1, ProcessInfo.processInfo.activeProcessorCount)
}
