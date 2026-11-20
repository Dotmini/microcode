//
//  AgentDesktopBridge.swift
//  MicroCode
//
//  Native In-Process C-ABI FFI (`libagent_desktop_ffi.dylib` ABI v7) & Full 57-Command
//  Semantic Accessibility Engine powered by `vercel-labs/agent-desktop` (Apache-2.0).
//
//  Capabilities:
//  - Sub-millisecond In-Process FFI (`ad_init`, `ad_adapter_create_with_session`,
//    `ad_snapshot`, `ad_execute_by_ref_timeout`, `ad_status`, `ad_trace_show`, `ad_trace_export`)
//  - Snapshot-Qualified Element Refs (`@<snapshot_id>:e<N>`) with `STALE_REF` & `AMBIGUOUS_TARGET` protection
//  - Multi-Agent Swarm Session Isolation (`mc-<sessionId>` namespaces)
//  - Full CLI surface support (`--skeleton`, `--root @ref`, `find`, `get`, `is`, `menubar`,
//    `menu`, `menu-bar-extras`, `dock`, `sheet`, `popover`, `Notification Center`, `cursor-overlay`, `sandbox`)
//  - Zero-leak `--stdin` secret piping & MicroCode Hard Security Denylist (`Keychain`, `1Password`, `SecurityAgent`)
//

import Foundation
import Darwin

// MARK: - Dynamic C-ABI FFI Bindings (`agent_desktop.h` ABI v7)

public final class AgentDesktopFFILoader: @unchecked Sendable {
    public static let shared = AgentDesktopFFILoader()

    public static let expectedABIMajor: UInt32 = 7
    public static let expectedActionSize: Int = 96

    // AdSnapshotSurface discriminants
    public enum Surface: Int32 {
        case window = 0
        case focused = 1
        case menu = 2
        case menubar = 3
        case sheet = 4
        case popover = 5
        case alert = 6
        case desktop = 7
        case taskbar = 8
        case systemTray = 9
        case quickSettings = 10
        case notificationCenter = 11
        case toolbar = 12
        case dock = 13
        case spotlight = 14
        case menuBarExtras = 15

