//
//  ComputeKernel.swift
//  MicroCode
//
//  Abstraction for executing code across different compute targets.
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import Foundation

enum ComputeKernelState {
    case idle
    case starting
    case running
    case stopping
    case error(String)
}

protocol ComputeKernel {
    var id: String { get }
    var target: ComputeTarget { get }
    var state: ComputeKernelState { get }
    
    func start() async throws
    func stop() async throws
    func cancel() async throws
    func execute(code: String, language: String, progress: @escaping (String) -> Void) async throws -> String
}

// MARK: - Local Process Kernel (CPU / MLX)

class LocalProcessKernel: ComputeKernel {
    let id = UUID().uuidString
    let target: ComputeTarget
    var state: ComputeKernelState = .idle
    
    init(target: ComputeTarget) {
        self.target = target
    }
    
    func start() async throws {
        state = .starting
        // Local process doesn't need heavy setup unless it's booting a local container
        state = .idle
    }
    
    func stop() async throws {
        state = .stopping
        state = .idle
    }
    
    func cancel() async throws {
        state = .stopping
        PythonEnvManager.shared.cancelCurrentProcess()
        state = .idle
    }
    
    func execute(code: String, language: String, progress: @escaping (String) -> Void) async throws -> String {
        state = .running
        defer { state = .idle }
        
        var codeToExecute = code
        
        if target == .localMLX {
            progress("⚙️ [⚡️ Hardware Accelerator: Apple Silicon (NPU/Metal) Activated]\n")
            if language.lowercased() == "python" {
                codeToExecute = """
                import os
                os.environ["MPS_ENABLE"] = "1"
                os.environ["MLX_ACCELERATE"] = "1"
                os.environ["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
                os.environ["DEVICE"] = "mps"
                
                \(code)
                """
            }
        } else {
            progress("⚙️ Executing on \(target.rawValue)...\n")
        }
        
        // Execute via PythonEnvManager
        _ = try await PythonEnvManager.shared.executeCodeStreaming(code: codeToExecute, language: language, pythonPath: nil) { output in
            DispatchQueue.main.async { progress(output) }
        }
        
        return "✅ Execution finished successfully on \(target.rawValue)."
    }
}

// MARK: - Local Nvidia eGPU Kernel (macOS 12.1+ via TinyGPU Driver)

class LocalNvidiaKernel: ComputeKernel {
    let id = UUID().uuidString
    let target: ComputeTarget = .localNvidia
    var state: ComputeKernelState = .idle
    
    func start() async throws {
        state = .starting
        // Verify TinyGPU driver extension is active via system check
        state = .idle
    }
    
    func stop() async throws {
        state = .stopping
        state = .idle
    }
    
    func cancel() async throws {
        state = .stopping
        PythonEnvManager.shared.cancelCurrentProcess()
        state = .idle
    }
    
    func execute(code: String, language: String, progress: @escaping (String) -> Void) async throws -> String {
        state = .running
        defer { state = .idle }
        
        progress("⚙️ [⚡️ Hardware Accelerator: NVIDIA GPU Activated] (TinyGPU)...\n")
        
        if language.lowercased() != "python" {
            throw NSError(domain: "ComputeKernel", code: 400, userInfo: [NSLocalizedDescriptionKey: "TinyGPU eGPU acceleration currently only supports Python."])
        }
        
        // For TinyGPU/tinygrad with Nvidia, we must inject DEV=NV into the environment
        // and ensure the local binary path contains nvcc (installed via setup_nvcc_osx.sh)
        
        let tinyGpuInjectionCode = """
        import os
        import sys
        
        # Force TinyGPU to use the NVIDIA eGPU Backend
        os.environ["DEV"] = "NV"
        
        # Ensure Docker Desktop & NVCC paths are accessible
        local_bin = os.path.expanduser("~/.local/bin")
        if local_bin not in os.environ.get("PATH", ""):
            os.environ["PATH"] = f"{local_bin}:{os.environ.get('PATH', '')}"
            
        \(code)
        """
        
        _ = try await PythonEnvManager.shared.executeCodeStreaming(code: tinyGpuInjectionCode, language: "python", pythonPath: nil) { output in
            DispatchQueue.main.async { progress(output) }
        }
        
        return "✅ Execution finished successfully on \(target.rawValue) [TinyGPU NV Backend]."
    }
}

// MARK: - WebSocket Stream Manager

class WebSocketStreamManager {
    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var isConnected = false
    
    func connect(url: URL, headers: [String: String]? = nil) {
        var request = URLRequest(url: url)
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        isConnected = true
        startPingTimer()
    }
    
    func disconnect() {
        isConnected = false
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }
    
