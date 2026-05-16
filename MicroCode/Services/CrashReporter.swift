//
//  CrashReporter.swift
//  MicroCode
//
//  Persistent crash & error capture.
//
//  Swift runtime failures (force-unwrap, out-of-bounds, fatalError,
//  precondition) compile to `brk #1` and surface as SIGILL/SIGTRAP — they do
//  NOT go through NSException. The OS .ips report only gives raw image
//  offsets for a statically-linked Swift binary, which is unreadable. This
//  reporter captures a real symbolicated backtrace + a breadcrumb trail to
//  files under ~/Library/Logs/MicroCode so we can see exactly why it crashed.
//
//  Copyright © 2026 SPU AI CLUB. All rights reserved.
//

import Foundation
import Darwin

public final class CrashReporter: @unchecked Sendable {

    public static let shared = CrashReporter()

    // MARK: - Paths

    public let logDirectory: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Logs/MicroCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var breadcrumbsURL: URL { logDirectory.appendingPathComponent("breadcrumbs.log") }
    private var errorsURL: URL { logDirectory.appendingPathComponent("errors.log") }
    /// Written by the (limited) signal handler. Archived on next launch.
    private var signalSentinelURL: URL { logDirectory.appendingPathComponent("last-signal-crash.log") }

    // MARK: - State

    private let ioQueue = DispatchQueue(label: "com.microcode.crashreporter", qos: .utility)
    private let lock = NSLock()
    private var ring: [String] = []
    private let ringMax = 250
    private var installed = false

    /// Pre-opened fd + C path so the signal handler does no Swift allocation.
    private static var signalFD: Int32 = -1

    private init() {}

    // MARK: - Install

