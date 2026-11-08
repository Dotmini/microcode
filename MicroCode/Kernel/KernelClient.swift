//
//  Kernel/KernelClient.swift
//  MicroCode
//
//  1) Bridge between User Space (Swift) and App Space (Rust Kernel FFI).
//  2) LocalPersistentPythonKernelPool — Warm Stateful Python Daemon (<1.5ms dispatch,
//     live 60Hz streaming, SIGINT interrupt preserving RAM, Retina plot isolation,
//     auto DataFrame grid extraction, and live Variable + Unified/Metal Memory telemetry).
//  3) PolyglotStreamingAndCacheEngine — Content-addressed SHA-256 binary cache for
//     Rust / C++ / Objective-C (<2ms cached runs), non-blocking 64KB-deadlock-free
//     60Hz pipe streaming with `\r` tqdm progress-bar coalescing, & warm Julia daemon.
//  4) NotebookImageCache & NotebookPersistenceActor — Retina NSCache & off-MainActor WAL.
//

import Foundation
import AppKit
import CryptoKit
import Darwin

// MARK: - Rust FFI Kernel Client (Preserved)

class KernelClient: ObservableObject {
    static let shared = KernelClient()

    @Published var isConnected = false
    @Published var powerMode = "Balanced"
    @Published var networkStatus = "Unknown"

    private init() {
        startHeartbeat()
    }

    func startHeartbeat() {
        isConnected = true
        networkStatus = getKernelNetworkStatus()
    }

    func setPowerMode(_ mode: String) async {
        powerMode = mode
        do {
            try setKernelPowerMode(mode: mode)
            print("⚡️ System Power Mode set to \(mode) via FFI")
        } catch {
            print("Failed to set Power Mode: \(error)")
        }
    }

    func triggerPanic() {
        print(" Triggering direct Kernel Panic via FFI...")
        triggerKernelPanic()
    }
}

// MARK: - Terminal Stream Buffer (`\r` tqdm Progress Coalescer + ANSI Sanitizer + 60Hz Batching)

final class TerminalStreamBuffer {
    private let lock = NSLock()
    private var completedLines: [String] = []
    private var currentLineChars: [Character] = []
    private var cursorIndex: Int = 0
    private var pendingCR: Bool = false

    private static let ansiRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
    )

    func reset() {
        lock.lock()
        completedLines.removeAll(keepingCapacity: false)
        currentLineChars.removeAll(keepingCapacity: false)
        cursorIndex = 0
        pendingCR = false
        lock.unlock()
    }

    func appendChunk(_ raw: String) -> String {
        let cleaned: String
        if raw.utf8.contains(0x1B), let rx = Self.ansiRegex {
            cleaned = rx.stringByReplacingMatches(
                in: raw,
                range: NSRange(raw.startIndex..., in: raw),
                withTemplate: ""
            )
        } else {
            cleaned = raw
        }

        lock.lock()
        defer { lock.unlock() }

        for ch in cleaned {
            if ch == "\r\n" {
                completedLines.append(String(currentLineChars))
                currentLineChars.removeAll(keepingCapacity: true)
                cursorIndex = 0
                pendingCR = false
                continue
            }
            if ch == "\r" {
                pendingCR = true
                cursorIndex = 0
                continue
            }
            if ch == "\n" {
                completedLines.append(String(currentLineChars))
                currentLineChars.removeAll(keepingCapacity: true)
                cursorIndex = 0
                pendingCR = false
                continue
            }
            if pendingCR {
                // In-place line overwrite (e.g. tqdm / epoch progress bar)
                currentLineChars.removeAll(keepingCapacity: true)
                cursorIndex = 0
                pendingCR = false
            }
            if cursorIndex < currentLineChars.count {
                currentLineChars[cursorIndex] = ch
            } else {
                currentLineChars.append(ch)
            }
            cursorIndex += 1
        }

        return snapshotLocked()
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return snapshotLocked()
    }

    private func snapshotLocked() -> String {
        if currentLineChars.isEmpty {
            return completedLines.joined(separator: "\n")
        }
        if completedLines.isEmpty {
            return String(currentLineChars)
        }
        return completedLines.joined(separator: "\n") + "\n" + String(currentLineChars)
    }
}

// MARK: - Kernel Execution Result Envelope

struct LocalKernelRunOutcome {
    let stdoutText: String
    let imageURLs: [URL]
    let inlineDataFrame: InlineDataFramePayload?
    let variables: [KernelVariableInfo]
    let telemetry: CellExecutionTelemetry
    let hadError: Bool
}

// MARK: - Persistent Warm Python Kernel Daemon & Pool

final class LocalPersistentPythonKernelPool {
    static let shared = LocalPersistentPythonKernelPool()

    private let lock = NSLock()
    private var kernels: [UUID: LocalPersistentPythonKernel] = [:]

    private init() {}

    func kernel(for notebookId: UUID, pythonPath: String, workingDirectory: URL) -> LocalPersistentPythonKernel {
        lock.lock()
        defer { lock.unlock() }
        if let existing = kernels[notebookId] {
            if existing.pythonExecutable == pythonPath {
                existing.workingDirectory = workingDirectory
                return existing
            } else {
                existing.shutdown()
            }
        }
        let created = LocalPersistentPythonKernel(
            notebookId: notebookId,
            pythonExecutable: pythonPath,
            workingDirectory: workingDirectory
        )
        kernels[notebookId] = created
        return created
    }

    func interrupt(notebookId: UUID) {
        lock.lock()
        let k = kernels[notebookId]
        lock.unlock()
        k?.interruptCurrentCell()
    }

    func restart(notebookId: UUID) {
        lock.lock()
        let k = kernels.removeValue(forKey: notebookId)
        lock.unlock()
        k?.shutdown()
        SharedMemoryService.shared.clearLiveVariables(for: notebookId)
    }
}

final class LocalPersistentPythonKernel {
    let notebookId: UUID
    let pythonExecutable: String
    var workingDirectory: URL

    private let stateLock = NSLock()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private var framingBuffer = Data()
    private let streamBuffer = TerminalStreamBuffer()
    private var lastUIEmitTime: CFAbsoluteTime = 0
    private var activeOnStream: ((String) -> Void)?
    private var activeContinuation: CheckedContinuation<LocalKernelRunOutcome, Never>?
    private var lastKnownRSSBytes: Int64 = 0

    init(notebookId: UUID, pythonExecutable: String, workingDirectory: URL) {
        self.notebookId = notebookId
        self.pythonExecutable = pythonExecutable
        self.workingDirectory = workingDirectory
    }

    func interruptCurrentCell() {
        stateLock.lock()
        let pid = process?.processIdentifier
        let running = process?.isRunning ?? false
        stateLock.unlock()
        if running, let pid, pid > 0 {
            kill(pid, SIGINT)
        }
    }

    func shutdown() {
        stateLock.lock()
        let proc = process
        let cont = activeContinuation
        activeContinuation = nil
        activeOnStream = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        stdinHandle = nil
        stdoutPipe = nil
        stderrPipe = nil
        framingBuffer.removeAll()
        stateLock.unlock()

        if let proc, proc.isRunning {
            proc.terminate()
        }
        if let cont {
            cont.resume(returning: LocalKernelRunOutcome(
                stdoutText: "⏹ Kernel restarted.",
                imageURLs: [],
                inlineDataFrame: nil,
                variables: [],
                telemetry: CellExecutionTelemetry(durationMs: 0, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false),
                hadError: false
            ))
        }
    }