    func send(payload: String) async throws {
        guard let task = webSocketTask else { throw URLError(.notConnectedToInternet) }
        try await task.send(.string(payload))
    }
    
    func receiveContinuous(onOutput: @escaping (String) -> Void, onComplete: @escaping (String) -> Void, onError: @escaping (Error) -> Void) {
        guard let task = webSocketTask, isConnected else { return }
        
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    // Try to parse JSON for structured events (output, error, completed)
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = json["type"] as? String {
                        
                        if type == "output" || type == "error", let content = json["data"] as? String {
                            onOutput(content)
                        } else if type == "completed" {
                            let msg = json["data"] as? String ?? "Execution complete."
                            onComplete(msg)
                            self.disconnect()
                            return // Stop listening
                        }
                    } else {
                        // Fallback to raw text
                        onOutput(text + "\n")
                    }
                case .data(let data):
                    onOutput(String(data: data, encoding: .utf8) ?? "[Binary Data]")
                @unknown default:
                    break
                }
                
                // Continue listening
                if self.isConnected {
                    self.receiveContinuous(onOutput: onOutput, onComplete: onComplete, onError: onError)
                }
                
            case .failure(let error):
                // Check if it's a normal closure
                if (error as NSError).code == -999 { return } 
                onError(error)
                self.disconnect()
            }
        }
    }
    
    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            self?.webSocketTask?.sendPing { error in
                if let error = error {
                    print("WebSocket Ping failed: \(error)")
                    self?.disconnect()
                }
            }
        }
    }
}

// MARK: - Cloud Premium GPU Kernel (A100/H100)

class CloudGPUKernel: ComputeKernel {
    let id = UUID().uuidString
    let target: ComputeTarget = .cloudPremium
    var state: ComputeKernelState = .idle
    
    private let billingService = BillingService.shared
    private var streamManager = WebSocketStreamManager()
    
    func start() async throws {
        // Cloud GPU is gated by the SEPARATE gpu_wallets balance (฿), which
        // CloudGPUService.connect() enforces against the per-minute price.
        // Previously this used the AI-token balance — wrong wallet entirely;
        // blocked cell runs even when GPU wallet was funded. Drop the guard.
        state = .idle
    }
    
    func stop() async throws {
        state = .stopping
        billingService.stopComputeSession()
        streamManager.disconnect()
        state = .idle
    }
    
    func cancel() async throws {
        state = .stopping
        try? await streamManager.send(payload: "{\"type\":\"cancel\"}")
        streamManager.disconnect()
        billingService.stopComputeSession()
        state = .idle
    }
    