        public static func from(name: String?) -> Surface {
            switch (name ?? "window").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "window", "": return .window
            case "focused", "focus": return .focused
            case "menu": return .menu
            case "menubar", "menu-bar": return .menubar
            case "sheet": return .sheet
            case "popover": return .popover
            case "alert": return .alert
            case "desktop": return .desktop
            case "notification", "notifications", "notification-center", "notification_center": return .notificationCenter
            case "toolbar": return .toolbar
            case "dock": return .dock
            case "spotlight": return .spotlight
            case "menu-bar-extras", "menu_bar_extras", "extras", "statusbar": return .menuBarExtras
            default: return .window
            }
        }
    }

    // AdActionKind discriminants
    public enum ActionKind: Int32 {
        case click = 0
        case doubleClick = 1
        case rightClick = 2
        case tripleClick = 3
        case setValue = 4
        case setFocus = 5
        case expand = 6
        case collapse = 7
        case select = 8
        case toggle = 9
        case check = 10
        case uncheck = 11
        case scroll = 12
        case scrollTo = 13
        case pressKey = 14
        case keyDown = 15
        case keyUp = 16
        case typeText = 17
        case clear = 18
        case hover = 19
        case drag = 20

        public static func from(name: String) -> ActionKind? {
            switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "click", "press": return .click
            case "double_click", "double-click", "doubleclick": return .doubleClick
            case "right_click", "right-click", "rightclick": return .rightClick
            case "triple_click", "triple-click", "tripleclick": return .tripleClick
            case "set_value", "set-value", "setvalue": return .setValue
            case "focus", "set_focus", "set-focus": return .setFocus
            case "expand": return .expand
            case "collapse": return .collapse
            case "select": return .select
            case "toggle": return .toggle
            case "check": return .check
            case "uncheck": return .uncheck
            case "scroll": return .scroll
            case "scroll_to", "scroll-to", "scrollto": return .scrollTo
            case "press_key", "press-key": return .pressKey
            case "type", "type_text", "type-text": return .typeText
            case "clear": return .clear
            case "hover": return .hover
            default: return nil
            }
        }
    }

    // AdPolicyKind discriminants
    public enum PolicyKind: Int32 {
        case headless = 0
        case focusFallback = 1
        case headed = 2
    }

    private typealias FnInit = @convention(c) (UInt32) -> Int32
    private typealias FnActionSize = @convention(c) () -> Int
    private typealias FnAdapterCreate = @convention(c) () -> OpaquePointer?
    private typealias FnAdapterCreateSession = @convention(c) (UnsafePointer<CChar>?) -> OpaquePointer?
    private typealias FnAdapterDestroy = @convention(c) (OpaquePointer?) -> Void
    private typealias FnSnapshot = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        Int32,
        UInt8,
        Bool,
        Bool,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias FnExecuteByRefTimeout = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafeRawPointer?,
        Int32,
        Int64,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias FnStatus = @convention(c) (
        OpaquePointer?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias FnVersion = @convention(c) (
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias FnTraceShow = @convention(c) (
        OpaquePointer?,
        Int32,
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias FnTraceExport = @convention(c) (
        OpaquePointer?,
        Int32,
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias FnLastErrorMessage = @convention(c) () -> UnsafePointer<CChar>?
    private typealias FnLastErrorSuggestion = @convention(c) () -> UnsafePointer<CChar>?
    private typealias FnFreeString = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    private var dylibHandle: UnsafeMutableRawPointer?
    public private(set) var loadedDylibPath: String?
    public private(set) var isReady: Bool = false

    private var fnInit: FnInit?
    private var fnActionSize: FnActionSize?
    private var fnAdapterCreate: FnAdapterCreate?
    private var fnAdapterCreateSession: FnAdapterCreateSession?
    private var fnAdapterDestroy: FnAdapterDestroy?
    private var fnSnapshot: FnSnapshot?
    private var fnExecuteByRefTimeout: FnExecuteByRefTimeout?
    private var fnStatus: FnStatus?
    private var fnVersion: FnVersion?
    private var fnTraceShow: FnTraceShow?
    private var fnTraceExport: FnTraceExport?
    private var fnLastErrorMessage: FnLastErrorMessage?
    private var fnLastErrorSuggestion: FnLastErrorSuggestion?
    private var fnFreeString: FnFreeString?

    private let lock = NSLock()
    private var adaptersBySession: [String: OpaquePointer] = [:]

    private init() {
        loadIfAvailable()
    }

    deinit {
        lock.lock()
        let all = Array(adaptersBySession.values)
        adaptersBySession.removeAll()
        lock.unlock()
        for ptr in all {
            fnAdapterDestroy?(ptr)
        }
    }

    private static func candidateDylibPaths() -> [String] {
        var paths: [String] = []
        if let fw = Bundle.main.privateFrameworksPath {
            paths.append((fw as NSString).appendingPathComponent("libagent_desktop_ffi.dylib"))
        }
        if let res = Bundle.main.resourceURL?.path {
            paths.append((res as NSString).appendingPathComponent("agent-desktop/lib/libagent_desktop_ffi.dylib"))
        }
        let cwd = FileManager.default.currentDirectoryPath
        paths.append((cwd as NSString).appendingPathComponent("Vendor/agent-desktop/1.3.1/ffi/agent-desktop-ffi-v1.3.1-aarch64-apple-darwin/lib/libagent_desktop_ffi.dylib"))
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AgentCore
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // MicroCode
            .deletingLastPathComponent() // repo root
            .path
        paths.append((sourceRoot as NSString).appendingPathComponent("Vendor/agent-desktop/1.3.1/ffi/agent-desktop-ffi-v1.3.1-aarch64-apple-darwin/lib/libagent_desktop_ffi.dylib"))
        return paths
    }

    private func loadSym<T>(_ handle: UnsafeMutableRawPointer, _ symbol: String, as type: T.Type) -> T? {
        guard let sym = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(sym, to: type)
    }

    private func loadIfAvailable() {
        let fm = FileManager.default
        for candidate in Self.candidateDylibPaths() where fm.fileExists(atPath: candidate) {
            guard let handle = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) else { continue }
            guard
                let fInit = loadSym(handle, "ad_init", as: FnInit.self),
                let fCreate = loadSym(handle, "ad_adapter_create", as: FnAdapterCreate.self),
                let fCreateSess = loadSym(handle, "ad_adapter_create_with_session", as: FnAdapterCreateSession.self),
                let fDestroy = loadSym(handle, "ad_adapter_destroy", as: FnAdapterDestroy.self),
                let fSnap = loadSym(handle, "ad_snapshot", as: FnSnapshot.self),
                let fExec = loadSym(handle, "ad_execute_by_ref_timeout", as: FnExecuteByRefTimeout.self),
                let fStat = loadSym(handle, "ad_status", as: FnStatus.self),
                let fVer = loadSym(handle, "ad_version", as: FnVersion.self),
                let fTrShow = loadSym(handle, "ad_trace_show", as: FnTraceShow.self),
                let fTrExp = loadSym(handle, "ad_trace_export", as: FnTraceExport.self),
                let fErrMsg = loadSym(handle, "ad_last_error_message", as: FnLastErrorMessage.self),
                let fErrSug = loadSym(handle, "ad_last_error_suggestion", as: FnLastErrorSuggestion.self),
                let fFree = loadSym(handle, "ad_free_string", as: FnFreeString.self)
            else {
                dlclose(handle)
                continue
            }
            let fActSize = loadSym(handle, "ad_action_size", as: FnActionSize.self)
            if let fActSize, fActSize() != Self.expectedActionSize {
                dlclose(handle)
                continue
            }
            guard fInit(Self.expectedABIMajor) == 0 else {
                dlclose(handle)
                continue
            }

            self.dylibHandle = handle
            self.loadedDylibPath = candidate
            self.fnInit = fInit
            self.fnActionSize = fActSize
            self.fnAdapterCreate = fCreate
            self.fnAdapterCreateSession = fCreateSess
            self.fnAdapterDestroy = fDestroy
            self.fnSnapshot = fSnap
            self.fnExecuteByRefTimeout = fExec
            self.fnStatus = fStat
            self.fnVersion = fVer
            self.fnTraceShow = fTrShow
            self.fnTraceExport = fTrExp
            self.fnLastErrorMessage = fErrMsg
            self.fnLastErrorSuggestion = fErrSug
            self.fnFreeString = fFree
            self.isReady = true
            return
        }
    }

    private func adapter(for sessionId: String?) -> OpaquePointer? {
        guard isReady else { return nil }
        let normalized = Self.sanitizeSessionId(sessionId)
        lock.lock()
        defer { lock.unlock() }
        if let existing = adaptersBySession[normalized] {
            return existing
        }
        let created: OpaquePointer?
        if normalized == "default" {
            created = fnAdapterCreate?()
        } else {
            created = normalized.withCString { cStr in
                fnAdapterCreateSession?(cStr)
            }
        }
        if let created {
            adaptersBySession[normalized] = created
        }
        return created
    }

    public static func sanitizeSessionId(_ raw: String?) -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "default"
        }
        let allowed = raw.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
        let cleaned = String(String.UnicodeScalarView(allowed))
        return cleaned.isEmpty ? "default" : String(cleaned.prefix(48))
    }

    private func takeOwnedJSON(_ outPtr: UnsafeMutablePointer<CChar>?, resultCode: Int32) -> [String: Any] {
        if let outPtr {
            defer { fnFreeString?(outPtr) }
            let str = String(cString: outPtr)
            if let data = str.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
            return ["ok": resultCode == 0, "raw": str]
        }
        let errMsg = fnLastErrorMessage?().map { String(cString: $0) } ?? "FFI call failed with code \(resultCode)"
        let errSug = fnLastErrorSuggestion?().map { String(cString: $0) }
        var errDict: [String: Any] = ["code": resultCode, "message": errMsg]
        if let errSug, !errSug.isEmpty {
            errDict["suggestion"] = errSug
        }
        return ["ok": false, "error": errDict]
    }

    public func status(sessionId: String? = nil) -> [String: Any]? {
        guard isReady, let ad = adapter(for: sessionId), let fnStatus else { return nil }
        var outPtr: UnsafeMutablePointer<CChar>? = nil
        let rc = fnStatus(ad, &outPtr)
        return takeOwnedJSON(outPtr, resultCode: rc)
    }

    public func snapshot(
        app: String?,
        surface: Surface = .window,
        maxDepth: UInt8 = 14,
        interactiveOnly: Bool = true,
        compact: Bool = true,
        sessionId: String? = nil
    ) -> [String: Any]? {
        guard isReady, let ad = adapter(for: sessionId), let fnSnapshot else { return nil }
        var outPtr: UnsafeMutablePointer<CChar>? = nil
        let rc: Int32
        if let app, !app.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rc = app.withCString { cApp in
                fnSnapshot(ad, cApp, surface.rawValue, maxDepth, interactiveOnly, compact, &outPtr)
            }
        } else {
            rc = fnSnapshot(ad, nil, surface.rawValue, maxDepth, interactiveOnly, compact, &outPtr)
        }
        return takeOwnedJSON(outPtr, resultCode: rc)
    }

    public func executeByRef(
        refId: String,
        kind: ActionKind,
        text: String? = nil,
        scrollDirection: Int32 = 1,
        scrollAmount: UInt32 = 3,
        policy: PolicyKind = .headless,
        timeoutMs: Int64 = 5000,
        sessionId: String? = nil
    ) -> [String: Any]? {
        guard isReady, let ad = adapter(for: sessionId), let fnExecuteByRefTimeout else { return nil }
        var outPtr: UnsafeMutablePointer<CChar>? = nil

        let rc: Int32 = refId.withCString { cRef in
            let invokeWithTextPtr: (UnsafePointer<CChar>?) -> Int32 = { cText in
                let rawBuf = UnsafeMutableRawPointer.allocate(byteCount: Self.expectedActionSize, alignment: 8)
                rawBuf.initializeMemory(as: UInt8.self, repeating: 0, count: Self.expectedActionSize)
                defer { rawBuf.deallocate() }

                // Exact 96-byte layout verified against `agent_desktop.h` C11 `_Static_assert`:
                // [0..<4] kind: int32_t
                // [8..<16] text: const char *
                // [16..<20] scroll.direction: int32_t, [20..<24] scroll.amount: uint32_t
                rawBuf.storeBytes(of: kind.rawValue, toByteOffset: 0, as: Int32.self)
                if let cText {
                    rawBuf.storeBytes(of: cText, toByteOffset: 8, as: UnsafePointer<CChar>.self)
                }
                if kind == .scroll {
                    rawBuf.storeBytes(of: scrollDirection, toByteOffset: 16, as: Int32.self)
                    rawBuf.storeBytes(of: scrollAmount, toByteOffset: 20, as: UInt32.self)
                }
                return fnExecuteByRefTimeout(ad, cRef, rawBuf, policy.rawValue, timeoutMs, &outPtr)
            }

            if let text {
                return text.withCString { cText in
                    invokeWithTextPtr(cText)
                }
            } else {
                return invokeWithTextPtr(nil)
            }
        }
        return takeOwnedJSON(outPtr, resultCode: rc)
    }

    public func traceExport(outPath: String?, limit: Int32 = 5000, sessionId: String? = nil) -> [String: Any]? {
        guard isReady, let ad = adapter(for: sessionId), let fnTraceExport else { return nil }
        var outPtr: UnsafeMutablePointer<CChar>? = nil
        let rc: Int32
        if let outPath, !outPath.isEmpty {
            rc = outPath.withCString { cPath in
                fnTraceExport(ad, limit, cPath, &outPtr)
            }
        } else {
            rc = fnTraceExport(ad, limit, nil, &outPtr)
        }
        return takeOwnedJSON(outPtr, resultCode: rc)
    }
}