    func executeCell(
        cellId: UUID,
        executionIndex: Int,
        code: String,
        onStream: @escaping (String) -> Void
    ) async -> LocalKernelRunOutcome {
        let sanitizedCode = code
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")

        do {
            try ensureDaemonStarted()
        } catch {
            return LocalKernelRunOutcome(
                stdoutText: "❌ Failed to start Python kernel (\(pythonExecutable)): \(error.localizedDescription)",
                imageURLs: [],
                inlineDataFrame: nil,
                variables: [],
                telemetry: CellExecutionTelemetry(durationMs: 0, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false),
                hadError: true
            )
        }

        let artifactsDir = workingDirectory.appendingPathComponent("artifacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: artifactsDir, withIntermediateDirectories: true)

        let shortCell = String(cellId.uuidString.prefix(8)).lowercased()
        let payloadDict: [String: Any] = [
            "code": sanitizedCode,
            "cell_tag": "cell_\(shortCell)_run\(executionIndex)",
            "workdir": workingDirectory.path,
            "artifacts_dir": artifactsDir.path,
            "session_id": notebookId.uuidString
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payloadDict),
              let handle = currentStdinHandle() else {
            return LocalKernelRunOutcome(
                stdoutText: "❌ Failed to encode kernel command.",
                imageURLs: [],
                inlineDataFrame: nil,
                variables: [],
                telemetry: CellExecutionTelemetry(durationMs: 0, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false),
                hadError: true
            )
        }

        let b64 = jsonData.base64EncodedString()
        let commandLine = "MC_EXEC:\(b64)\n"

        return await withCheckedContinuation { continuation in
            stateLock.lock()
            streamBuffer.reset()
            framingBuffer.removeAll(keepingCapacity: true)
            activeOnStream = onStream
            activeContinuation = continuation
            lastUIEmitTime = 0
            stateLock.unlock()

            do {
                if let cmdData = commandLine.data(using: .utf8) {
                    try handle.write(contentsOf: cmdData)
                }
            } catch {
                stateLock.lock()
                let pending = activeContinuation
                activeContinuation = nil
                activeOnStream = nil
                stateLock.unlock()
                pending?.resume(returning: LocalKernelRunOutcome(
                    stdoutText: "❌ Kernel pipe write failed: \(error.localizedDescription)",
                    imageURLs: [],
                    inlineDataFrame: nil,
                    variables: [],
                    telemetry: CellExecutionTelemetry(durationMs: 0, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false),
                    hadError: true
                ))
            }
        }
    }

    private func currentStdinHandle() -> FileHandle? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stdinHandle
    }

    private func ensureDaemonStarted() throws {
        stateLock.lock()
        if let proc = process, proc.isRunning, stdinHandle != nil {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let daemonScriptURL = workingDirectory.appendingPathComponent(".mc_persistent_py_worker_v2.py")
        let workerCode = Self.buildPythonWorkerScript(sessionId: notebookId.uuidString)
        try workerCode.write(to: daemonScriptURL, atomically: true, encoding: .utf8)

        let resolvedExec: String = {
            if FileManager.default.isExecutableFile(atPath: pythonExecutable) {
                return pythonExecutable
            }
            for candidate in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"] {
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
            return PythonEnvManager.shared.systemPythonExecutable
        }()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: resolvedExec)
        proc.arguments = ["-u", daemonScriptURL.path]
        proc.currentDirectoryURL = workingDirectory

        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        env["MPLBACKEND"] = "Agg"
        env["MICROCODE_LOCAL_API_TOKEN"] = LocalBackendAuth.token
        let runtimeBins = RuntimeManager.shared.allRuntimeBinDirectories()
        let extra = (runtimeBins + ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin"]).joined(separator: ":")
        let prevPath = env["PATH"] ?? ""
        env["PATH"] = prevPath.isEmpty ? extra : "\(extra):\(prevPath)"
        proc.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let chunk = fh.availableData
            guard !chunk.isEmpty else { return }
            self?.consumeStdoutData(chunk)
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let chunk = fh.availableData
            guard !chunk.isEmpty else { return }
            if let str = String(data: chunk, encoding: .utf8) {
                self?.appendUserStreamText(str)
            }
        }

        proc.terminationHandler = { [weak self] terminatedProc in
            guard let self = self else { return }
            self.stateLock.lock()
            let cont = self.activeContinuation
            self.activeContinuation = nil
            self.activeOnStream = nil
            if self.process === terminatedProc {
                self.process = nil
                self.stdinHandle = nil
            }
            let partial = self.streamBuffer.snapshot()
            self.stateLock.unlock()

            if let cont {
                let status = terminatedProc.terminationStatus
                let msg = partial.isEmpty
                    ? "⚠️ Python kernel process exited (code \(status)). Kernel will auto-respawn on next run."
                    : partial + "\n⚠️ Kernel process exited (code \(status))."
                cont.resume(returning: LocalKernelRunOutcome(
                    stdoutText: msg,
                    imageURLs: [],
                    inlineDataFrame: nil,
                    variables: [],
                    telemetry: CellExecutionTelemetry(durationMs: 0, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false),
                    hadError: status != 0
                ))
            }
        }

        try proc.run()

        stateLock.lock()
        self.process = proc
        self.stdinHandle = inPipe.fileHandleForWriting
        self.stdoutPipe = outPipe
        self.stderrPipe = errPipe
        stateLock.unlock()
    }

    private func appendUserStreamText(_ text: String, forceEmit: Bool = false) {
        stateLock.lock()
        let snap = streamBuffer.appendChunk(text)
        let now = CFAbsoluteTimeGetCurrent()
        let cb = activeOnStream
        let shouldEmit = forceEmit || (now - lastUIEmitTime >= 0.018) // ~55-60 Hz coalesced UI frame rate
        if shouldEmit {
            lastUIEmitTime = now
        }
        stateLock.unlock()

        if shouldEmit, let cb {
            DispatchQueue.main.async {
                cb(snap)
            }
        }
    }

    private func consumeStdoutData(_ chunk: Data) {
        let startMarker = Data([0x02, 0x4D, 0x43, 0x4A, 0x3A]) // "\x02MCJ:"
        let endByte: UInt8 = 0x03                              // "\x03"

        stateLock.lock()
        framingBuffer.append(chunk)
        stateLock.unlock()

        while true {
            stateLock.lock()
            if framingBuffer.isEmpty {
                stateLock.unlock()
                break
            }

            if let markerRange = framingBuffer.range(of: startMarker) {
                // 1. Flush any user stdout preceding `\x02MCJ:`
                if markerRange.lowerBound > framingBuffer.startIndex {
                    let prefixData = framingBuffer.subdata(in: framingBuffer.startIndex..<markerRange.lowerBound)
                    framingBuffer.removeSubrange(framingBuffer.startIndex..<markerRange.lowerBound)
                    stateLock.unlock()
                    if let userText = String(data: prefixData, encoding: .utf8) {
                        appendUserStreamText(userText)
                    }
                    continue
                }

                // Marker is at startIndex — look for closing `\x03`
                let searchFrom = framingBuffer.index(framingBuffer.startIndex, offsetBy: startMarker.count)
                if let endIdx = framingBuffer[searchFrom...].firstIndex(of: endByte) {
                    let b64Data = framingBuffer.subdata(in: searchFrom..<endIdx)
                    var removeEnd = framingBuffer.index(after: endIdx)
                    if removeEnd < framingBuffer.endIndex && framingBuffer[removeEnd] == 0x0A {
                        removeEnd = framingBuffer.index(after: removeEnd)
                    }
                    framingBuffer.removeSubrange(framingBuffer.startIndex..<removeEnd)
                    stateLock.unlock()

                    if let b64Str = String(data: b64Data, encoding: .utf8),
                       let decoded = Data(base64Encoded: b64Str) {
                        handleKernelControlPacket(decoded)
                    }
                    continue
                } else {
                    // Wait for the rest of the control frame
                    stateLock.unlock()
                    break
                }
            } else {
                // Keep up to 4 trailing bytes in case `\x02MCJ:` splits across OS pipe reads
                let holdback = min(4, framingBuffer.count)
                let flushCount = framingBuffer.count - holdback
                if flushCount > 0 && !framingBuffer.suffix(holdback).contains(0x02) {
                    let allData = framingBuffer
                    framingBuffer.removeAll(keepingCapacity: true)
                    stateLock.unlock()
                    if let userText = String(data: allData, encoding: .utf8) {
                        appendUserStreamText(userText)
                    }
                } else if flushCount > 0 {
                    let prefixData = framingBuffer.subdata(in: 0..<flushCount)
                    framingBuffer.removeSubrange(0..<flushCount)
                    stateLock.unlock()
                    if let userText = String(data: prefixData, encoding: .utf8) {
                        appendUserStreamText(userText)
                    }
                } else {
                    stateLock.unlock()
                }
                break
            }
        }
    }

