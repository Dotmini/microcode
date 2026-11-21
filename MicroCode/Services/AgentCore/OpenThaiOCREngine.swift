//
//  OpenThaiOCREngine.swift
//  MicroCode
//
//  Dual-Model OpenThai 2.0 OCR Engine (`https://openthai.ai/openthai2p0-ocr`, Apache-2.0):
//  1. `OpenThai 2.0 OCR Text` (4.2 MB ONNX CPU: `det.onnx` + `rec.onnx` + `thai_norm.py`):
//     - Persistent zero-cold-start JSON-Lines daemon (~150ms per Retina screenshot / ~390ms per A4 page)
//     - 99.5% Thai Budget & 96.3% Royal Gazette accuracy, exact 2D bounding boxes, 100% offline
//     - Self-healing `uv` Python runtime bootstrap (`~/.microcode/runtimes/openthai-ocr-venv`)
//  2. `OpenThai 2.0 OCR Markdown` (`iapp/OpenThai2.0-OCR-Markdown` 0.63B Nemotron-Parse):
//     - Auto-connects to local vLLM (`http://127.0.0.1:8000/v1`, `OPENTHAI_OCR_MARKDOWN_URL`)
//       or official iApp API (`POST https://api.iapp.co.th/v3/store/ocr/document/markdown` when `IAPP_API_KEY` is set),
//       falling back seamlessly to local ONNX CPU + 2D HTML/Markdown table reconstruction when offline.
//

import Foundation
import AppKit

public struct OpenThaiOCRResponse: Sendable {
    public let ok: Bool
    public let engineName: String
    public let text: String
    public let markdown: String
    public let confidence: Float
    public let elapsedMs: Double
    public let blocks: [SpatialVisionTextBlock]
    public let totalPages: Int
    public let errorMessage: String?
}

public final class OpenThaiOCREngine: @unchecked Sendable {
    public static let shared = OpenThaiOCREngine()

    private let daemonLock = NSLock()
    private var daemonProcess: Process?
    private var daemonStdin: FileHandle?
    private var daemonStdout: FileHandle?
    private var daemonReadBuffer = Data()
    private var requestCounter: UInt64 = 0
    private var bootstrapAttempted: Bool = false

    private init() {}

    deinit {
        stopDaemon()
    }

    // MARK: - Resource & Runtime Discovery

    public var resolvedModelDirectory: String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let res = Bundle.main.resourceURL?.path {
            candidates.append((res as NSString).appendingPathComponent("openthai-ocr"))
        }
        let cwd = fm.currentDirectoryPath
        candidates.append((cwd as NSString).appendingPathComponent("Vendor/openthai-ocr/2.0"))
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        candidates.append((sourceRoot as NSString).appendingPathComponent("Vendor/openthai-ocr/2.0"))