// MARK: - Unified Agent-Desktop Orchestrator (In-Process FFI + 57-Command CLI)

public final class AgentDesktopBridge: @unchecked Sendable {
    public static let shared = AgentDesktopBridge()

    private static let forbiddenShortcuts: Set<String> = [
        "cmd+q", "command+q", "meta+q",
        "cmd+shift+q", "ctrl+cmd+q", "cmd+alt+esc", "cmd+opt+esc", "cmd+shift+delete"
    ]

    private init() {}

    public func resolveBinaryPath() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let res = Bundle.main.resourceURL?.path {
            candidates.append((res as NSString).appendingPathComponent("agent-desktop/bin/agent-desktop"))
            candidates.append((res as NSString).appendingPathComponent("agent-desktop/agent-desktop"))
        }
        let cwd = fm.currentDirectoryPath
        candidates.append((cwd as NSString).appendingPathComponent("Vendor/agent-desktop/1.3.1/cli/agent-desktop"))
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        candidates.append((sourceRoot as NSString).appendingPathComponent("Vendor/agent-desktop/1.3.1/cli/agent-desktop"))
        candidates.append("/opt/homebrew/bin/agent-desktop")
        candidates.append("/usr/local/bin/agent-desktop")

        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    public static func isSnapshotQualifiedRef(_ candidate: String?) -> Bool {
        guard let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.hasPrefix("@"),
              let colonIdx = raw.firstIndex(of: ":") else {
            return false
        }
        let snapPart = raw[raw.index(after: raw.startIndex)..<colonIdx]
        let elemPart = raw[raw.index(after: colonIdx)...]
        return !snapPart.isEmpty && elemPart.hasPrefix("e") && elemPart.count >= 2
    }