    private func handleKernelControlPacket(_ jsonData: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let event = obj["event"] as? String else { return }

        if event == "done" {
            let durationMs = (obj["duration_ms"] as? NSNumber)?.doubleValue ?? 0
            let rssBytes = (obj["rss_bytes"] as? NSNumber)?.int64Value ?? 0
            let metalBytes = (obj["metal_bytes"] as? NSNumber)?.int64Value ?? 0
            let hadError = (obj["had_error"] as? Bool) ?? false
            let exprText = (obj["expr_text"] as? String) ?? ""

            var imageURLs: [URL] = []
            if let imgPaths = obj["images"] as? [String] {
                for p in imgPaths where FileManager.default.fileExists(atPath: p) {
                    imageURLs.append(URL(fileURLWithPath: p))
                }
            }

            var inlineDF: InlineDataFramePayload? = nil
            if let dfObj = obj["dataframe"] as? [String: Any],
               let dfBytes = try? JSONSerialization.data(withJSONObject: dfObj) {
                inlineDF = try? JSONDecoder().decode(InlineDataFramePayload.self, from: dfBytes)
            }

            var parsedVars: [KernelVariableInfo] = []
            if let varsArr = obj["variables"] as? [[String: Any]],
               let varsBytes = try? JSONSerialization.data(withJSONObject: varsArr) {
                parsedVars = (try? JSONDecoder().decode([KernelVariableInfo].self, from: varsBytes)) ?? []
            }

            stateLock.lock()
            if !exprText.isEmpty && inlineDF == nil {
                let current = streamBuffer.snapshot()
                _ = streamBuffer.appendChunk((current.isEmpty || current.hasSuffix("\n")) ? exprText : ("\n" + exprText))
            }
            let finalOutput = streamBuffer.snapshot().trimmingCharacters(in: .newlines)
            let prevRSS = lastKnownRSSBytes
            lastKnownRSSBytes = rssBytes
            let deltaBytes = prevRSS > 0 ? (rssBytes - prevRSS) : 0
            let cont = activeContinuation
            activeContinuation = nil
            activeOnStream = nil
            stateLock.unlock()

            SharedMemoryService.shared.updateLiveVariables(
                for: notebookId,
                variables: parsedVars,
                rssBytes: rssBytes,
                metalBytes: metalBytes
            )

            let telemetry = CellExecutionTelemetry(
                durationMs: durationMs,
                memoryDeltaBytes: deltaBytes,
                peakRSSBytes: rssBytes,
                metalAllocatedBytes: metalBytes,
                isCachedBinary: false
            )

            cont?.resume(returning: LocalKernelRunOutcome(
                stdoutText: finalOutput,
                imageURLs: imageURLs,
                inlineDataFrame: inlineDF,
                variables: parsedVars,
                telemetry: telemetry,
                hadError: hadError
            ))
        }
    }