    public func install() {
        lock.lock()
        let already = installed
        installed = true
        lock.unlock()
        guard !already else { return }

        // 1. Archive any crash captured on the *previous* run.
        archivePreviousSignalCrash()

        // 2. Pre-open the signal-handler crash file (truncating). Keeping the
        //    fd open means the handler only needs write()/backtrace_symbols_fd.
        let path = signalSentinelURL.path
        path.withCString { cstr in
            CrashReporter.signalFD = open(cstr, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        }

        breadcrumb("===== SESSION START \(CrashReporter.timestamp()) — MicroCode v\(CrashReporter.appVersion()) =====")

        // 3. ObjC / NSException (full Foundation is safe here).
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.handleException(exception)
        }

        // 4. Fatal signals — incl. SIGTRAP/SIGILL which is how Swift `brk #1`
        //    (force-unwrap / fatalError / precondition / OOB) surfaces.
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP, SIGSYS] {
            signal(sig, CrashReporter.signalHandler)
        }
    }

    // MARK: - Breadcrumbs

    /// Record a lifecycle event. The last breadcrumb before a crash tells us
    /// where it died even if the backtrace is unsymbolicated. Cheap & safe to
    /// call from anywhere (including the main thread / SwiftUI body).
    public func breadcrumb(_ message: String,
                           file: String = #fileID, line: Int = #line, function: String = #function) {
        let entry = "[\(CrashReporter.timestamp())] [\((file as NSString).lastPathComponent):\(line) \(function)] \(message)"
        lock.lock()
        ring.append(entry)
        if ring.count > ringMax { ring.removeFirst(ring.count - ringMax) }
        lock.unlock()
        ioQueue.async { [breadcrumbsURL] in
            CrashReporter.append(entry + "\n", to: breadcrumbsURL)
        }
    }

    /// Record a non-fatal error so we have a continuous error history.
    public func logError(_ message: String,
                         file: String = #fileID, line: Int = #line, function: String = #function) {
        let entry = "[\(CrashReporter.timestamp())] [ERROR] [\((file as NSString).lastPathComponent):\(line) \(function)] \(message)"
        breadcrumb("ERROR: \(message)", file: file, line: line, function: function)
        ioQueue.async { [errorsURL] in
            CrashReporter.append(entry + "\n", to: errorsURL)
        }
    }

    // MARK: - Handlers

    private func handleException(_ exception: NSException) {
        let report = """
        ════════════════════════════════════════════════════════════════
         UNCAUGHT EXCEPTION
        ════════════════════════════════════════════════════════════════
        Time:    \(CrashReporter.timestamp())
        Version: MicroCode v\(CrashReporter.appVersion())
        Name:    \(exception.name.rawValue)
        Reason:  \(exception.reason ?? "(none)")
        UserInfo:\(exception.userInfo.map { " \($0)" } ?? " (none)")

        ── Exception call stack ───────────────────────────────────────
        \(exception.callStackSymbols.joined(separator: "\n"))

        ── Thread call stack ──────────────────────────────────────────
        \(Thread.callStackSymbols.joined(separator: "\n"))

        ── Recent breadcrumbs (newest last) ───────────────────────────
        \(recentBreadcrumbs().joined(separator: "\n"))
        ════════════════════════════════════════════════════════════════
        """
        writeCrashReport(report, kind: "exception")
    }

    /// C signal handler. MUST stay minimal & not call Swift runtime/alloc.
    private static let signalHandler: @convention(c) (Int32) -> Void = { sig in
        if CrashReporter.signalFD >= 0 {
            let header = "\n*** FATAL SIGNAL \(sig) (\(CrashReporter.signalName(sig))) ***\nSee breadcrumbs.log for the event trail.\nBacktrace:\n"
            header.withCString { _ = write(CrashReporter.signalFD, $0, strlen($0)) }

            var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
            let n = backtrace(&frames, 128)
            backtrace_symbols_fd(&frames, n, CrashReporter.signalFD)
            fsync(CrashReporter.signalFD)
        }
        // Restore default handler and re-raise so the OS still produces its
        // own report and the process terminates normally.
        signal(sig, SIG_DFL)
        raise(sig)
    }

    // MARK: - Crash report writing (full-Foundation path)

    private func writeCrashReport(_ body: String, kind: String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamped = logDirectory.appendingPathComponent("Crash-\(kind)-\(f.string(from: Date())).log")
        CrashReporter.append(body + "\n", to: stamped)
        // `latest-crash.log` is what the in-app viewer shows first.
        try? body.write(to: logDirectory.appendingPathComponent("latest-crash.log"),
                         atomically: true, encoding: .utf8)
        NSLog("[CrashReporter] %@ crash written to %@", kind, stamped.path)
    }

    /// If the signal handler wrote a sentinel last run, fold it (plus the
    /// breadcrumb trail) into a proper timestamped crash report now.
    private func archivePreviousSignalCrash() {
        let url = signalSentinelURL
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let raw = String(data: data, encoding: .utf8), raw.contains("FATAL SIGNAL") else { return }

        let crumbs = (try? String(contentsOf: breadcrumbsURL, encoding: .utf8))?
            .split(separator: "\n").suffix(80).joined(separator: "\n") ?? "(none)"

        let report = """
        ════════════════════════════════════════════════════════════════
         FATAL SIGNAL CRASH (recovered from previous run)
        ════════════════════════════════════════════════════════════════
        Recovered: \(CrashReporter.timestamp())
        Version:   MicroCode v\(CrashReporter.appVersion())
        \(raw)

        ── Breadcrumbs leading up to the crash (newest last) ──────────
        \(crumbs)
        ════════════════════════════════════════════════════════════════
        """
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        CrashReporter.append(report + "\n",
                             to: logDirectory.appendingPathComponent("Crash-signal-\(f.string(from: Date())).log"))
        try? report.write(to: logDirectory.appendingPathComponent("latest-crash.log"),
                          atomically: true, encoding: .utf8)
        // Clear the sentinel so we don't re-archive it next launch.
        try? Data().write(to: url)
        NSLog("[CrashReporter] Recovered previous-run signal crash into latest-crash.log")
    }

    // MARK: - Read API (for the in-app viewer)

    public func recentBreadcrumbs() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return ring
    }

    public func latestCrashText() -> String? {
        try? String(contentsOf: logDirectory.appendingPathComponent("latest-crash.log"), encoding: .utf8)
    }

    public func crashLogFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: logDirectory,
                                                      includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.lastPathComponent.hasPrefix("Crash-") }
            .sorted { (lhs, rhs) in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            } ?? []
    }

    // MARK: - Helpers

    private static func append(_ text: String, to url: URL) {
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    private static func appVersion() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private static func signalName(_ sig: Int32) -> String {
        switch sig {
        case SIGABRT: return "SIGABRT"
        case SIGILL:  return "SIGILL (Swift trap / illegal instruction)"
        case SIGSEGV: return "SIGSEGV (bad memory access)"
        case SIGFPE:  return "SIGFPE (arithmetic)"
        case SIGBUS:  return "SIGBUS"
        case SIGTRAP: return "SIGTRAP (Swift brk #1: force-unwrap / fatalError / precondition / out-of-bounds)"
        case SIGSYS:  return "SIGSYS"
        default:      return "signal \(sig)"
        }
    }
}