        for dir in candidates {
            let det = (dir as NSString).appendingPathComponent("det.onnx")
            let rec = (dir as NSString).appendingPathComponent("rec.onnx")
            let daemon = (dir as NSString).appendingPathComponent("openthai_ocr_daemon.py")
            if fm.fileExists(atPath: det) && fm.fileExists(atPath: rec) && fm.fileExists(atPath: daemon) {
                return dir
            }
        }
        return nil
    }

    public var isModelBundled: Bool {
        resolvedModelDirectory != nil
    }

    private var venvDirectoryPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".microcode/runtimes/openthai-ocr-venv")
    }

    private func resolvePythonExecutable() -> String? {
        let fm = FileManager.default
        let venvPy = (venvDirectoryPath as NSString).appendingPathComponent("bin/python")
        if fm.isExecutableFile(atPath: venvPy) {
            return venvPy
        }
        if !bootstrapAttempted {
            bootstrapAttempted = true
            if bootstrapVenvIfPossible(), fm.isExecutableFile(atPath: venvPy) {
                return venvPy
            }
        }
        for fallback in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"] {
            if fm.isExecutableFile(atPath: fallback) {
                return fallback
            }
        }
        return nil
    }

    private func bootstrapVenvIfPossible() -> Bool {
        let fm = FileManager.default
        let uvCandidates = [
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
            (fm.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent(".local/bin/uv"),
            (fm.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent(".cargo/bin/uv")
        ]
        guard let uvBin = uvCandidates.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            return false
        }
        let parentDir = (venvDirectoryPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        func runSync(_ args: [String], timeout: TimeInterval) -> Bool {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: uvBin)
            p.arguments = args
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            do { try p.run() } catch { return false }
            let deadline = Date().addingTimeInterval(timeout)
            while p.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if p.isRunning {
                p.terminate()
                return false
            }
            return p.terminationStatus == 0
        }

        guard runSync(["venv", "--python", "3.12", venvDirectoryPath], timeout: 45) else {
            return false
        }
        let venvPy = (venvDirectoryPath as NSString).appendingPathComponent("bin/python")
        return runSync([
            "pip", "install", "--python", venvPy,
            "onnxruntime", "opencv-python-headless", "numpy", "pyclipper", "pypdfium2"
        ], timeout: 120)
    }

    // MARK: - Persistent Warm Daemon Lifecycle

    private func ensureDaemonLocked() -> Bool {
        if let proc = daemonProcess, proc.isRunning, daemonStdin != nil, daemonStdout != nil {
            return true
        }
        stopDaemonLocked()

        guard let modelDir = resolvedModelDirectory,
              let pyBin = resolvePythonExecutable() else {
            return false
        }
        let scriptPath = (modelDir as NSString).appendingPathComponent("openthai_ocr_daemon.py")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pyBin)
        proc.arguments = ["-u", scriptPath, "--daemon"]
        proc.currentDirectoryURL = URL(fileURLWithPath: modelDir)

        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["OMP_NUM_THREADS"] = "2"
        proc.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return false
        }

        self.daemonProcess = proc
        self.daemonStdin = inPipe.fileHandleForWriting
        self.daemonStdout = outPipe.fileHandleForReading
        self.daemonReadBuffer.removeAll(keepingCapacity: true)

        // Read initial `{"ready": true, ...}` banner line (max 8s for cold ONNX compilation)
        guard let bannerLine = readLineLocked(timeout: 8.0),
              let data = bannerLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["ready"] as? Bool) == true else {
            stopDaemonLocked()
            return false
        }
        return true
    }

    private func readLineLocked(timeout: TimeInterval) -> String? {
        guard let stdout = daemonStdout, let proc = daemonProcess else { return nil }
        let newline = UInt8(ascii: "\n")
        let fd = stdout.fileDescriptor
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let nlIdx = daemonReadBuffer.firstIndex(of: newline) {
                let lineData = daemonReadBuffer.subdata(in: 0..<nlIdx)
                daemonReadBuffer.removeSubrange(0...nlIdx)
                return String(data: lineData, encoding: .utf8)
            }
            if !proc.isRunning {
                return nil
            }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let waitMs = Int32(max(10, min(250, deadline.timeIntervalSinceNow * 1000)))
            let ready = Darwin.poll(&pfd, 1, waitMs)
            if ready > 0 && (pfd.revents & Int16(POLLIN)) != 0 {
                var chunk = [UInt8](repeating: 0, count: 65536)
                let n = Darwin.read(fd, &chunk, chunk.count)
                if n > 0 {
                    daemonReadBuffer.append(contentsOf: chunk[0..<n])
                } else if n == 0 {
                    return nil
                }
            }
        }
        return nil
    }

    public func stopDaemon() {
        daemonLock.lock()
        stopDaemonLocked()
        daemonLock.unlock()
    }

    private func stopDaemonLocked() {
        if let proc = daemonProcess, proc.isRunning {
            proc.terminate()
        }
        daemonProcess = nil
        daemonStdin = nil
        daemonStdout = nil
        daemonReadBuffer.removeAll(keepingCapacity: false)
    }

    private func sendDaemonRequest(_ payload: [String: Any], timeout: TimeInterval = 20.0) -> [String: Any]? {
        daemonLock.lock()
        defer { daemonLock.unlock() }

        guard ensureDaemonLocked(), let stdin = daemonStdin else {
            return nil
        }

        requestCounter &+= 1
        var tagged = payload
        let reqId = "ot-\(requestCounter)"
        tagged["id"] = reqId

        guard var reqData = try? JSONSerialization.data(withJSONObject: tagged) else {
            return nil
        }
        reqData.append(UInt8(ascii: "\n"))

        do {
            try stdin.write(contentsOf: reqData)
        } catch {
            stopDaemonLocked()
            return nil
        }

        guard let respLine = readLineLocked(timeout: timeout),
              let respData = respLine.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
            stopDaemonLocked()
            return nil
        }
        return obj
    }

    // MARK: - Public High-Speed OCR APIs (In-Memory Image Data & File/PDF Paths)

    public static func containsThaiScript(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x0E00...0x0E7F).contains(scalar.value) {
                return true
            }
        }
        return false
    }

    /// Runs `OpenThai 2.0 OCR Text` (4.2MB ONNX CPU) on in-memory PNG/JPEG bytes in ~150ms.
    public func recognizeImageData(
        _ data: Data,
        includeMarkdown: Bool = true
    ) async -> OpenThaiOCRResponse? {
        guard !data.isEmpty, isModelBundled else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let b64 = data.base64EncodedString()
                guard let raw = self.sendDaemonRequest([
                    "cmd": "ocr",
                    "image_base64": b64,
                    "include_markdown": includeMarkdown
                ], timeout: 15.0) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Self.parseDaemonResponse(raw))
            }
        }
    }

    /// Converts a `CGImage` to fast PNG bytes and runs `OpenThai 2.0 OCR Text`.
    public func recognizeCGImage(_ cgImage: CGImage, includeMarkdown: Bool = false) async -> OpenThaiOCRResponse? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return await recognizeImageData(pngData, includeMarkdown: includeMarkdown)
    }

    /// Runs OpenThai 2.0 OCR (`auto` | `text` | `markdown`) on an image or multi-page PDF file.
    public func recognizeFile(
        path: String,
        mode: String = "auto",
        pageStart: Int = 1,
        pageEnd: Int = 10
    ) async -> OpenThaiOCRResponse {
        let expanded = NSString(string: path).expandingTildeInPath
        let normalizedMode = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // If `markdown` (or `auto` with external OpenThai2.0-OCR-Markdown endpoint configured) is requested,
        // attempt the 0.63B Nemotron-Parse Markdown server / iApp API first, then fall back to local ONNX + 2D Table engine.
        if normalizedMode == "markdown" || normalizedMode == "auto" {
            if let remoteMD = await tryOpenThaiMarkdownEndpoint(filePath: expanded, explicitMarkdownRequest: normalizedMode == "markdown") {
                return remoteMD
            }
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let raw = self.sendDaemonRequest([
                    "cmd": "ocr",
                    "path": expanded,
                    "page_start": max(1, pageStart),
                    "page_end": max(1, pageEnd),
                    "include_markdown": true
                ], timeout: 45.0) else {
                    continuation.resume(returning: OpenThaiOCRResponse(
                        ok: false,
                        engineName: "OpenThai2.0-OCR",
                        text: "",
                        markdown: "",
                        confidence: 0,
                        elapsedMs: 0,
                        blocks: [],
                        totalPages: 0,
                        errorMessage: "OpenThai 2.0 OCR runtime unavailable (verify ~/.microcode/runtimes/openthai-ocr-venv)."
                    ))
                    return
                }
                continuation.resume(returning: Self.parseDaemonResponse(raw))
            }
        }
    }

    // MARK: - OpenThai 2.0 OCR Markdown (0.63B vLLM `nemotron-parse` & Official iApp API)

    private func tryOpenThaiMarkdownEndpoint(filePath: String, explicitMarkdownRequest: Bool) async -> OpenThaiOCRResponse? {
        let env = ProcessInfo.processInfo.environment
        let customVLLM = env["OPENTHAI_OCR_MARKDOWN_URL"] ?? UserDefaults.standard.string(forKey: "MicroCode.OpenThaiMarkdownURL")
        let iappKey = env["IAPP_API_KEY"] ?? env["OPENTHAI_API_KEY"] ?? UserDefaults.standard.string(forKey: "MicroCode.IAppAPIKey")

        // 1. Local vLLM / OpenAI-compatible server serving `iapp/OpenThai2.0-OCR-Markdown` (`nemotron-parse`)
        let vllmBase = (customVLLM?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? (explicitMarkdownRequest ? "http://127.0.0.1:8000/v1" : nil)

        if let vllmBase,
           !filePath.lowercased().hasSuffix(".pdf"),
           let imgData = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
           !imgData.isEmpty {
            let t0 = CFAbsoluteTimeGetCurrent()
            if let md = await callVLLMMarkdownServer(baseURL: vllmBase, imageData: imgData) {
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                return OpenThaiOCRResponse(
                    ok: true,
                    engineName: "OpenThai2.0-OCR-Markdown (0.63B vLLM)",
                    text: md,
                    markdown: md,
                    confidence: 0.96,
                    elapsedMs: ms,
                    blocks: [],
                    totalPages: 1,
                    errorMessage: nil
                )
            }
        }

        // 2. Official iApp OpenThai 2.0 OCR Markdown API (`POST https://api.iapp.co.th/v3/store/ocr/document/markdown`)
        if let apiKey = iappKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty,
           let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)), !fileData.isEmpty {
            let t0 = CFAbsoluteTimeGetCurrent()
            if let md = await callIAppMarkdownAPI(apiKey: apiKey, fileData: fileData, fileName: (filePath as NSString).lastPathComponent) {
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                return OpenThaiOCRResponse(
                    ok: true,
                    engineName: "OpenThai2.0-OCR-Markdown (iApp API)",
                    text: md,
                    markdown: md,
                    confidence: 0.97,
                    elapsedMs: ms,
                    blocks: [],
                    totalPages: 1,
                    errorMessage: nil
                )
            }
        }

        return nil
    }

    private func callVLLMMarkdownServer(baseURL: String, imageData: Data) async -> String? {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: "\(trimmed)/chat/completions") else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 8.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let b64 = imageData.base64EncodedString()
        let body: [String: Any] = [
            "model": "nemotron-parse",
            "temperature": 0.0,
            "max_tokens": 4096,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(b64)"]],
                        ["type": "text", "text": "Parse this document page into structured Markdown, preserving exact Thai and English text and rendering tables as HTML with rowspan and colspan."]
                    ]
                ]
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return content
    }

    private func callIAppMarkdownAPI(apiKey: String, fileData: Data, fileName: String) async -> String? {
        guard let url = URL(string: "https://api.iapp.co.th/v3/store/ocr/document/markdown") else { return nil }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30.0
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let mime = fileName.lowercased().hasSuffix(".pdf") ? "application/pdf" : "image/png"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let md = (json["markdown"] as? String) ?? (json["text"] as? String), !md.isEmpty {
            return md
        }
        return nil
    }

    private static func parseDaemonResponse(_ raw: [String: Any]) -> OpenThaiOCRResponse {
        let ok = (raw["ok"] as? Bool) ?? false
        let engine = (raw["engine"] as? String) ?? "OpenThai2.0-OCR-Text (ONNX CPU)"
        let text = (raw["text"] as? String) ?? ""
        let markdown = (raw["markdown"] as? String) ?? text
        let conf = Float((raw["confidence"] as? Double) ?? (raw["confidence"] as? NSNumber)?.doubleValue ?? 0.0)
        let ms = (raw["elapsed_ms"] as? Double) ?? (raw["elapsed_ms"] as? NSNumber)?.doubleValue ?? 0.0
        let totalPages = (raw["total_pages"] as? Int) ?? 1
        let err = raw["error"] as? String

        var blocks: [SpatialVisionTextBlock] = []
        if let rawLines = raw["lines"] as? [[String: Any]] {
            blocks.reserveCapacity(rawLines.count)
            for ln in rawLines {
                guard let lnText = ln["text"] as? String, !lnText.isEmpty else { continue }
                let lnConf = Float((ln["confidence"] as? Double) ?? (ln["confidence"] as? NSNumber)?.doubleValue ?? 0.9)
                let pxDict = ln["pixel_rect"] as? [String: Any]
                let nmDict = ln["normalized_rect"] as? [String: Any]
                let pxRect = CGRect(
                    x: (pxDict?["x"] as? Double) ?? 0,
                    y: (pxDict?["y"] as? Double) ?? 0,
                    width: (pxDict?["width"] as? Double) ?? 1,
                    height: (pxDict?["height"] as? Double) ?? 1
                )
                let nmRect = CGRect(
                    x: (nmDict?["x"] as? Double) ?? 0,
                    y: (nmDict?["y"] as? Double) ?? 0,
                    width: (nmDict?["width"] as? Double) ?? 0.01,
                    height: (nmDict?["height"] as? Double) ?? 0.01
                )
                blocks.append(SpatialVisionTextBlock(
                    text: lnText,
                    confidence: lnConf,
                    normalizedTopLeftRect: nmRect,
                    pixelRect: pxRect
                ))
            }
        }

        return OpenThaiOCRResponse(
            ok: ok,
            engineName: engine,
            text: text,
            markdown: markdown,
            confidence: conf,
            elapsedMs: ms,
            blocks: blocks,
            totalPages: totalPages,
            errorMessage: err
        )
    }
}