    private static func buildPythonWorkerScript(sessionId: String) -> String {
        let shmBridge = SharedMemoryService.shared.getPythonBridgeCode(sessionId: sessionId)
        return """
        import sys as _mc_sys
        import os as _mc_os
        import io as _mc_io
        import ast as _mc_ast
        import time as _mc_time
        import json as _mc_json
        import base64 as _mc_b64
        import traceback as _mc_tb
        import resource as _mc_res
        import warnings as _mc_warnings
        import builtins as _mc_builtins

        _mc_warnings.filterwarnings("ignore", message=".*FigureCanvasAgg is non-interactive.*")

        _MC_PROTO_IN = _mc_sys.__stdin__
        _MC_PROTO_OUT = _mc_sys.__stdout__

        # Persistent User Namespace
        _MC_GLOBALS = {"__name__": "__main__", "__builtins__": __builtins__}
        _MC_DISPLAYED_DF = None
        _MC_CELL_OUTPUT_FILES = []
        _MC_CAPTURED_FIG_IDS = set()
        _MC_RICH_SEQ = 0

        # Inject Zero-Copy POSIX SHM Bridge into user globals
        exec(\(_pythonTripleQuotedLiteral(shmBridge)), _MC_GLOBALS)

        def _mc_extract_df_payload(obj, var_name, artifacts_dir, cell_tag):
            cls_name = type(obj).__name__
            mod_name = getattr(type(obj), "__module__", "")
            # Convert Polars DataFrame cleanly if encountered
            if cls_name == "DataFrame" and "polars" in mod_name:
                try:
                    total_rows, total_cols = obj.height, obj.width
                    cols = [str(c) for c in obj.columns[:60]]
                    dtypes = {str(c): str(obj.schema[c]) for c in cols}
                    sub = obj.select(cols).head(250)
                    rows = [[("" if v is None else str(v)) for v in row] for row in sub.iter_rows()]
                    stats = {}
                    csv_path = _mc_os.path.join(artifacts_dir, f"{cell_tag}_df.csv")
                    try:
                        obj.head(5000).write_csv(csv_path)
                    except Exception:
                        csv_path = None
                    return {
                        "variableName": var_name or "polars.DataFrame",
                        "totalRows": int(total_rows),
                        "totalCols": int(total_cols),
                        "columns": cols,
                        "dtypes": dtypes,
                        "stats": stats,
                        "rows": rows,
                        "csvExportPath": csv_path
                    }
                except Exception:
                    return None

            # Pandas DataFrame
            if cls_name == "DataFrame" and hasattr(obj, "columns") and hasattr(obj, "iloc"):
                try:
                    total_rows, total_cols = int(obj.shape[0]), int(obj.shape[1])
                    raw_cols = list(obj.columns[:60])
                    cols = [str(c) for c in raw_cols]
                    dtypes = {}
                    stats = {}
                    for c, c_name in zip(raw_cols, cols):
                        s = obj[c]
                        dt = s.dtype
                        dtypes[c_name] = str(dt)
                        kind = getattr(dt, "kind", "")
                        if kind in ("i", "u"):
                            st = {"nullCount": 0, "minVal": None, "maxVal": None, "meanVal": None}
                            if total_rows > 0:
                                arr = s.to_numpy(copy=False)
                                st["minVal"] = float(arr.min())
                                st["maxVal"] = float(arr.max())
                                st["meanVal"] = float(arr.mean())
                        elif kind == "f":
                            arr = s.to_numpy(copy=False)
                            null_cnt = int((arr != arr).sum())
                            st = {"nullCount": null_cnt, "minVal": None, "maxVal": None, "meanVal": None}
                            if total_rows > null_cnt:
                                valid = arr[arr == arr] if null_cnt else arr
                                st["minVal"] = float(valid.min())
                                st["maxVal"] = float(valid.max())
                                st["meanVal"] = float(valid.mean())
                        else:
                            st = {"nullCount": int(s.isna().sum()), "minVal": None, "maxVal": None, "meanVal": None}
                        stats[c_name] = st
                    head_df = obj.iloc[:250, :len(raw_cols)]
                    rows = []
                    for row_tuple in head_df.itertuples(index=False, name=None):
                        rows.append([("" if (v is None or (isinstance(v, float) and v != v)) else str(v)) for v in row_tuple])
                    csv_path = _mc_os.path.join(artifacts_dir, f"{cell_tag}_df.csv")
                    try:
                        if total_rows <= 250 and len(raw_cols) == total_cols:
                            import csv as _mc_csv
                            with open(csv_path, "w", newline="", encoding="utf-8") as _cf:
                                _cw = _mc_csv.writer(_cf)
                                _cw.writerow(cols)
                                _cw.writerows(rows)
                        else:
                            obj.head(5000).to_csv(csv_path, index=False)
                    except Exception:
                        csv_path = None
                    return {
                        "variableName": var_name or "DataFrame",
                        "totalRows": total_rows,
                        "totalCols": total_cols,
                        "columns": cols,
                        "dtypes": dtypes,
                        "stats": stats,
                        "rows": rows,
                        "csvExportPath": csv_path
                    }
                except Exception:
                    return None
            return None

        _MC_RICH_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg", ".pdf", ".md", ".markdown", ".html", ".htm"}

        def _mc_next_artifact_path(ext):
            global _MC_RICH_SEQ
            _MC_RICH_SEQ += 1
            try:
                _mc_os.makedirs(_MC_CUR_ARTIFACTS, exist_ok=True)
            except Exception:
                pass
            clean_ext = ext.lstrip(".")
            return _mc_os.path.join(_MC_CUR_ARTIFACTS, f"{_MC_CUR_TAG}_rich{_MC_RICH_SEQ}.{clean_ext}")

        def _mc_record_output_file(path_val):
            try:
                p = _mc_os.path.realpath(_mc_os.path.abspath(_mc_os.fspath(path_val)))
                if _mc_os.path.isfile(p) and _mc_os.path.getsize(p) > 0:
                    if p not in _MC_CELL_OUTPUT_FILES:
                        _MC_CELL_OUTPUT_FILES.append(p)
                    return True
            except Exception:
                pass
            return False

        def _mc_save_mpl_fig_obj(fig):
            try:
                if fig is None:
                    return False
                has_content = bool(
                    getattr(fig, "axes", None)
                    or getattr(fig, "texts", None)
                    or getattr(fig, "images", None)
                    or getattr(fig, "patches", None)
                    or getattr(fig, "artists", None)
                )
                if not has_content:
                    return False
                img_path = _mc_next_artifact_path("png")
                dpi_val = max(150, int(getattr(fig, "dpi", 150) or 150))
                try:
                    fig.savefig(img_path, dpi=dpi_val, bbox_inches="tight")
                except Exception:
                    fig.savefig(img_path, dpi=dpi_val)
                if _mc_record_output_file(img_path):
                    _MC_CAPTURED_FIG_IDS.add(id(fig))
                    return True
            except Exception:
                pass
            return False

        def _mc_capture_open_mpl_figures(close_after=False):
            if "matplotlib.pyplot" not in _mc_sys.modules:
                return
            try:
                plt = _mc_sys.modules["matplotlib.pyplot"]
                fignums = list(plt.get_fignums())
                for num in fignums:
                    fig = plt.figure(num)
                    if id(fig) not in _MC_CAPTURED_FIG_IDS:
                        _mc_save_mpl_fig_obj(fig)
                if close_after and fignums:
                    orig_close = getattr(plt, "_mc_orig_close", plt.close)
                    orig_close("all")
            except Exception:
                pass

        def _mc_patch_viz_modules():
            if "matplotlib.pyplot" in _mc_sys.modules:
                try:
                    plt = _mc_sys.modules["matplotlib.pyplot"]
                    if not getattr(plt, "_mc_patched", False):
                        plt._mc_orig_show = plt.show
                        plt._mc_orig_close = plt.close
                        def _mc_plt_show(*args, **kwargs):
                            _mc_capture_open_mpl_figures(close_after=True)
                        plt.show = _mc_plt_show
                        plt._mc_patched = True
                except Exception:
                    pass
            if "matplotlib.figure" in _mc_sys.modules:
                try:
                    mfig = _mc_sys.modules["matplotlib.figure"]
                    FigCls = getattr(mfig, "Figure", None)
                    if FigCls is not None and not getattr(FigCls, "_mc_patched", False):
                        _orig_fig_show = FigCls.show
                        _orig_fig_savefig = FigCls.savefig
                        def _mc_fig_show(self, *args, **kwargs):
                            _mc_save_mpl_fig_obj(self)
                        def _mc_fig_savefig(self, fname, *args, **kwargs):
                            res = _orig_fig_savefig(self, fname, *args, **kwargs)
                            if isinstance(fname, (str, _mc_os.PathLike)):
                                p_str = _mc_os.fspath(fname)
                                _, ext = _mc_os.path.splitext(p_str.lower())
                                if ext in _MC_RICH_EXTS:
                                    if _mc_record_output_file(p_str) and ext in {".png", ".jpg", ".jpeg", ".webp", ".svg"}:
                                        _MC_CAPTURED_FIG_IDS.add(id(self))
                            return res
                        FigCls.show = _mc_fig_show
                        FigCls.savefig = _mc_fig_savefig
                        FigCls._mc_patched = True
                except Exception:
                    pass
            if "PIL.Image" in _mc_sys.modules:
                try:
                    pil_mod = _mc_sys.modules["PIL.Image"]
                    ImgCls = getattr(pil_mod, "Image", None)
                    if ImgCls is not None and not getattr(ImgCls, "_mc_patched", False):
                        def _mc_pil_show(self, *args, **kwargs):
                            p = _mc_next_artifact_path("png")
                            self.save(p, format="PNG")
                            _mc_record_output_file(p)
                        ImgCls.show = _mc_pil_show
                        ImgCls._mc_patched = True
                except Exception:
                    pass
            if "plotly.basedatatypes" in _mc_sys.modules:
                try:
                    pbase = _mc_sys.modules["plotly.basedatatypes"]
                    BFCls = getattr(pbase, "BaseFigure", None)
                    if BFCls is not None and not getattr(BFCls, "_mc_patched", False):
                        def _mc_plotly_show(self, *args, **kwargs):
                            p = _mc_next_artifact_path("html")
                            self.write_html(p, include_plotlyjs="cdn")
                            _mc_record_output_file(p)
                        BFCls.show = _mc_plotly_show
                        BFCls._mc_patched = True
                except Exception:
                    pass
            if "plotly.io" in _mc_sys.modules:
                try:
                    pio = _mc_sys.modules["plotly.io"]
                    if not getattr(pio, "_mc_patched", False):
                        def _mc_pio_show(fig, *args, **kwargs):
                            if hasattr(fig, "write_html"):
                                p = _mc_next_artifact_path("html")
                                fig.write_html(p, include_plotlyjs="cdn")
                                _mc_record_output_file(p)
                        pio.show = _mc_pio_show
                        pio._mc_patched = True
                except Exception:
                    pass

        _mc_orig_import = _mc_builtins.__import__
        def _mc_import_hook(name, globals=None, locals=None, fromlist=(), level=0):
            mod = _mc_orig_import(name, globals, locals, fromlist, level)
            if name.startswith(("matplotlib", "PIL", "plotly")):
                _mc_patch_viz_modules()
            return mod
        _mc_builtins.__import__ = _mc_import_hook

        def _mc_try_capture_rich_value(o, allow_path_str=False):
            global _MC_DISPLAYED_DF
            if o is None:
                return False
            df_p = _mc_extract_df_payload(o, "display", _MC_CUR_ARTIFACTS, _MC_CUR_TAG)
            if df_p is not None:
                _MC_DISPLAYED_DF = df_p
                return True

            cls_name = type(o).__name__
            mod_name = getattr(type(o), "__module__", "")

            # Existing rich file path passed to display("report.pdf" / Path("notes.md"))
            if isinstance(o, _mc_os.PathLike) or (allow_path_str and isinstance(o, str) and len(o) < 1024 and "\\n" not in o):
                try:
                    p_str = _mc_os.fspath(o) if isinstance(o, _mc_os.PathLike) else o
                    _, ext = _mc_os.path.splitext(p_str.lower())
                    if ext in _MC_RICH_EXTS and _mc_os.path.isfile(p_str):
                        return _mc_record_output_file(p_str)
                except Exception:
                    pass

            # Matplotlib Figure / Axes
            if "matplotlib" in mod_name:
                if hasattr(o, "savefig"):
                    return _mc_save_mpl_fig_obj(o)
                if hasattr(o, "figure") and hasattr(o.figure, "savefig"):
                    return _mc_save_mpl_fig_obj(o.figure)

            # PIL Image
            if "PIL" in mod_name and hasattr(o, "save"):
                try:
                    p = _mc_next_artifact_path("png")
                    o.save(p, format="PNG")
                    return _mc_record_output_file(p)
                except Exception:
                    pass

            # Plotly / Altair / Folium HTML-capable figures
            if hasattr(o, "write_html"):
                try:
                    p = _mc_next_artifact_path("html")
                    try:
                        o.write_html(p, include_plotlyjs="cdn")
                    except TypeError:
                        o.write_html(p)
                    return _mc_record_output_file(p)
                except Exception:
                    pass

            # IPython.display objects (Markdown, Latex, Math, SVG, Image, HTML, PDF) & _repr_*_ protocol
            if "IPython" in mod_name or any(hasattr(o, m) for m in ("_repr_markdown_", "_repr_latex_", "_repr_svg_", "_repr_png_", "_repr_jpeg_", "_repr_html_", "_repr_pdf_")):
                try:
                    if cls_name == "PDF" or hasattr(o, "_repr_pdf_"):
                        fn = getattr(o, "filename", None)
                        if fn and _mc_os.path.isfile(fn):
                            return _mc_record_output_file(fn)
                        raw_pdf = o._repr_pdf_() if hasattr(o, "_repr_pdf_") else getattr(o, "data", None)
                        if raw_pdf:
                            b = _mc_b64.b64decode(raw_pdf) if isinstance(raw_pdf, str) else raw_pdf
                            p = _mc_next_artifact_path("pdf")
                            with open(p, "wb") as f:
                                f.write(b)
                            return _mc_record_output_file(p)
                    if cls_name in ("Latex", "Math") or hasattr(o, "_repr_latex_"):
                        tex_s = o._repr_latex_() if hasattr(o, "_repr_latex_") else getattr(o, "data", "")
                        if isinstance(tex_s, str) and tex_s.strip():
                            s = tex_s.strip()
                            if not (s.startswith("$$") or s.startswith("\\[") or s.startswith("$")):
                                s = f"$$\\n{s}\\n$$"
                            p = _mc_next_artifact_path("md")
                            with open(p, "w", encoding="utf-8") as f:
                                f.write(s)
                            return _mc_record_output_file(p)
                    if cls_name == "Markdown" or hasattr(o, "_repr_markdown_"):
                        md_s = o._repr_markdown_() if hasattr(o, "_repr_markdown_") else getattr(o, "data", "")
                        if isinstance(md_s, str) and md_s.strip():
                            p = _mc_next_artifact_path("md")
                            with open(p, "w", encoding="utf-8") as f:
                                f.write(md_s)
                            return _mc_record_output_file(p)
                    if cls_name == "SVG" or hasattr(o, "_repr_svg_"):
                        fn = getattr(o, "filename", None)
                        if fn and _mc_os.path.isfile(fn):
                            return _mc_record_output_file(fn)
                        svg_s = o._repr_svg_() if hasattr(o, "_repr_svg_") else getattr(o, "data", "")
                        if isinstance(svg_s, str) and svg_s.strip():
                            p = _mc_next_artifact_path("svg")
                            with open(p, "w", encoding="utf-8") as f:
                                f.write(svg_s)
                            return _mc_record_output_file(p)
                    if cls_name == "Image" or hasattr(o, "_repr_png_") or hasattr(o, "_repr_jpeg_"):
                        fn = getattr(o, "filename", None)
                        if fn and _mc_os.path.isfile(fn):
                            return _mc_record_output_file(fn)
                        if hasattr(o, "_repr_png_"):
                            png_d = o._repr_png_()
                            if png_d:
                                b = _mc_b64.b64decode(png_d) if isinstance(png_d, str) else png_d
                                p = _mc_next_artifact_path("png")
                                with open(p, "wb") as f:
                                    f.write(b)
                                return _mc_record_output_file(p)
                        if hasattr(o, "_repr_jpeg_"):
                            jpg_d = o._repr_jpeg_()
                            if jpg_d:
                                b = _mc_b64.b64decode(jpg_d) if isinstance(jpg_d, str) else jpg_d
                                p = _mc_next_artifact_path("jpg")
                                with open(p, "wb") as f:
                                    f.write(b)
                                return _mc_record_output_file(p)
                        raw_d = getattr(o, "data", None)
                        if isinstance(raw_d, (bytes, bytearray)):
                            fmt = getattr(o, "format", "png") or "png"
                            p = _mc_next_artifact_path(fmt)
                            with open(p, "wb") as f:
                                f.write(raw_d)
                            return _mc_record_output_file(p)
                    if cls_name == "HTML" or hasattr(o, "_repr_html_"):
                        html_s = o._repr_html_() if hasattr(o, "_repr_html_") else getattr(o, "data", "")
                        if isinstance(html_s, str) and html_s.strip():
                            p = _mc_next_artifact_path("html")
                            with open(p, "w", encoding="utf-8") as f:
                                f.write(html_s)
                            return _mc_record_output_file(p)
                except Exception:
                    pass
            return False

        def _mc_display(*objs):
            for o in objs:
                if not _mc_try_capture_rich_value(o, allow_path_str=True):
                    print(repr(o) if not isinstance(o, str) else o)

        def _mc_display_markdown(text_str):
            if isinstance(text_str, str) and text_str.strip():
                p = _mc_next_artifact_path("md")
                with open(p, "w", encoding="utf-8") as f:
                    f.write(text_str)
                _mc_record_output_file(p)

        def _mc_display_pdf(pdf_path):
            _mc_record_output_file(pdf_path)

        _MC_GLOBALS["display"] = _mc_display
        _MC_GLOBALS["display_markdown"] = _mc_display_markdown
        _MC_GLOBALS["display_pdf"] = _mc_display_pdf
        _MC_CUR_ARTIFACTS = _mc_os.getcwd()
        _MC_CUR_TAG = "cell"

        _MC_SKIP_VARS = {
            "__name__", "__doc__", "__package__", "__loader__", "__spec__", "__builtins__",
            "display", "display_markdown", "display_pdf", "shm", "MicroCodeSHM", "In", "Out", "_"
        }
        _MC_VAR_CACHE = {}

        def _mc_collect_mutated_names(ast_tree):
            names = set()
            for node in _mc_ast.walk(ast_tree):
                if isinstance(node, _mc_ast.Name) and isinstance(node.ctx, (_mc_ast.Store, _mc_ast.Del)):
                    names.add(node.id)
                elif isinstance(node, _mc_ast.Call) and isinstance(node.func, _mc_ast.Attribute):
                    if isinstance(node.func.value, _mc_ast.Name):
                        names.add(node.func.value.id)
                elif isinstance(node, _mc_ast.Subscript) and isinstance(node.ctx, (_mc_ast.Store, _mc_ast.Del)):
                    if isinstance(node.value, _mc_ast.Name):
                        names.add(node.value.id)
            return names

        def _mc_inspect_variables(mutated_names=None):
            items = []
            live_keys = set()
            for k, v in list(_MC_GLOBALS.items()):
                if k.startswith("_") or k in _MC_SKIP_VARS:
                    continue
                t = type(v)
                t_name = t.__name__
                if t_name in ("module", "function", "type", "builtin_function_or_method", "method"):
                    continue
                live_keys.add(k)
                raw_shape = getattr(v, "shape", None)
                cache_sig = (id(v), tuple(raw_shape) if isinstance(raw_shape, tuple) else None, t_name)
                if mutated_names is not None and k not in mutated_names:
                    cached_entry = _MC_VAR_CACHE.get(k)
                    if cached_entry is not None and cached_entry[0] == cache_sig:
                        items.append(cached_entry[1])
                        if len(items) >= 60:
                            break
                        continue

                shape = ""
                dtype = t_name
                mem = 0
                cols = []
                sample = []
                preview = ""
                try:
                    if raw_shape is not None:
                        shape = str(tuple(int(x) for x in raw_shape))
                    elif isinstance(v, (list, tuple, set, dict, str, bytes)):
                        shape = f"len={len(v)}"

                    if hasattr(v, "dtype"):
                        dtype = str(v.dtype)
                    elif t_name == "DataFrame" and hasattr(v, "columns"):
                        cols = [str(c) for c in list(v.columns)[:30]]
                        dtype = f"{len(cols)} cols"

                    if hasattr(v, "nbytes"):
                        mem = int(v.nbytes)
                    elif hasattr(v, "memory_usage") and callable(v.memory_usage):
                        mem = int(v.memory_usage(index=False, deep=False).sum())
                    else:
                        mem = int(_mc_sys.getsizeof(v))

                    # Zero-copy sparkline & O(1) preview extraction (avoids multi-MB .flatten() & slow DataFrame.to_string())
                    if t_name == "DataFrame" and hasattr(v, "iloc") and hasattr(v, "columns"):
                        n_rows, n_cols = int(v.shape[0]), int(v.shape[1])
                        if n_rows > 0 and n_cols > 0:
                            for c in list(v.columns[:8]):
                                s_col = v[c]
                                if getattr(s_col.dtype, "kind", "") in ("i", "u", "f"):
                                    vals = s_col.iloc[:28].tolist()
                                    sample = [float(x) for x in vals if isinstance(x, (int, float)) and x == x]
                                    break
                            preview_pairs = [f"{c}={v[c].iloc[0]!r}" for c in list(v.columns[:4])]
                            preview = f"DataFrame[{n_rows}x{n_cols}] " + ", ".join(preview_pairs)
                        else:
                            preview = f"DataFrame[{n_rows}x{n_cols}]"
                    elif hasattr(v, "reshape") and hasattr(v, "dtype") and getattr(v.dtype, "kind", "") in ("i", "u", "f"):
                        view1d = v.reshape(-1)
                        n_take = min(28, int(view1d.shape[0]))
                        if n_take > 0:
                            vals = view1d[:n_take].tolist()
                            sample = [float(x) for x in vals if isinstance(x, (int, float)) and x == x]
                        head_vals = view1d[:min(4, n_take)].tolist()
                        preview = f"array(shape={shape}, dtype={dtype}, head={head_vals})"[:180]
                    elif isinstance(v, (list, tuple)) and len(v) > 0 and all(isinstance(x, (int, float)) for x in v[:16]):
                        sample = [float(x) for x in v[:28] if x == x]
                        preview = repr(v[:10])[:180]
                    else:
                        preview = repr(v)[:180]
                except Exception:
                    preview = f"<{t_name}>"

                entry = {
                    "name": str(k),
                    "typeName": t_name,
                    "shape": shape,
                    "dtype": dtype,
                    "memoryBytes": max(0, mem),
                    "preview": preview,
                    "columns": cols,
                    "numericSample": sample
                }
                _MC_VAR_CACHE[k] = (cache_sig, entry)
                items.append(entry)
                if len(items) >= 60:
                    break
            if len(_MC_VAR_CACHE) > len(live_keys):
                for dead_k in list(_MC_VAR_CACHE.keys()):
                    if dead_k not in live_keys:
                        _MC_VAR_CACHE.pop(dead_k, None)
            items.sort(key=lambda x: (-x["memoryBytes"], x["name"]))
            return items

        def _mc_get_rss_and_metal():
            # On macOS Darwin, ru_maxrss is in bytes
            rss = int(_mc_res.getrusage(_mc_res.RUSAGE_SELF).ru_maxrss)
            metal = 0
            try:
                if "mlx.core" in _mc_sys.modules:
                    mx = _mc_sys.modules["mlx.core"]
                    if hasattr(mx, "metal") and hasattr(mx.metal, "get_active_memory"):
                        metal += int(mx.metal.get_active_memory())
            except Exception:
                pass
            try:
                if "torch" in _mc_sys.modules:
                    th = _mc_sys.modules["torch"]
                    if hasattr(th, "mps") and hasattr(th.mps, "current_allocated_memory"):
                        metal += int(th.mps.current_allocated_memory())
            except Exception:
                pass
            return rss, metal

        def _mc_emit_packet(obj):
            raw = _mc_json.dumps(obj, ensure_ascii=False).encode("utf-8")
            b64 = _mc_b64.b64encode(raw).decode("ascii")
            _MC_PROTO_OUT.write("\\x02MCJ:" + b64 + "\\x03\\n")
            _MC_PROTO_OUT.flush()

        while True:
            line = _MC_PROTO_IN.readline()
            if not line:
                break
            if not line.startswith("MC_EXEC:"):
                continue

            b64_cmd = line[8:].strip()
            try:
                cmd = _mc_json.loads(_mc_b64.b64decode(b64_cmd).decode("utf-8"))
            except Exception as e:
                _mc_emit_packet({"event": "done", "duration_ms": 0, "rss_bytes": 0, "metal_bytes": 0, "had_error": True, "expr_text": f"Protocol decode error: {e}", "images": [], "variables": []})
                continue

            code = cmd.get("code", "")
            workdir = cmd.get("workdir", "")
            _MC_CUR_ARTIFACTS = cmd.get("artifacts_dir", workdir)
            _MC_CUR_TAG = cmd.get("cell_tag", "cell")
            _MC_DISPLAYED_DF = None
            _MC_CELL_OUTPUT_FILES = []
            _MC_CAPTURED_FIG_IDS = set()
            _MC_RICH_SEQ = 0

            if workdir and _mc_os.path.isdir(workdir):
                try:
                    _mc_os.chdir(workdir)
                except Exception:
                    pass
                if workdir not in _mc_sys.path:
                    _mc_sys.path.insert(0, workdir)

            _mc_patch_viz_modules()

            def _mc_snapshot_rich_files(base_dir):
                snap = {}
                if not base_dir or not _mc_os.path.isdir(base_dir):
                    return snap
                scan_dirs = [base_dir]
                for sub in ("figures", "outputs", "plots", "reports"):
                    sd = _mc_os.path.join(base_dir, sub)
                    if _mc_os.path.isdir(sd):
                        scan_dirs.append(sd)
                for d in scan_dirs:
                    try:
                        for entry in _mc_os.scandir(d):
                            if entry.is_file():
                                _, ext = _mc_os.path.splitext(entry.name.lower())
                                if ext in _MC_RICH_EXTS:
                                    try:
                                        st = entry.stat()
                                        snap[_mc_os.path.realpath(entry.path)] = (st.st_mtime_ns, st.st_size)
                                    except Exception:
                                        pass
                    except Exception:
                        pass
                return snap

            _mc_before_files = _mc_snapshot_rich_files(workdir)

            # Prevent accidental user `input()` from reading kernel command pipe
            _mc_sys.stdin = _mc_io.StringIO("")
            t0 = _mc_time.perf_counter()
            had_error = False
            expr_text = ""
            df_payload = None
            saved_images = []
            mutated_names = None

            try:
                tree = _mc_ast.parse(code, filename="<cell>", mode="exec")
                mutated_names = _mc_collect_mutated_names(tree)
                last_expr_name = None
                if tree.body and isinstance(tree.body[-1], _mc_ast.Expr):
                    last_node = tree.body.pop()
                    if isinstance(last_node.value, _mc_ast.Name):
                        last_expr_name = last_node.value.id
                    if tree.body:
                        exec(compile(tree, "<cell>", "exec"), _MC_GLOBALS)
                    eval_expr = _mc_ast.Expression(last_node.value)
                    _mc_ast.fix_missing_locations(eval_expr)
                    val = eval(compile(eval_expr, "<cell>", "eval"), _MC_GLOBALS)
                    if val is not None:
                        _MC_GLOBALS["_"] = val
                        df_payload = _mc_extract_df_payload(val, last_expr_name or "Result", _MC_CUR_ARTIFACTS, _MC_CUR_TAG)
                        if df_payload is None:
                            if not _mc_try_capture_rich_value(val, allow_path_str=False):
                                val_mod = getattr(type(val), "__module__", "")
                                if not ("matplotlib" in val_mod or "seaborn" in val_mod):
                                    expr_text = repr(val)
                else:
                    exec(compile(tree, "<cell>", "exec"), _MC_GLOBALS)
            except KeyboardInterrupt:
                had_error = True
                mutated_names = None
                print("\\n⏹ Interrupted by user (variables in RAM preserved).", flush=True)
            except SystemExit as se:
                mutated_names = None
                print(f"\\nℹ️ Cell exited with SystemExit({se.code}). Kernel remains warm.", flush=True)
            except SyntaxError:
                had_error = True
                mutated_names = None
                _mc_tb.print_exc(limit=4)
            except Exception:
                had_error = True
                mutated_names = None
                exc_type, exc_val, exc_tb = _mc_sys.exc_info()
                tb_lines = _mc_tb.format_exception(exc_type, exc_val, exc_tb.tb_next if exc_tb and exc_tb.tb_next else exc_tb)
                _mc_sys.stdout.write("".join(tb_lines))
                _mc_sys.stdout.flush()

            # Capture any still-open Matplotlib figures that did not explicitly call plt.show()
            _mc_capture_open_mpl_figures(close_after=True)

            # Collect any rich files (.png, .svg, .pdf, .md, .html, etc.) newly written in workdir during this cell run
            _mc_after_files = _mc_snapshot_rich_files(workdir)
            for _f_path, _f_stat in sorted(_mc_after_files.items(), key=lambda kv: kv[1][0]):
                if _f_path not in _mc_before_files or _mc_before_files[_f_path] != _f_stat:
                    _mc_record_output_file(_f_path)

            saved_images = list(_MC_CELL_OUTPUT_FILES)

            if df_payload is None and _MC_DISPLAYED_DF is not None:
                df_payload = _MC_DISPLAYED_DF

            dt_ms = (_mc_time.perf_counter() - t0) * 1000.0
            _mc_sys.stdout.flush()
            _mc_sys.stderr.flush()
            rss_b, metal_b = _mc_get_rss_and_metal()
            vars_list = _mc_inspect_variables(mutated_names)

            _mc_emit_packet({
                "event": "done",
                "duration_ms": round(dt_ms, 3),
                "rss_bytes": rss_b,
                "metal_bytes": metal_b,
                "had_error": had_error,
                "expr_text": expr_text,
                "images": saved_images,
                "dataframe": df_payload,
                "variables": vars_list
            })
        """
    }