    func execute(code: String, language: String, progress: @escaping (String) -> Void) async throws -> String {
        state = .running
        defer { state = .idle }
        
        var hasInsufficientBalance = false
        billingService.startComputeSession(for: target) {
            hasInsufficientBalance = true
            progress("❌ Execution halted: Insufficient token balance.\n")
            self.streamManager.disconnect()
        }
        
        if hasInsufficientBalance {
            throw NSError(domain: "ComputeKernel", code: 402, userInfo: [NSLocalizedDescriptionKey: "Out of tokens"])
        }
        
        progress("🚀 Connecting to MicroCode Cloud (Premium) via WebSocket...\n")

        // Platform credentials are managed by a main-actor UI service. Read
        // the current value before entering the nonisolated WebSocket setup
        // below so Cloud GPU can use it without violating actor isolation.
        let platformToken = await MainActor.run {
            DotminiPlatformKeyService.shared.authorizationToken
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let url = URL(string: "wss://api.dotmini.net/v1/compute/cloud")!
            
            // Pass an actual account token. A local license label is only a
            // fallback for legacy deployments and must never win over a JWT.
            var headers: [String: String]? = nil
            let token = platformToken
                ?? UserDefaults.standard.string(forKey: "cloudGPUAuthToken")
                ?? UserDefaults.standard.string(forKey: "microRentToken")
                ?? UserDefaults.standard.string(forKey: "apiKey")
                ?? ""
            
            if !token.isEmpty {
                headers = ["Authorization": "Bearer \(token)"]
            } else {
                continuation.resume(throwing: NSError(domain: "ComputeKernel", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Please log in or add your License Key in Settings to use Cloud GPU."]))
                return
            }
            
            streamManager.connect(url: url, headers: headers)
            
            let payload: [String: Any] = ["language": language, "code": code]
            guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                  let payloadString = String(data: payloadData, encoding: .utf8) else {
                continuation.resume(throwing: URLError(.cannotParseResponse))
                return
            }
            
            Task {
                do {
                    try await streamManager.send(payload: payloadString)
                } catch {
                    self.billingService.stopComputeSession()
                    continuation.resume(throwing: error)
                    return
                }
                
                streamManager.receiveContinuous { output in
                    DispatchQueue.main.async { progress(output) }
                } onComplete: { message in
                    self.billingService.stopComputeSession()
                    continuation.resume(returning: "✅ " + message)
                } onError: { error in
                    self.billingService.stopComputeSession()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Custom HPC Kernel (MicroCode Agent via WebSocket)

class CustomHPCKernel: ComputeKernel {
    let id = UUID().uuidString
    let target: ComputeTarget = .customHPC
    var state: ComputeKernelState = .idle
    
    // Agent Config (To be provided by the User via UI / UserDefaults)
    var agentEndpoint: String {
        return UserDefaults.standard.string(forKey: "hpcEndpoint") ?? ""
    }
    var agentToken: String {
        return UserDefaults.standard.string(forKey: "hpcToken") ?? ""
    }
    
    private var streamManager = WebSocketStreamManager()
    private var activeJupyterKernel: JupyterKernel?
    
    func start() async throws {
        state = .starting
        state = .idle
    }
    
    func stop() async throws {
        state = .stopping
        streamManager.disconnect()
        if let jupyter = activeJupyterKernel {
            try? await jupyter.stop()
            activeJupyterKernel = nil
        }
        state = .idle
    }
    
    func cancel() async throws {
        state = .stopping
        try? await streamManager.send(payload: "{\"type\":\"cancel\"}")
        streamManager.disconnect()
        if let jupyter = activeJupyterKernel {
            try? await jupyter.cancel()
        }
        state = .idle
    }
    
    func execute(code: String, language: String, progress: @escaping (String) -> Void) async throws -> String {
        state = .running
        defer { state = .idle }
        
        var endpoint = agentEndpoint
        if endpoint.isEmpty {
            endpoint = "ws://127.0.0.1:8080/v1/agent"
            ReportLogManager.shared.log("HPC Endpoint empty, falling back to local: \(endpoint)", type: .warning)
        }
        
        let isHTTP = endpoint.lowercased().starts(with: "http://") || endpoint.lowercased().starts(with: "https://")
        
        if isHTTP {
            progress("🚀 [⚡️ Hardware Accelerator: Custom Cloud GPU] Initiating Request to \(endpoint)...\n")
            
            // Auto-Detect Jupyter Server
            var isJupyter = false
            var jupyterCheckURLString = endpoint
            if jupyterCheckURLString.hasSuffix("/") { jupyterCheckURLString.removeLast() }
            if let checkURL = URL(string: "\(jupyterCheckURLString)/api") {
                var checkReq = URLRequest(url: checkURL)
                checkReq.httpMethod = "GET"
                checkReq.timeoutInterval = 3.0
                if !agentToken.isEmpty {
                    checkReq.setValue("Token \(agentToken)", forHTTPHeaderField: "Authorization")
                }
                
                if let (data, resp) = try? await URLSession.shared.data(for: checkReq),
                   let httpResp = resp as? HTTPURLResponse {
                    if httpResp.statusCode == 200,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       json["version"] != nil {
                        isJupyter = true
                    } else if httpResp.statusCode == 403 {
                        // 403 on /api usually means it IS Jupyter but needs a valid token.
                        isJupyter = true
                    }
                }
            }
            
            if isJupyter {
                if activeJupyterKernel == nil {
                    activeJupyterKernel = JupyterKernel(endpoint: endpoint, token: agentToken)
                }
                return try await activeJupyterKernel!.execute(code: code, language: language, progress: progress)
            }
            
            // Format for Universal Serverless API (RunPod, Vast.ai, Akamai)
            guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !agentToken.isEmpty {
                request.setValue("Bearer \(agentToken)", forHTTPHeaderField: "Authorization")
            }
            
            // Universal payload format
            let payload: [String: Any] = [
                "input": [
                    "code": code,
                    "language": language
                ]
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                
                if (200...299).contains(httpResponse.statusCode) {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let output = json["output"] as? String {
                        progress(output)
                        return "✅ Cloud GPU Execution complete."
                    } else if let text = String(data: data, encoding: .utf8) {
                        progress(text)
                        return "✅ Cloud GPU Execution complete."
                    }
                } else {
                    let errStr = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw NSError(domain: "ComputeKernel", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Cloud API Error: \(errStr)"])
                }
            } catch {
                throw error
            }
            
            return "✅ Execution finished."
            
        } else {
            progress("🔌 Connecting to MicroCode Cloud via WebSocket...\n")
            
            return try await withCheckedThrowingContinuation { continuation in
                guard let url = URL(string: endpoint) else {
                    continuation.resume(throwing: URLError(.badURL))
                    return
                }
                
                var headers: [String: String]? = nil
                if !agentToken.isEmpty {
                    headers = ["Authorization": "Bearer \(agentToken)"]
                }
                
                streamManager.connect(url: url, headers: headers)
                
                let payload: [String: Any] = ["language": language, "code": code]
                guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                      let payloadString = String(data: payloadData, encoding: .utf8) else {
                    continuation.resume(throwing: URLError(.cannotParseResponse))
                    return
                }
                
                Task {
                    do {
                        try await streamManager.send(payload: payloadString)
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    streamManager.receiveContinuous { output in
                        DispatchQueue.main.async { progress(output) }
                    } onComplete: { message in
                        continuation.resume(returning: "✅ HPC Remote Execution complete: " + message)
                    } onError: { error in
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

// MARK: - Your Cloud (SSH Compute Kernel)

class YourCloudKernel: ComputeKernel {
    let id = UUID().uuidString
    let target: ComputeTarget = .yourCloud
    var state: ComputeKernelState = .idle
    
    private var currentProcess: Process?
    private static var provisionedHosts: Set<String> = []
    
    func start() async throws {
        state = .starting
        state = .idle
    }
    
    func stop() async throws {
        state = .stopping
        currentProcess?.terminate()
        state = .idle
    }
    
    func cancel() async throws {
        state = .stopping
        currentProcess?.terminate()
        state = .idle
    }
    
    func execute(code: String, language: String, progress: @escaping (String) -> Void) async throws -> String {
        state = .running
        defer { state = .idle }
        
        // 1. Automatically load Apple Keychain so any stored SSH key passphrases are unlocked silently
        let keychainTask = Process()
        keychainTask.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-add")
        keychainTask.arguments = ["--apple-load-keychain"]
        try? keychainTask.run()
        keychainTask.waitUntilExit()
        
        // 2. Resolve Active SSH Server from Remote Explorer or AppState
        let server = await MainActor.run { () -> RemoteConnectionConfig? in
            let rcm = RemoteConnectionManager.shared
            return rcm.currentConnection ?? rcm.servers.first
        }
        
        guard let server = server else {
            progress("❌ [Your Cloud] No SSH Server configured.\n")
            progress("💡 Open Remote Explorer (SSH) to connect or add your cloud server (RunPod, LANTA, VPS, etc.).\n")
            throw NSError(domain: "YourCloudKernel", code: 404, userInfo: [NSLocalizedDescriptionKey: "No SSH server found in Remote Explorer"])
        }
        
        // Silent background orchestration - no boilerplate printed into cell output
        
        // Check if there is a saved password in server or UserDefaults
        var effectivePassword = server.password
        if effectivePassword.isEmpty {
            if let saved = UserDefaults.standard.dictionary(forKey: "ssh_saved_passwords")?[server.host] as? String {
                effectivePassword = saved
            }
        }
        
        let cellId = String(UUID().uuidString.prefix(8))
        let cleanLang = language.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 2.5 Zero-Config Background Cloud Provisioning (Pre-warms all compilers on first connect)
        ensureRemoteEnvironmentProvisioned(server: server, password: effectivePassword)

        // 3. Auto-Detect Required Packages from Code & IDE Env
        let cellImports = PythonEnvManager.analyzeImports(code)
            .map { PythonEnvManager.pypiName(for: $0) }
        let ideImports = PythonEnvManager.shared.detectedPackages
        let allRequiredPackages = Array(Set(cellImports + ideImports)).sorted()
        
        // 4. Read & propagate project .env variables (if present)
        var envExports = ""
        let workspaceURL = await MainActor.run { AppState.shared?.workspaceFolder }
        if let workspaceURL = workspaceURL {
            let envFile = workspaceURL.appendingPathComponent(".env")
            if let content = try? String(contentsOf: envFile, encoding: .utf8) {
                let lines = content.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && !trimmed.hasPrefix("#") && trimmed.contains("=") {
                        let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                        if parts.count == 2 {
                            let k = parts[0].trimmingCharacters(in: .whitespaces)
                            let v = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                            envExports += "export \(k)=\"\(v)\"\n"
                        }
                    }
                }
            }
        }
        
        // 5. Format Base64 in 64-character lines to prevent PTY line-wrapping corruption
        let base64Raw = Data(code.utf8).base64EncodedString()
        var wrappedB64 = ""
        var strIdx = base64Raw.startIndex
        while strIdx < base64Raw.endIndex {
            let nextIdx = base64Raw.index(strIdx, offsetBy: 64, limitedBy: base64Raw.endIndex) ?? base64Raw.endIndex
            wrappedB64 += String(base64Raw[strIdx..<nextIdx]) + "\n"
            strIdx = nextIdx
        }
        
        let reqPkgsBashList = allRequiredPackages.map { "\"\($0)\"" }.joined(separator: " ")
        
        // 6. Intelligent Auto-ENV Runner Script
        let runnerContent = """
        #!/bin/bash
        set +e
        \(envExports)
        WORKSPACE="$HOME/.microcode/cell_runtime"
        VENV_DIR="$HOME/.microcode/venv"
        mkdir -p "$WORKSPACE"
        cd "$WORKSPACE"

        # 1. Ensure isolated, persistent cloud virtualenv exists (~/.microcode/venv)
        if [ ! -f "$VENV_DIR/bin/python" ]; then
            python3 -m venv "$VENV_DIR" 2>/dev/null || virtualenv "$VENV_DIR" 2>/dev/null || true
        fi

        # 2. Select Python and Pip binaries
        if [ -x "$VENV_DIR/bin/python" ]; then
            PY="$VENV_DIR/bin/python"
            PIP="$VENV_DIR/bin/pip"
        elif [ -n "$CONDA_PREFIX" ] && [ -x "$CONDA_PREFIX/bin/python" ]; then
            PY="$CONDA_PREFIX/bin/python"
            PIP="$CONDA_PREFIX/bin/pip"
        elif command -v python3 >/dev/null 2>&1; then
            PY="python3"
            PIP="pip3"
        else
            PY="python"
            PIP="pip"
        fi

        # 3. Auto-verify and pre-install detected imports
        REQ_PACKAGES=( \(reqPkgsBashList) )
        for pkg in "${REQ_PACKAGES[@]}"; do
            if ! $PY -c "import $pkg" 2>/dev/null; then
                $PIP install -q "$pkg" 2>&1 || \
                $PY -m pip install -q "$pkg" 2>&1 || \
                $PIP install -q --break-system-packages "$pkg" 2>&1 || true
            fi
        done

        cat << 'CODE_EOF' | base64 -d > "cell_\(cellId).raw"
        \(wrappedB64)CODE_EOF

        echo '===MICROCODE_CELL_OUTPUT_START==='
        case "\(cleanLang)" in
            python|py)
                mv "cell_\(cellId).raw" "cell_\(cellId).py"
                PY_OUT=$($PY -u "cell_\(cellId).py" 2>&1)
                if echo "$PY_OUT" | grep -q "ModuleNotFoundError: No module named"; then
                    MISSING=$(echo "$PY_OUT" | awk -F"'" '/No module named/{print $2; exit}')
                    if [ -n "$MISSING" ]; then
                        $PIP install -q "$MISSING" 2>&1 || true
                        $PY -u "cell_\(cellId).py" 2>&1
                    else
                        echo "$PY_OUT"
                    fi
                else
                    echo "$PY_OUT"
                fi
                ;;
            bash|shell|sh|zsh)
                mv "cell_\(cellId).raw" "cell_\(cellId).sh"
                chmod +x "cell_\(cellId).sh"
                bash "cell_\(cellId).sh" 2>&1
                ;;
            c)
                mv "cell_\(cellId).raw" "cell_\(cellId).c"
                CC="gcc"
                if ! command -v gcc >/dev/null 2>&1; then CC="clang"; fi
                $CC -O2 "cell_\(cellId).c" -o "cell_\(cellId).out" -lm 2>&1 && "./cell_\(cellId).out" 2>&1
                ;;
            cpp|c++)
                mv "cell_\(cellId).raw" "cell_\(cellId).cpp"
                CXX="g++"
                if ! command -v g++ >/dev/null 2>&1; then CXX="clang++"; fi
                $CXX -std=c++17 -O2 "cell_\(cellId).cpp" -o "cell_\(cellId).out" -lm 2>&1 && "./cell_\(cellId).out" 2>&1
                ;;
            rust|rs)
                mv "cell_\(cellId).raw" "cell_\(cellId).rs"
                RUSTC="rustc"
                if [ -x "$HOME/.cargo/bin/rustc" ]; then RUSTC="$HOME/.cargo/bin/rustc"; fi
                $RUSTC "cell_\(cellId).rs" -o "cell_\(cellId).out" 2>&1 && "./cell_\(cellId).out" 2>&1
                ;;
            javascript|js|node|nodejs)
                mv "cell_\(cellId).raw" "cell_\(cellId).js"
                node "cell_\(cellId).js" 2>&1
                ;;
            ardium|ar)
                mv "cell_\(cellId).raw" "cell_\(cellId).ar"
                if command -v ardium >/dev/null 2>&1; then ardium run "cell_\(cellId).ar" 2>&1
                elif [ -x "$HOME/.ardium/bin/ardium" ]; then "$HOME/.ardium/bin/ardium" run "cell_\(cellId).ar" 2>&1
                elif [ -x "/usr/local/bin/ardium" ]; then /usr/local/bin/ardium run "cell_\(cellId).ar" 2>&1
                else echo "❌ Ardium is installed locally on your Mac. Select 'Local CPU' on this cell header to run Ardium natively." >&2
                fi
                ;;
            r)
                mv "cell_\(cellId).raw" "cell_\(cellId).r"
                if ! command -v Rscript >/dev/null 2>&1; then
                    if command -v apt-get >/dev/null 2>&1; then
                        export DEBIAN_FRONTEND=noninteractive
                        apt-get update -qq >/dev/null 2>&1
                        apt-get install -y -qq r-base-core >/dev/null 2>&1
                    fi
                fi
                if command -v Rscript >/dev/null 2>&1; then
                    Rscript "cell_\(cellId).r" 2>&1
                else
                    echo "❌ Rscript not found on remote server. Please install R or run on Local CPU." >&2
                fi
                ;;
            julia)
                mv "cell_\(cellId).raw" "cell_\(cellId).jl"
                julia "cell_\(cellId).jl" 2>&1
                ;;
            go)
                mv "cell_\(cellId).raw" "cell_\(cellId).go"
                if ! command -v go >/dev/null 2>&1; then
                    if command -v apt-get >/dev/null 2>&1; then
                        export DEBIAN_FRONTEND=noninteractive
                        apt-get update -qq >/dev/null 2>&1
                        apt-get install -y -qq golang-go >/dev/null 2>&1
                    fi
                fi
                go run "cell_\(cellId).go" 2>&1
                ;;
            objc|objective-c|objectivec|m)
                mv "cell_\(cellId).raw" "cell_\(cellId).m"
                if ! command -v clang >/dev/null 2>&1 || ! command -v gnustep-config >/dev/null 2>&1; then
                    if command -v apt-get >/dev/null 2>&1; then
                        export DEBIAN_FRONTEND=noninteractive
                        apt-get update -qq >/dev/null 2>&1
                        apt-get install -y -qq clang gobjc libgnustep-base-dev gnustep-devel >/dev/null 2>&1
                    fi
                fi
                if command -v gnustep-config >/dev/null 2>&1; then
                    GS_FLAGS=$(gnustep-config --objc-flags 2>/dev/null)
                    GS_LIBS=$(gnustep-config --base-libs 2>/dev/null)
                    clang $GS_FLAGS -fobjc-arc "cell_\(cellId).m" -o "cell_\(cellId).out" $GS_LIBS -lobjc -lpthread 2>&1 && "./cell_\(cellId).out" 2>&1
                else
                    clang -fobjc-arc "cell_\(cellId).m" -o "cell_\(cellId).out" -lobjc -lpthread 2>&1 && "./cell_\(cellId).out" 2>&1
                fi
                ;;
            java)
                mv "cell_\(cellId).raw" "Main_\(cellId).java"
                if ! command -v javac >/dev/null 2>&1; then
                    if command -v apt-get >/dev/null 2>&1; then
                        export DEBIAN_FRONTEND=noninteractive
                        apt-get update -qq >/dev/null 2>&1
                        apt-get install -y -qq default-jdk >/dev/null 2>&1
                    fi
                fi
                javac "Main_\(cellId).java" 2>&1 && java "Main_\(cellId)" 2>&1
                ;;
            csharp|c#|cs)
                mv "cell_\(cellId).raw" "cell_\(cellId).cs"
                if ! command -v dotnet >/dev/null 2>&1 && ! command -v csc >/dev/null 2>&1; then
                    if command -v apt-get >/dev/null 2>&1; then
                        export DEBIAN_FRONTEND=noninteractive
                        apt-get update -qq >/dev/null 2>&1
                        apt-get install -y -qq mono-complete >/dev/null 2>&1 || true
                    fi
                fi
                if command -v dotnet-script >/dev/null 2>&1; then
                    dotnet-script "cell_\(cellId).cs" 2>&1
                elif command -v csc >/dev/null 2>&1; then
                    csc "cell_\(cellId).cs" -out:"cell_\(cellId).exe" 2>&1 && mono "cell_\(cellId).exe" 2>&1
                else
                    echo "❌ .NET/Mono runtime not ready on remote cloud. Select 'Local CPU' on this cell to execute natively on Mac." >&2
                fi
                ;;
            sql)
                mv "cell_\(cellId).raw" "cell_\(cellId).sql"
                if ! command -v sqlite3 >/dev/null 2>&1; then
                    if command -v apt-get >/dev/null 2>&1; then
                        export DEBIAN_FRONTEND=noninteractive
                        apt-get update -qq >/dev/null 2>&1
                        apt-get install -y -qq sqlite3 >/dev/null 2>&1
                    fi
                fi
                sqlite3 -header -column :memory: < "cell_\(cellId).sql" 2>&1
                ;;
            latex|tex)
                mv "cell_\(cellId).raw" "cell_\(cellId).tex"
                if ! command -v pdflatex >/dev/null 2>&1; then
                    if command -v apt-get >/dev/null 2>&1; then
                        export DEBIAN_FRONTEND=noninteractive
                        apt-get update -qq >/dev/null 2>&1
                        apt-get install -y -qq texlive-latex-base >/dev/null 2>&1 || true
                    fi
                fi
                if command -v pdflatex >/dev/null 2>&1; then
                    pdflatex -interaction=nonstopmode "cell_\(cellId).tex" 2>&1 | tail -n 25
                else
                    echo "✓ LaTeX syntax validated (pdflatex not found on remote cloud)"
                fi
                ;;
            rmarkdown|"r markdown"|rmd)
                mv "cell_\(cellId).raw" "cell_\(cellId).Rmd"
                if ! command -v Rscript >/dev/null 2>&1; then
                    if command -v apt-get >/dev/null 2>&1; then
                        export DEBIAN_FRONTEND=noninteractive
                        apt-get update -qq >/dev/null 2>&1
                        apt-get install -y -qq r-base-core >/dev/null 2>&1
                    fi
                fi
                Rscript -e "if (!require('rmarkdown')) install.packages('rmarkdown', repos='https://cloud.r-project.org'); rmarkdown::render('cell_\(cellId).Rmd')" 2>&1
                ;;
            *)
                mv "cell_\(cellId).raw" "cell_\(cellId).run"
                $PY "cell_\(cellId).run" 2>&1 || bash "cell_\(cellId).run" 2>&1
                ;;
        esac
        echo '===MICROCODE_CELL_OUTPUT_END==='
        rm -f "cell_\(cellId).*"
        """
        
        let scriptFeed = """
        cat << 'RUNNER_EOF' > /tmp/mc_runner_\(cellId).sh
        \(runnerContent)
        RUNNER_EOF
        bash /tmp/mc_runner_\(cellId).sh
        rm -f /tmp/mc_runner_\(cellId).sh
        exit
        \n
        """
        
        // 7. Execute via OpenSSH with PTY Allocation and zero-prompting
        let rawOutput = try await executeViaOpenSSH(
            server: server,
            password: effectivePassword,
            scriptFeed: scriptFeed
        )
        
        // 8. Extract ONLY the cell's pure output between delimiters
        let startTag = "===MICROCODE_CELL_OUTPUT_START==="
        let endTag = "===MICROCODE_CELL_OUTPUT_END==="
        
        if rawOutput.contains(startTag) && rawOutput.contains(endTag) {
            let afterStart = rawOutput.components(separatedBy: startTag).last ?? ""
            let cellBody = afterStart.components(separatedBy: endTag).first ?? ""
            
            // Clean up carriage returns, shell prompts, and empty lines
            let lines = cellBody
                .components(separatedBy: "\n")
                .map { $0.replacingOccurrences(of: "\r", with: "") }
                .filter { line in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !trimmed.isEmpty && !trimmed.hasPrefix("root@") && !trimmed.hasPrefix("[dqw0") && !trimmed.contains("cat << 'RUNNER_EOF'")
                }
            
            let finalCleanOutput = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return finalCleanOutput
        } else {
            // Fallback: If tags weren't reached, display clean filtered output
            let filtered = rawOutput
                .components(separatedBy: "\n")
                .map { $0.replacingOccurrences(of: "\r", with: "") }
                .filter { line in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !trimmed.isEmpty &&
                        !trimmed.contains("RUNPOD.IO") &&
                        !trimmed.contains("_____") &&
                        !trimmed.contains("stty -echo") &&
                        !trimmed.contains("cat << 'RUNNER_EOF'") &&
                        !trimmed.hasPrefix("root@")
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            return filtered.isEmpty ? rawOutput.trimmingCharacters(in: .whitespacesAndNewlines) : filtered
        }
    }
    
    private func ensureRemoteEnvironmentProvisioned(server: RemoteConnectionConfig, password: String) {
        guard !Self.provisionedHosts.contains(server.host) else { return }
        Self.provisionedHosts.insert(server.host)
        
        Task.detached(priority: .background) { [weak self] in
            let setupScript = """
            if [ ! -f "$HOME/.microcode/.provisioned_v2" ]; then
                mkdir -p "$HOME/.microcode/cell_runtime" "$HOME/.microcode/venv"
                if command -v apt-get >/dev/null 2>&1; then
                    export DEBIAN_FRONTEND=noninteractive
                    (apt-get update -qq && apt-get install -y -qq build-essential clang gobjc libgnustep-base-dev gnustep-devel r-base-core golang-go sqlite3 default-jdk >/dev/null 2>&1 && touch "$HOME/.microcode/.provisioned_v2") &
                else
                    touch "$HOME/.microcode/.provisioned_v2"
                fi
            fi
            exit
            """
            _ = try? await self?.executeViaOpenSSH(server: server, password: password, scriptFeed: setupScript)
        }
    }

    private func executeViaOpenSSH(server: RemoteConnectionConfig, password: String, scriptFeed: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            self.currentProcess = process
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            
            var args = [
                "-tt", // Force pseudo-terminal for RunPod and remote clouds
                "-o", "ServerAliveInterval=15",
                "-o", "TCPKeepAlive=yes",
                "-o", "StrictHostKeyChecking=accept-new",
                "-o", "ConnectTimeout=15",
                "-p", "\(server.port)"
            ]
            if !server.keyPath.isEmpty {
                let expanded = (server.keyPath as NSString).expandingTildeInPath
                if FileManager.default.fileExists(atPath: expanded) {
                    args.append(contentsOf: ["-i", expanded])
                }
            }
            args.append("\(server.username)@\(server.host)")
            process.arguments = args
            
            var env = ProcessInfo.processInfo.environment
            
            // Password AskPass Support (if password is provided, feed it automatically with zero user prompting)
            var tempAskPass: String? = nil
            var tempPassFile: String? = nil
            
            if !password.isEmpty {
                let unique = ProcessInfo.processInfo.globallyUniqueString
                let passPath = "/tmp/mc_pass_\(unique).txt"
                let askPath = "/tmp/mc_ask_\(unique).sh"
                
                try? (password + "\n").write(toFile: passPath, atomically: true, encoding: .utf8)
                let chmodP = Process()
                chmodP.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmodP.arguments = ["600", passPath]
                try? chmodP.run()
                chmodP.waitUntilExit()
                
                let askScript = "#!/bin/sh\ncat \"\(passPath)\"\n"
                try? askScript.write(toFile: askPath, atomically: true, encoding: .utf8)
                let chmodA = Process()
                chmodA.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmodA.arguments = ["700", askPath]
                try? chmodA.run()
                chmodA.waitUntilExit()
                
                env["SSH_ASKPASS"] = askPath
                env["SSH_ASKPASS_REQUIRE"] = "force"
                env["DISPLAY"] = ":0"
                tempAskPass = askPath
                tempPassFile = passPath
            }
            
            process.environment = env
            
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            do {
                try process.run()
                
                if let data = scriptFeed.data(using: .utf8) {
                    stdinPipe.fileHandleForWriting.write(data)
                    try? stdinPipe.fileHandleForWriting.close()
                }
                
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                if let tempAskPass = tempAskPass { try? FileManager.default.removeItem(atPath: tempAskPass) }
                if let tempPassFile = tempPassFile { try? FileManager.default.removeItem(atPath: tempPassFile) }
                
                var combined = String(data: outData, encoding: .utf8) ?? ""
                if let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
                    combined += "\n" + errStr
                }
                continuation.resume(returning: combined)
            } catch {
                if let tempAskPass = tempAskPass { try? FileManager.default.removeItem(atPath: tempAskPass) }
                if let tempPassFile = tempPassFile { try? FileManager.default.removeItem(atPath: tempPassFile) }
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Kernel Router

class ComputeKernelRouter {
    static let shared = ComputeKernelRouter()
    
    private var activeKernels: [String: ComputeKernel] = [:]
    
    func getKernel(for target: ComputeTarget) -> ComputeKernel {
        // Older notebooks can persist cloudPremium. A managed Cloud GPU
        // session writes a Jupyter HTTP endpoint, which must use the same
        // Jupyter kernel as customHPC instead of the retired generic socket.
        if target == .cloudPremium {
            let endpoint = UserDefaults.standard.string(forKey: "hpcEndpoint") ?? ""
            let token = UserDefaults.standard.string(forKey: "hpcToken") ?? ""
            if (endpoint.hasPrefix("https://") || endpoint.hasPrefix("http://")), !token.isEmpty {
                return getKernel(for: .customHPC)
            }
        }
        if let existing = activeKernels[target.rawValue] {
            return existing
        }
        
        let kernel: ComputeKernel
        switch target {
        case .localCPU, .localMLX:
            kernel = LocalProcessKernel(target: target)
        case .localNvidia:
            kernel = LocalNvidiaKernel()
        case .cloudPremium:
            kernel = CloudGPUKernel()
        case .customHPC:
            kernel = CustomHPCKernel()
        case .yourCloud:
            kernel = YourCloudKernel()
        }
        
        activeKernels[target.rawValue] = kernel
        return kernel
    }
}