    private func enforceAppAllowed(_ appNameOrBundle: String?) throws {
        guard let app = appNameOrBundle?.trimmingCharacters(in: .whitespacesAndNewlines), !app.isEmpty else {
            return
        }
        let blocked: Bool = MainActor.assumeIsolatedIfOnMain {
            NativeComputerUseService.isBlockedApplication(bundleId: app, appName: app)
        }
        if blocked {
            throw NSError(
                domain: "AgentDesktopSecurity",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Security Shield: Agent-Desktop is strictly blocked from accessing sensitive application '\(app)' (Keychain, Password Managers, SecurityAgent, System Settings)."]
            )
        }
    }

    /// Runs the bundled `agent-desktop` Rust binary off the MainActor with optional stdin payload (keeping secrets out of argv).
    public func runCLI(
        globalFlags: [String] = [],
        subcommand: String,
        args: [String] = [],
        stdinText: String? = nil,
        sessionId: String? = nil,
        headed: Bool = false,
        timeoutSec: TimeInterval = 15.0
    ) async -> [String: Any] {
        guard let binPath = resolveBinaryPath() else {
            return [
                "ok": false,
                "error": [
                    "code": "BINARY_NOT_FOUND",
                    "message": "Bundled agent-desktop binary not found."
                ]
            ]
        }

        var fullArgs: [String] = []
        let cleanSession = AgentDesktopFFILoader.sanitizeSessionId(sessionId)
        if cleanSession != "default" {
            fullArgs += ["--session", cleanSession]
        }
        if headed {
            fullArgs.append("--headed")
        }
        fullArgs += globalFlags
        fullArgs.append(subcommand)
        fullArgs += args

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: binPath)
                proc.arguments = fullArgs

                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe

                var inPipe: Pipe? = nil
                if stdinText != nil {
                    let p = Pipe()
                    proc.standardInput = p
                    inPipe = p
                }

                do {
                    try proc.run()
                } catch {
                    continuation.resume(returning: [
                        "ok": false,
                        "error": ["code": "EXEC_FAILED", "message": error.localizedDescription]
                    ])
                    return
                }

                if let stdinText, let handle = inPipe?.fileHandleForWriting {
                    if let data = stdinText.data(using: .utf8) {
                        try? handle.write(contentsOf: data)
                    }
                    try? handle.close()
                }

                let deadline = Date().addingTimeInterval(timeoutSec)
                while proc.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.015)
                }
                if proc.isRunning {
                    proc.terminate()
                }

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stdoutStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderrStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if let jsonData = stdoutStr.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    continuation.resume(returning: parsed)
                } else {
                    continuation.resume(returning: [
                        "ok": proc.terminationStatus == 0,
                        "exit_code": Int(proc.terminationStatus),
                        "stdout": stdoutStr,
                        "stderr": stderrStr
                    ])
                }
            }
        }
    }

    // MARK: - High-Level Unified Request Dispatcher (FFI Fast-Path + CLI Full Surface + OCR Fallback)

    public func execute(_ params: [String: Any], defaultSessionId: String? = nil) async -> [String: Any] {
        let command = ((params["command"] as? String) ?? (params["action"] as? String) ?? "snapshot")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let app = (params["app"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = (params["session"] as? String) ?? defaultSessionId
        let headed = (params["headed"] as? Bool) ?? false

        do {
            try enforceAppAllowed(app)
        } catch {
            return ["ok": false, "success": false, "error": ["code": "SECURITY_SHIELD_BLOCKED", "message": error.localizedDescription]]
        }

        switch command {
        case "status", "permissions":
            if command == "status", let ffiStatus = AgentDesktopFFILoader.shared.status(sessionId: session) {
                var enriched = ffiStatus
                enriched["engine"] = "libagent_desktop_ffi (in-process ABI v7)"
                enriched["dylib_path"] = AgentDesktopFFILoader.shared.loadedDylibPath ?? ""
                enriched["openthai_ocr_ready"] = OpenThaiOCREngine.shared.isModelBundled
                return enriched
            }
            return await runCLI(subcommand: command, sessionId: session, headed: headed)

        case "snapshot", "skeleton", "drill", "observe_tree":
            let skeleton = (command == "skeleton") || ((params["skeleton"] as? Bool) ?? false)
            let rootRef = (params["root"] as? String) ?? (params["root_ref"] as? String)
            let windowIdStr: String? = {
                if let wStr = params["window_id"] as? String, !wStr.isEmpty { return wStr }
                if let wInt = (params["window_id"] as? Int) ?? (params["window_id"] as? NSNumber)?.intValue {
                    return String(wInt)
                }
                return nil
            }()
            let surfaceStr = (params["surface"] as? String) ?? "window"
            let interactiveOnly = (params["interactive_only"] as? Bool) ?? true
            let compact = (params["compact"] as? Bool) ?? true
            let maxDepth = UInt8(clamping: (params["max_depth"] as? Int) ?? 14)
            let autoOCRFallback = (params["ocr_fallback"] as? Bool) ?? true

            var result: [String: Any]
            // Use sub-millisecond In-Process FFI when neither CLI-only `--skeleton`, `--root`, nor `--window-id` is requested
            if !skeleton && (rootRef == nil || rootRef?.isEmpty == true) && windowIdStr == nil,
               let ffiSnap = AgentDesktopFFILoader.shared.snapshot(
                   app: app,
                   surface: .from(name: surfaceStr),
                   maxDepth: maxDepth,
                   interactiveOnly: interactiveOnly,
                   compact: compact,
                   sessionId: session
               ) {
                result = ffiSnap
                result["transport"] = "ffi_in_process"
            } else {
                var cliArgs: [String] = []
                if let app, !app.isEmpty { cliArgs += ["--app", app] }
                if let windowIdStr { cliArgs += ["--window-id", windowIdStr] }
                if surfaceStr.lowercased() != "window" { cliArgs += ["--surface", surfaceStr] }
                if skeleton { cliArgs.append("--skeleton") }
                if let rootRef, !rootRef.isEmpty { cliArgs += ["--root", rootRef] }
                if interactiveOnly { cliArgs.append("-i") }
                if compact { cliArgs.append("--compact") }
                result = await runCLI(subcommand: "snapshot", args: cliArgs, sessionId: session, headed: headed)
                result["transport"] = "cli_native"
            }

            // Hybrid Canvas / Simulator / Thai UI Fallback:
            // If AX tree returned 0 interactive refs on a standard window, automatically augment with OpenThai 2.0 OCR + Set-of-Mark!
            if autoOCRFallback,
               surfaceStr.lowercased() == "window",
               let dataDict = result["data"] as? [String: Any],
               let refCount = (dataDict["ref_count"] as? Int) ?? (dataDict["ref_count"] as? NSNumber)?.intValue,
               refCount == 0 {
                let fallback = await NativeComputerUseService.shared.handleRequest([
                    "action": "inspect",
                    "app": app ?? "MicroCode"
                ])
                result["hybrid_openthai_ocr_fallback"] = [
                    "triggered": true,
                    "reason": "Accessibility tree reported 0 interactive refs (Canvas/Metal/WebGL/Simulator surface); augmented with OpenThai 2.0 OCR + Set-of-Mark.",
                    "spatial_map": fallback["spatial_map"] ?? "",
                    "element_count": fallback["element_count"] ?? 0,
                    "elements": fallback["elements"] ?? []
                ]
            }
            return result

        case "click", "double-click", "double_click", "right-click", "right_click", "triple-click", "triple_click",
             "type", "set-value", "set_value", "clear", "focus", "select", "toggle", "check", "uncheck",
             "expand", "collapse", "scroll", "scroll-to", "scroll_to", "hover":
            guard let ref = ((params["ref"] as? String) ?? (params["ref_id"] as? String) ?? (params["target"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines),
                  Self.isSnapshotQualifiedRef(ref) else {
                return [
                    "ok": false,
                    "error": [
                        "code": "INVALID_REF",
                        "message": "Provide a snapshot-qualified ref like '@s8f3k2p9:e8' from a prior snapshot."
                    ]
                ]
            }
            let textVal = (params["text"] as? String) ?? (params["value"] as? String)
            let policy: AgentDesktopFFILoader.PolicyKind = headed ? .headed : .headless
            let timeoutMs = Int64((params["timeout_ms"] as? Int) ?? 5000)

            // In-process FFI fast-path for all ref-addressed semantic actions
            if let kind = AgentDesktopFFILoader.ActionKind.from(name: command),
               let ffiRes = AgentDesktopFFILoader.shared.executeByRef(
                   refId: ref,
                   kind: kind,
                   text: textVal,
                   scrollDirection: Self.parseScrollDirection(params["direction"] as? String),
                   scrollAmount: UInt32(clamping: (params["amount"] as? Int) ?? 3),
                   policy: policy,
                   timeoutMs: timeoutMs,
                   sessionId: session
               ) {
                var enriched = ffiRes
                enriched["transport"] = "ffi_in_process"
                return enriched
            }

            // CLI fallback with `--stdin` secret protection for text-bearing actions
            let cliSub = command.replacingOccurrences(of: "_", with: "-")
            if (cliSub == "type" || cliSub == "set-value"), let textVal {
                return await runCLI(subcommand: cliSub, args: [ref, "--stdin"], stdinText: textVal, sessionId: session, headed: headed)
            }
            var cliArgs = [ref]
            if let textVal, cliSub == "select" { cliArgs.append(textVal) }
            return await runCLI(subcommand: cliSub, args: cliArgs, sessionId: session, headed: headed)

        case "find":
            var cliArgs: [String] = []
            if let app, !app.isEmpty { cliArgs += ["--app", app] }
            if let role = params["role"] as? String, !role.isEmpty { cliArgs += ["--role", role] }
            if let name = (params["name"] as? String) ?? (params["query"] as? String), !name.isEmpty {
                cliArgs += ["--name", name]
            }
            return await runCLI(subcommand: "find", args: cliArgs, sessionId: session, headed: headed)

        case "get", "is":
            guard let ref = (params["ref"] as? String) ?? (params["ref_id"] as? String), !ref.isEmpty else {
                return ["ok": false, "error": ["code": "MISSING_REF", "message": "Provide 'ref' (@snapshot:eN)."]]
            }
            let prop = (params["property"] as? String) ?? (params["state"] as? String) ?? (command == "is" ? "visible" : "value")
            return await runCLI(subcommand: command, args: ["--property", prop, ref], sessionId: session, headed: headed)

        case "press":
            let combo = ((params["combo"] as? String) ?? (params["key"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.forbiddenShortcuts.contains(combo.lowercased()) {
                return [
                    "ok": false,
                    "error": [
                        "code": "POLICY_DENIED",
                        "message": "Destructive quit/logout shortcut '\(combo)' is blocked by policy."
                    ]
                ]
            }
            var cliArgs = [combo]
            if let app, !app.isEmpty { cliArgs += ["--app", app] }
            return await runCLI(subcommand: "press", args: cliArgs, sessionId: session, headed: true)

        case "list-windows", "list_windows", "windows":
            var cliArgs: [String] = []
            if let app, !app.isEmpty { cliArgs += ["--app", app] }
            return await runCLI(subcommand: "list-windows", args: cliArgs, sessionId: session, headed: headed)

        case "list-apps", "list_apps", "apps":
            return await runCLI(subcommand: "list-apps", sessionId: session, headed: headed)

        case "list-surfaces", "list_surfaces", "surfaces":
            var cliArgs: [String] = []
            if let app, !app.isEmpty { cliArgs += ["--app", app] }
            return await runCLI(subcommand: "list-surfaces", args: cliArgs, sessionId: session, headed: headed)

        case "open-system-surface", "open_system_surface":
            let surface = (params["surface"] as? String) ?? "menubar"
            var cliArgs = [surface]
            if let app, !app.isEmpty { cliArgs += ["--app", app] }
            return await runCLI(subcommand: "open-system-surface", args: cliArgs, sessionId: session, headed: headed)

        case "launch":
            guard let targetApp = app, !targetApp.isEmpty else {
                return ["ok": false, "error": ["code": "MISSING_APP", "message": "Provide 'app' name or bundle identifier to launch."]]
            }
            return await runCLI(subcommand: "launch", args: [targetApp], sessionId: session, headed: headed)

        case "close-app", "close_app":
            guard let targetApp = app, !targetApp.isEmpty else {
                return ["ok": false, "error": ["code": "MISSING_APP", "message": "Provide 'app' name or bundle identifier to close."]]
            }
            return await runCLI(subcommand: "close-app", args: [targetApp], sessionId: session, headed: headed)

        case "cursor-overlay", "cursor_overlay":
            let mode = ((params["mode"] as? String) ?? (params["enable"] as? Bool == false ? "disable" : "enable")).lowercased()
            return await runCLI(subcommand: "cursor-overlay", args: [mode], sessionId: session, headed: headed)

        case "list-notifications", "list_notifications", "notifications":
            return await runCLI(subcommand: "list-notifications", sessionId: session, headed: headed)

        case "dismiss-notification", "dismiss_notification":
            var cliArgs: [String] = []
            if let expApp = (params["expected_app"] as? String) ?? app, !expApp.isEmpty {
                cliArgs += ["--expected-app", expApp]
            }
            if let expTitle = params["expected_title"] as? String, !expTitle.isEmpty {
                cliArgs += ["--expected-title", expTitle]
            }
            return await runCLI(subcommand: "dismiss-notification", args: cliArgs, sessionId: session, headed: headed)

        case "wait":
            var cliArgs: [String] = []
            if let app, !app.isEmpty { cliArgs += ["--app", app] }
            if let text = params["text"] as? String, !text.isEmpty { cliArgs += ["--text", text] }
            if let ref = params["ref"] as? String, !ref.isEmpty { cliArgs += ["--ref", ref] }
            if let ms = params["timeout_ms"] as? Int { cliArgs += ["--timeout-ms", String(ms)] }
            return await runCLI(subcommand: "wait", args: cliArgs, sessionId: session, headed: headed)

        case "trace-export", "trace_export":
            let outPath = (params["output_path"] as? String) ?? "/tmp/microcode_agent_desktop_trace.html"
            if let ffiTrace = AgentDesktopFFILoader.shared.traceExport(outPath: outPath, sessionId: session) {
                return ffiTrace
            }
            return await runCLI(subcommand: "trace", args: ["export", outPath], sessionId: session, headed: headed)

        default:
            let extraArgs = (params["args"] as? [String]) ?? []
            return await runCLI(subcommand: command.replacingOccurrences(of: "_", with: "-"), args: extraArgs, sessionId: session, headed: headed)
        }
    }

    private static func parseScrollDirection(_ raw: String?) -> Int32 {
        switch (raw ?? "down").lowercased() {
        case "up": return 0
        case "down": return 1
        case "left": return 2
        case "right": return 3
        default: return 1
        }
    }
}

private extension MainActor {
    static func assumeIsolatedIfOnMain<T>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(body)
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated(body)
            }
        }
    }
}

// MARK: - First-Class AgentTool (`agent_desktop`)

struct AgentDesktopTool: AgentTool {
    let name = "agent_desktop"
    let description = """
    Semantic OS Accessibility Computer-Use Engine (`vercel-labs/agent-desktop` v1.3.1 In-Process FFI + OpenThai 2.0 OCR Hybrid Fallback).
    Operates macOS desktop apps headlessly WITHOUT moving the user's mouse or requiring Vision screenshots!
    Workflow:
    1. Map dense apps: `{"command":"skeleton","app":"Notes"}` or small apps: `{"command":"snapshot","app":"Finder"}` -> returns compact JSON tree with snapshot-qualified `@<snapshot_id>:e<N>` refs.
    2. Drill a subtree if needed: `{"command":"drill","app":"Notes","root":"@s8f3k2p9:e3"}`.
    3. Act on an exact ref: `{"command":"click","ref":"@s8f3k2p9:e8"}` or `{"command":"type","ref":"@s8f3k2p9:e12","text":"สวัสดี"}` (returns `STALE_REF` if UI changed — re-snapshot and retry).
    4. Inspect system surfaces: `surface` = 'window' | 'menubar' | 'menu' | 'menu-bar-extras' | 'dock' | 'sheet' | 'popover' | 'alert' | 'notifications'.
    5. Enable non-intrusive click-through Ghost Cursor: `{"command":"cursor-overlay","mode":"enable"}`.
    """

    let parameters: [ToolParameter] = [
        ToolParameter(name: "command", type: "string", description: "Command: 'snapshot', 'skeleton', 'drill', 'find', 'click', 'double-click', 'right-click', 'type', 'set-value', 'clear', 'focus', 'select', 'toggle', 'check', 'uncheck', 'expand', 'collapse', 'scroll', 'scroll-to', 'press', 'get', 'is', 'list-windows', 'list-apps', 'list-surfaces', 'open-system-surface', 'launch', 'close-app', 'cursor-overlay', 'list-notifications', 'dismiss-notification', 'wait', 'status', 'trace-export'", required: true),
        ToolParameter(name: "app", type: "string", description: "Target application name or bundle ID (e.g. 'Finder', 'Notes', 'Safari', 'Simulator', 'MicroCode')", required: false),
        ToolParameter(name: "ref", type: "string", description: "Snapshot-qualified element ref `@<snapshot_id>:e<N>` (e.g. '@s8f3k2p9:e8') for ref actions", required: false),
        ToolParameter(name: "root", type: "string", description: "Parent `@<snapshot_id>:e<N>` ref to drill into for 'drill' / 'snapshot'", required: false),
        ToolParameter(name: "surface", type: "string", description: "Surface scope: 'window' (default), 'focused', 'menubar', 'menu', 'menu-bar-extras', 'dock', 'sheet', 'popover', 'alert'", required: false),
        ToolParameter(name: "text", type: "string", description: "Text payload for 'type', 'set-value', 'select', or 'wait'", required: false),
        ToolParameter(name: "role", type: "string", description: "Role filter for 'find' (e.g. 'button', 'textfield', 'menuitem')", required: false),
        ToolParameter(name: "name", type: "string", description: "Element name/label filter for 'find'", required: false),
        ToolParameter(name: "combo", type: "string", description: "Key chord for 'press' (e.g. 'cmd+s', 'cmd+f', 'return')", required: false),
        ToolParameter(name: "headed", type: "boolean", description: "Set true ONLY when physical pointer/focus is required (e.g. hover/drag/double-click); false (default) runs 100% headless via AX", required: false),
        ToolParameter(name: "session", type: "string", description: "Optional isolated session namespace for multi-agent execution", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        let res = await AgentDesktopBridge.shared.execute(params)
        let data = try JSONSerialization.data(withJSONObject: res, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