    private static func _pythonTripleQuotedLiteral(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"\"\"", with: "\\\"\\\"\\\"")
        return "\"\"\"\(escaped)\"\"\""
    }
}

// MARK: - Polyglot Non-Blocking 60Hz Streaming Runner & SHA-256 Binary Cache Engine

final class PolyglotStreamingAndCacheEngine {
    static let shared = PolyglotStreamingAndCacheEngine()

    private let activeProcessesLock = NSLock()
    private var activeProcessesByCell: [UUID: Process] = [:]

    private init() {}

    func cancelProcess(for cellId: UUID) {
        activeProcessesLock.lock()
        let proc = activeProcessesByCell.removeValue(forKey: cellId)
        activeProcessesLock.unlock()
        if let proc, proc.isRunning {
            proc.terminate()
        }
    }

    /// Runs any external process with non-blocking `readabilityHandler` draining on BOTH `stdout` and `stderr`,
    /// completely preventing macOS 64KB pipe deadlocks while streaming `\r`-coalesced output at 60Hz.
    func runStreamingProcess(
        cellId: UUID,
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        onStream: ((String) -> Void)? = nil
    ) async throws -> (output: String, exitCode: Int32, durationMs: Double) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let streamBuf = TerminalStreamBuffer()
        let emitLock = NSLock()
        var lastEmit: CFAbsoluteTime = 0