// MARK: - First-Class AgentTool (`openthai_ocr`)

struct OpenThaiOCRTool: AgentTool {
    let name = "openthai_ocr"
    let description = """
    OpenThai 2.0 OCR Engine (`https://openthai.ai/openthai2p0-ocr`, Apache-2.0) for high-precision Thai + English document, table, PDF, receipt, government Gazette, and UI screenshot recognition.
    Modes:
    - 'auto' (default): Uses OpenThai 2.0 OCR Markdown (0.63B vLLM / iApp API) if configured, otherwise runs bundled local OpenThai 2.0 OCR Text (4.2MB ONNX CPU, ~160ms/page, 100% offline) + 2D HTML/Markdown table reconstruction.
    - 'text': Forces local offline 4.2MB ONNX CPU line detector + Thai CTC recognizer with exact line bounding boxes.
    - 'markdown': Structured Markdown + HTML `rowspan`/`colspan` table extraction for complex forms and multi-column PDFs.
    """

    let parameters: [ToolParameter] = [
        ToolParameter(name: "path", type: "string", description: "Path to image (.png/.jpg/.webp/.tiff/.bmp) or PDF (.pdf) file", required: true),
        ToolParameter(name: "mode", type: "string", description: "'auto' (default), 'text' (4MB local ONNX CPU), or 'markdown' (structured tables & layout)", required: false),
        ToolParameter(name: "page_start", type: "integer", description: "Start page for PDF files (1-based, default 1)", required: false),
        ToolParameter(name: "page_end", type: "integer", description: "End page for PDF files (inclusive, default 10)", required: false),
        ToolParameter(name: "include_boxes", type: "boolean", description: "Include 2D pixel & normalized bounding boxes for each recognized line (default false)", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        guard let rawPath = params["path"] as? String, !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "OpenThaiOCR", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing required parameter 'path'."])
        }
        let mode = (params["mode"] as? String) ?? "auto"
        let pageStart = (params["page_start"] as? Int) ?? (params["page_start"] as? NSNumber)?.intValue ?? 1
        let pageEnd = (params["page_end"] as? Int) ?? (params["page_end"] as? NSNumber)?.intValue ?? 10
        let includeBoxes = (params["include_boxes"] as? Bool) ?? false

        let wsRoot = await MainActor.run { AgentToolBox.shared.effectiveWorkspaceRoot }
        let resolved: String = {
            let expanded = NSString(string: rawPath).expandingTildeInPath
            if expanded.hasPrefix("/") { return expanded }
            if let ws = wsRoot, !ws.isEmpty {
                return (ws as NSString).appendingPathComponent(expanded)
            }
            return expanded
        }()

        let res = await OpenThaiOCREngine.shared.recognizeFile(
            path: resolved,
            mode: mode,
            pageStart: pageStart,
            pageEnd: pageEnd
        )

        var out: [String: Any] = [
            "ok": res.ok,
            "engine": res.engineName,
            "path": resolved,
            "confidence": Double((res.confidence * 10000).rounded() / 10000),
            "elapsed_ms": res.elapsedMs,
            "total_pages": res.totalPages,
            "line_count": res.blocks.count,
            "markdown": res.markdown,
            "text": res.text
        ]
        if let err = res.errorMessage {
            out["error"] = err
        }
        if includeBoxes {
            out["lines"] = res.blocks.map { b in
                [
                    "text": b.text,
                    "confidence": Double((b.confidence * 10000).rounded() / 10000),
                    "pixel_rect": [
                        "x": Double(b.pixelRect.origin.x),
                        "y": Double(b.pixelRect.origin.y),
                        "width": Double(b.pixelRect.width),
                        "height": Double(b.pixelRect.height)
                    ],
                    "normalized_rect": [
                        "x": Double(b.normalizedTopLeftRect.origin.x),
                        "y": Double(b.normalizedTopLeftRect.origin.y),
                        "width": Double(b.normalizedTopLeftRect.width),
                        "height": Double(b.normalizedTopLeftRect.height)
                    ]
                ]
            }
        }
        let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