        func ingest(_ data: Data) {
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let snap = streamBuf.appendChunk(text)
            let now = CFAbsoluteTimeGetCurrent()
            emitLock.lock()
            let shouldEmit = (now - lastEmit >= 0.020)
            if shouldEmit { lastEmit = now }
            emitLock.unlock()
            if shouldEmit, let onStream {
                DispatchQueue.main.async { onStream(snap) }
            }
        }

        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = arguments
        proc.currentDirectoryURL = workingDirectory
        proc.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { fh in
            ingest(fh.availableData)
        }
        errPipe.fileHandleForReading.readabilityHandler = { fh in
            ingest(fh.availableData)
        }

        activeProcessesLock.lock()
        activeProcessesByCell[cellId] = proc
        activeProcessesLock.unlock()

        return try await withCheckedThrowingContinuation { continuation in
            proc.terminationHandler = { [weak self] finished in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                // Drain any residual bytes after process exit
                let remOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                if !remOut.isEmpty, let s = String(data: remOut, encoding: .utf8) {
                    _ = streamBuf.appendChunk(s)
                }
                let remErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                if !remErr.isEmpty, let s = String(data: remErr, encoding: .utf8) {
                    _ = streamBuf.appendChunk(s)
                }

                self?.activeProcessesLock.lock()
                self?.activeProcessesByCell.removeValue(forKey: cellId)
                self?.activeProcessesLock.unlock()

                let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                let finalSnap = streamBuf.snapshot()
                continuation.resume(returning: (finalSnap, finished.terminationStatus, dtMs))
            }

            do {
                try proc.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                self.activeProcessesLock.lock()
                self.activeProcessesByCell.removeValue(forKey: cellId)
                self.activeProcessesLock.unlock()
                continuation.resume(throwing: error)
            }
        }
    }

    /// Compiles (with SHA-256 content-addressed binary caching) and runs Rust, C++, or Objective-C cells.
    /// Cache hits execute in `< 2ms` with zero compiler invocation!
    func runCompiledCellWithCache(
        cellId: UUID,
        languageTag: String,
        sourceExtension: String,
        sourceCode: String,
        compilerExecutable: String,
        compilerArgsBuilder: (_ sourcePath: String, _ binaryPath: String) -> [String],
        workingDirectory: URL,
        environment: [String: String],
        onStream: @escaping (String) -> Void
    ) async -> (output: String, telemetry: CellExecutionTelemetry, hadError: Bool) {
        let cacheDir = workingDirectory.appendingPathComponent(".cell-bin-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let cacheKeyInput = "\(languageTag)|\(compilerExecutable)|v2|\(sourceCode)"
        let digest = SHA256.hash(data: Data(cacheKeyInput.utf8))
        let hashHex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let cachedBinaryURL = cacheDir.appendingPathComponent("\(languageTag)_\(hashHex)")

        var wasCached = FileManager.default.isExecutableFile(atPath: cachedBinaryURL.path)
        var compileMs: Double = 0

        if !wasCached {
            let tempSrcURL = cacheDir.appendingPathComponent("src_\(hashHex).\(sourceExtension)")
            do {
                try sourceCode.write(to: tempSrcURL, atomically: true, encoding: .utf8)
                let execURL: URL
                let args: [String]
                if compilerExecutable.contains("/") {
                    execURL = URL(fileURLWithPath: compilerExecutable)
                    args = compilerArgsBuilder(tempSrcURL.path, cachedBinaryURL.path)
                } else {
                    execURL = URL(fileURLWithPath: "/usr/bin/env")
                    args = [compilerExecutable] + compilerArgsBuilder(tempSrcURL.path, cachedBinaryURL.path)
                }

                let compRes = try await runStreamingProcess(
                    cellId: cellId,
                    executableURL: execURL,
                    arguments: args,
                    workingDirectory: workingDirectory,
                    environment: environment,
                    onStream: nil
                )
                compileMs = compRes.durationMs
                try? FileManager.default.removeItem(at: tempSrcURL)

                if compRes.exitCode != 0 {
                    try? FileManager.default.removeItem(at: cachedBinaryURL)
                    return (
                        "❌ Compilation Failed:\n" + compRes.output,
                        CellExecutionTelemetry(durationMs: compileMs, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false),
                        true
                    )
                }
                pruneBinaryCacheIfNeeded(in: cacheDir, maxEntries: 48)
            } catch {
                try? FileManager.default.removeItem(at: tempSrcURL)
                return (
                    "❌ Compiler Error: \(error.localizedDescription)",
                    CellExecutionTelemetry(durationMs: 0, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false),
                    true
                )
            }
        } else {
            wasCached = true
        }

        // Execute compiled native binary
        do {
            let runRes = try await runStreamingProcess(
                cellId: cellId,
                executableURL: cachedBinaryURL,
                arguments: [],
                workingDirectory: workingDirectory,
                environment: environment,
                onStream: onStream
            )
            let totalMs = compileMs + runRes.durationMs
            return (
                runRes.output,
                CellExecutionTelemetry(
                    durationMs: totalMs,
                    memoryDeltaBytes: 0,
                    peakRSSBytes: 0,
                    metalAllocatedBytes: 0,
                    isCachedBinary: wasCached
                ),
                runRes.exitCode != 0
            )
        } catch {
            return (
                "❌ Execution Error: \(error.localizedDescription)",
                CellExecutionTelemetry(durationMs: compileMs, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: wasCached),
                true
            )
        }
    }

    private func pruneBinaryCacheIfNeeded(in dir: URL, maxEntries: Int) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ), urls.count > maxEntries else { return }

        let sorted = urls.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
        for stale in sorted.dropFirst(maxEntries) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}

// MARK: - Warm Persistent Julia Kernel Pool (Eliminates Julia TTFX JIT Penalty Across Cells)

final class LocalPersistentJuliaKernelPool {
    static let shared = LocalPersistentJuliaKernelPool()

    private let lock = NSLock()
    private var workers: [UUID: LocalPersistentJuliaWorker] = [:]

    private init() {}

    func execute(
        notebookId: UUID,
        cellId: UUID,
        juliaPath: String,
        workingDirectory: URL,
        code: String,
        onStream: @escaping (String) -> Void
    ) async -> (output: String, telemetry: CellExecutionTelemetry, hadError: Bool) {
        let worker: LocalPersistentJuliaWorker = {
            lock.lock()
            defer { lock.unlock() }
            if let existing = workers[notebookId], existing.juliaPath == juliaPath {
                return existing
            }
            workers[notebookId]?.shutdown()
            let w = LocalPersistentJuliaWorker(juliaPath: juliaPath, workingDirectory: workingDirectory)
            workers[notebookId] = w
            return w
        }()
        return await worker.execute(code: code, workingDirectory: workingDirectory, onStream: onStream)
    }

    func restart(notebookId: UUID) {
        lock.lock()
        let w = workers.removeValue(forKey: notebookId)
        lock.unlock()
        w?.shutdown()
    }
}

final class LocalPersistentJuliaWorker {
    let juliaPath: String
    private var workingDirectory: URL
    private let lock = NSLock()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var framingBuffer = Data()
    private let streamBuffer = TerminalStreamBuffer()
    private var activeOnStream: ((String) -> Void)?
    private var activeContinuation: CheckedContinuation<(String, CellExecutionTelemetry, Bool), Never>?

    init(juliaPath: String, workingDirectory: URL) {
        self.juliaPath = juliaPath
        self.workingDirectory = workingDirectory
    }

    func shutdown() {
        lock.lock()
        let p = process
        let cont = activeContinuation
        activeContinuation = nil
        activeOnStream = nil
        process = nil
        stdinHandle = nil
        lock.unlock()
        if let p, p.isRunning { p.terminate() }
        cont?.resume(returning: ("⏹ Julia kernel stopped.", CellExecutionTelemetry(durationMs: 0, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false), false))
    }

    func execute(
        code: String,
        workingDirectory: URL,
        onStream: @escaping (String) -> Void
    ) async -> (String, CellExecutionTelemetry, Bool) {
        self.workingDirectory = workingDirectory
        do {
            try ensureStarted()
        } catch {
            return ("❌ Failed to start Julia daemon: \(error.localizedDescription)", CellExecutionTelemetry(durationMs: 0, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false), true)
        }

        let packedPayload = workingDirectory.path + "\u{0000}" + code
        guard let data = packedPayload.data(using: .utf8),
              let handle = currentStdin() else {
            return ("❌ Failed to encode Julia command.", CellExecutionTelemetry(durationMs: 0, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false), true)
        }

        let line = "MC_JL:" + data.base64EncodedString() + "\n"
        return await withCheckedContinuation { cont in
            lock.lock()
            streamBuffer.reset()
            framingBuffer.removeAll(keepingCapacity: true)
            activeOnStream = onStream
            activeContinuation = cont
            lock.unlock()

            do {
                if let d = line.data(using: .utf8) {
                    try handle.write(contentsOf: d)
                }
            } catch {
                lock.lock()
                let pending = activeContinuation
                activeContinuation = nil
                activeOnStream = nil
                lock.unlock()
                pending?.resume(returning: ("❌ Julia write error: \(error.localizedDescription)", CellExecutionTelemetry(durationMs: 0, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false), true))
            }
        }
    }

    private func currentStdin() -> FileHandle? {
        lock.lock()
        defer { lock.unlock() }
        return stdinHandle
    }

    private func ensureStarted() throws {
        lock.lock()
        if let p = process, p.isRunning, stdinHandle != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let workerFile = workingDirectory.appendingPathComponent(".mc_persistent_julia_worker.jl")
        let script = """
        using Base64
        const _MC_MOD = Module(:MCWorkspace)
        Core.eval(_MC_MOD, :(using Base))
        while !eof(stdin)
            line = readline(stdin)
            startswith(line, "MC_JL:") || continue
            b64 = strip(line[7:end])
            raw = String(base64decode(b64))
            t0 = time_ns()
            had_err = false
            try
                parts = split(raw, '\\0'; limit=2)
                if length(parts) == 2
                    wd = String(parts[1])
                    isdir(wd) && cd(wd)
                    code_str = String(parts[2])
                else
                    code_str = raw
                end
                val = Base.include_string(_MC_MOD, code_str, "cell")
                if val !== nothing
                    println(repr(val))
                end
            catch e
                had_err = true
                showerror(stdout, e, catch_backtrace())
                println()
            end
            flush(stdout)
            flush(stderr)
            dt_ms = (time_ns() - t0) / 1e6
            err_flag = had_err ? "true" : "false"
            pkt = "{\\"ms\\":" * string(round(dt_ms, digits=2)) * ",\\"err\\":" * err_flag * "}"
            write(stdout, "\\x02MCJ:" * base64encode(pkt) * "\\x03\\n")
            flush(stdout)
        end
        """
        try script.write(to: workerFile, atomically: true, encoding: .utf8)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: juliaPath)
        p.arguments = ["--startup-file=no", workerFile.path]
        p.currentDirectoryURL = workingDirectory

        let inP = Pipe()
        let outP = Pipe()
        let errP = Pipe()
        p.standardInput = inP
        p.standardOutput = outP
        p.standardError = errP

        outP.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let d = fh.availableData
            guard !d.isEmpty else { return }
            self?.consumeStdout(d)
        }
        errP.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let d = fh.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            self?.emitUser(s)
        }

        try p.run()
        lock.lock()
        self.process = p
        self.stdinHandle = inP.fileHandleForWriting
        lock.unlock()
    }

    private func emitUser(_ s: String) {
        lock.lock()
        let snap = streamBuffer.appendChunk(s)
        let cb = activeOnStream
        lock.unlock()
        if let cb {
            DispatchQueue.main.async { cb(snap) }
        }
    }

    private func consumeStdout(_ chunk: Data) {
        let marker = Data([0x02, 0x4D, 0x43, 0x4A, 0x3A])
        let endByte: UInt8 = 0x03

        lock.lock()
        framingBuffer.append(chunk)
        lock.unlock()

        while true {
            lock.lock()
            if let r = framingBuffer.range(of: marker) {
                if r.lowerBound > framingBuffer.startIndex {
                    let pre = framingBuffer.subdata(in: framingBuffer.startIndex..<r.lowerBound)
                    framingBuffer.removeSubrange(framingBuffer.startIndex..<r.lowerBound)
                    lock.unlock()
                    if let s = String(data: pre, encoding: .utf8) { emitUser(s) }
                    continue
                }
                let start = framingBuffer.index(framingBuffer.startIndex, offsetBy: marker.count)
                if let end = framingBuffer[start...].firstIndex(of: endByte) {
                    let b64D = framingBuffer.subdata(in: start..<end)
                    var remEnd = framingBuffer.index(after: end)
                    if remEnd < framingBuffer.endIndex && framingBuffer[remEnd] == 0x0A {
                        remEnd = framingBuffer.index(after: remEnd)
                    }
                    framingBuffer.removeSubrange(framingBuffer.startIndex..<remEnd)
                    let finalOut = streamBuffer.snapshot().trimmingCharacters(in: .newlines)
                    let cont = activeContinuation
                    activeContinuation = nil
                    activeOnStream = nil
                    lock.unlock()

                    var ms: Double = 0
                    var hadErr = false
                    if let b64S = String(data: b64D, encoding: .utf8),
                       let dec = Data(base64Encoded: b64S),
                       let obj = try? JSONSerialization.jsonObject(with: dec) as? [String: Any] {
                        ms = (obj["ms"] as? NSNumber)?.doubleValue ?? 0
                        hadErr = (obj["err"] as? Bool) ?? false
                    }
                    cont?.resume(returning: (
                        finalOut,
                        CellExecutionTelemetry(durationMs: ms, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false),
                        hadErr
                    ))
                    continue
                }
            } else if framingBuffer.count > 4 {
                let n = framingBuffer.count - 4
                let pre = framingBuffer.subdata(in: 0..<n)
                framingBuffer.removeSubrange(0..<n)
                lock.unlock()
                if let s = String(data: pre, encoding: .utf8) { emitUser(s) }
                continue
            }
            lock.unlock()
            break
        }
    }
}

// MARK: - Retina Plot Image Cache (`NSCache` Off-Layout Decoding)

final class NotebookImageCache {
    static let shared = NotebookImageCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 96
    }

    func image(for url: URL) -> NSImage? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let fsize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let key = "\(url.path)#\(Int64(mtime * 1000))#\(fsize)" as NSString
        if let hit = cache.object(forKey: key) {
            return hit
        }
        guard let decoded = NSImage(contentsOf: url) else { return nil }
        if url.pathExtension.lowercased() == "svg", decoded.size.width > 0, decoded.size.width < 120 {
            let scale = 720.0 / decoded.size.width
            decoded.size = NSSize(width: decoded.size.width * scale, height: max(120, decoded.size.height * scale))
        }
        cache.setObject(decoded, forKey: key)
        return decoded
    }
}

// MARK: - Off-MainActor Atomic WAL Persistence Actor (Eliminates UserDefaults / cfprefsd Stalls)

actor NotebookPersistenceActor {
    static let shared = NotebookPersistenceActor()

    private var walFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("MicroCode/notebooks_wal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notebooks_state_v2.json")
    }

    func writeWALSnapshot(payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }
        try? data.write(to: walFileURL, options: [.atomic])
    }

    nonisolated func loadWALSnapshotSync() -> Data? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base
            .appendingPathComponent("MicroCode/notebooks_wal", isDirectory: true)
            .appendingPathComponent("notebooks_state_v2.json")
        return try? Data(contentsOf: url)
    }

    func writeDataAtomically(_ data: Data, to url: URL) {
        try? data.write(to: url, options: [.atomic])
    }
}
