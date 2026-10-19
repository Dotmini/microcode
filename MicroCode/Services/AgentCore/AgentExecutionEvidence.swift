import Foundation

/// Completion checkpoints shared by the primary agent and its harness.
/// A successful read or a started background task is not a verified change.
struct AgentExecutionEvidence {
    static let verifiedSubagentPrefix = "SUBAGENT_VERIFIED_CHANGE\n"
    static let completedSubagentPrefix = "SUBAGENT_COMPLETED\n"

    private var step = 0
    private var latestMutation: Int?
    private var latestVerification: Int?
    private var latestExecution: Int?
    private var latestLaunch: Int?
    private var latestFailure: Int?
    private var latestObservation: Int?
    private(set) var successfulTools = 0

    mutating func record(name: String, arguments: [String: Any], success: Bool, output: String = "") {
        step += 1
        guard success else { latestFailure = step; return }
        successfulTools += 1
        let base = Self.normalize(name)
        let delegatedChange = base == "invoke_subagent" && output.hasPrefix(Self.verifiedSubagentPrefix)
        if Self.mutates(name: name, arguments: arguments) || delegatedChange { latestMutation = step }
        if Self.verifies(name: name, arguments: arguments) || delegatedChange { latestVerification = step }
        if Self.executes(name: name, arguments: arguments) { latestExecution = step }
        if Self.launches(name: name, arguments: arguments) { latestLaunch = step }
        if !["agent_plan", "create_plan", "define_subagent", "send_message", "manage_subagents"].contains(base),
           base != "invoke_subagent" || output.hasPrefix(Self.completedSubagentPrefix) || delegatedChange {
            latestObservation = step
        }
    }

    var hasMutation: Bool { latestMutation != nil }
    var hasVerifiedMutation: Bool {
        guard let mutation = latestMutation else { return true }
        guard let verification = latestVerification ?? latestExecution ?? latestLaunch else { return false }
        return verification >= mutation
    }

    func satisfies(requiresMutation: Bool, requiresExecution: Bool = false, requiresLaunch: Bool = false) -> Bool {
        if requiresMutation {
            guard hasMutation && hasVerifiedMutation else { return false }
        }
        if requiresExecution {
            guard latestExecution != nil || latestLaunch != nil || latestVerification != nil else { return false }
        }
        if requiresLaunch {
            guard latestLaunch != nil || latestExecution != nil else { return false }
        }
        return successfulTools > 0 || (latestObservation ?? 0) > 0
    }

    static func normalize(_ name: String) -> String {
        name.replacingOccurrences(of: "mcp__local__", with: "")
    }

    static func taskRequiresMutation(_ task: String) -> Bool {
        let value = task.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let readOnly = ["read-only", "read only", "do not modify", "don't modify", "do not edit", "don't edit",
                        "do not change", "don't change", "plan only", "ห้ามแก้", "อย่าแก้", "ไม่ต้องแก้", "ยังไม่แก้", "ตรวจอย่างเดียว", "วางแผนอย่างเดียว"]
        if readOnly.contains(where: value.contains) { return false }
        let pureQuestionOrReview = ["ทำไม", "เพราะอะไร", "คืออะไร", "อธิบาย", "เล่าให้ฟัง", "วิเคราะห์", "รีวิว", "explain", "why ", "what is", "what does", "how does"]
        let explicitAction = ["ช่วยแก้", "เริ่มปรับ", "แก้ไข", "สร้างไฟล์", "เขียนโค้ด", "implement", "refactor", "fix ", "patch "]
        if pureQuestionOrReview.contains(where: value.contains) && !explicitAction.contains(where: value.contains) {
            return false
        }
        return ["fix", "implement", "add", "create", "edit", "modify", "change", "redesign", "refactor",
                "rewrite", "patch", "remove", "delete", "write", "update", "แก้", "ทำให้", "เพิ่ม", "สร้าง",
                "เขียน", "เปลี่ยน", "ออกแบบใหม่", "ลบ", "อัปเดต", "ปรับปรุง", "พัฒนา"].contains(where: value.contains)
    }

    static func mutates(name: String, arguments: [String: Any]) -> Bool {
        let base = normalize(name)
        if base == "shell" { return shellMutates(arguments["command"] as? String ?? "") }
        return ["file_write", "replace_in_file", "multi_replace_in_file", "patch_file", "apply_patch", "rename_file", "create_directory", "delete_file",
                "cell_create", "cell_update", "cell_delete"].contains(base)
    }

    static func verifies(name: String, arguments: [String: Any]) -> Bool {
        let base = normalize(name)
        if base == "shell" { return (shellVerifies(arguments["command"] as? String ?? "") || launches(name: name, arguments: arguments)) && !mutates(name: name, arguments: arguments) }
        if base == "device_runtime" {
            return ["build", "test", "run", "diagnostics"].contains((arguments["operation"] as? String ?? "").lowercased())
        }
        return ["get_diagnostics", "lsp_diagnostics", "playground_run", "cell_run", "ardium_run",
                "ardium_compile", "ardium_test", "ardium_diagnose", "visual_regression", "preview_control"].contains(base)
    }

    static func executes(name: String, arguments: [String: Any]) -> Bool {
        let base = normalize(name)
        if base == "shell" {
            let cmd = (arguments["command"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !cmd.isEmpty { return true }
        }
        return verifies(name: name, arguments: arguments) || launches(name: name, arguments: arguments)
    }

    static func launches(name: String, arguments: [String: Any]) -> Bool {
        let base = normalize(name)
        if base == "preview_control" { return true }
        if ["playground_run", "cell_run", "ardium_run"].contains(base) { return true }
        if base == "device_runtime" {
            let op = (arguments["operation"] as? String ?? "").lowercased()
            return ["run", "launch", "open", "start"].contains(op) || op.isEmpty
        }
        guard base == "shell" else { return false }
        let command = (arguments["command"] as? String ?? "").lowercased()
        return ["simctl launch", "devicectl device process launch", "flutter run", "npm run", "npm start",
                "pnpm ", "yarn ", "bun ", "npx vite", "vite", "next ", "nuxt", "svelte", "astro",
                "http.server", "localhost", "127.0.0.1", "lsof -i", "open ", "cargo run", "swift run",
                "dotnet run", "go run", "python", "node ", "deno "].contains(where: command.contains)
    }

    static func shellMutates(_ command: String) -> Bool {
        let value = command.lowercased()
        let markers = ["perl -pi", "perl -i", "sed -i", "apply_patch", "write_text(", "write_bytes(",
                       "shutil.copy", "shutil.move", "os.remove(", "os.rename("]
        if markers.contains(where: value.contains) { return true }
        // Ignore redirections purely to /tmp, /var/tmp, or /dev/null
        let strippedTmpRedirects = value.replacingOccurrences(
            of: #">{1,2}\s*(?:/tmp/[^\s;&|]+|/var/tmp/[^\s;&|]+|/dev/null)"#,
            with: "",
            options: .regularExpression
        )
        return matches(#"(?:^|[;&|]\s*)(?:cp|mv|rm|mkdir|touch|truncate|tee)\s+(?!/tmp/|/var/tmp/)"#, strippedTmpRedirects)
            || matches(#"(?:^|[;&|]\s*)(?:cat|echo|printf)\b[^\n]*[^>]>{1,2}\s*[^&]"#, strippedTmpRedirects)
            || matches(#"open\s*\([^\n]*[,'\"]\s*['\"](?:w|a|x)"#, strippedTmpRedirects)
    }

    static func shellVerifies(_ command: String) -> Bool {
        shellCommands(command).contains { tokens in
            var words = tokens.map { $0.lowercased() }
            if words.first == "env" || words.first == "command" { words.removeFirst() }
            while let first = words.first, matches(#"^[a-z_][a-z0-9_]*="#, first) { words.removeFirst() }
            guard let executable = words.first else { return false }
            let name = (executable as NSString).lastPathComponent
            let args = Array(words.dropFirst())
            if ["cargo", "go", "swift", "dotnet"].contains(name) {
                return args.first.map { ["build", "test", "check", "vet", "run"].contains($0) } ?? false
            }
            if ["npm", "pnpm", "yarn", "bun", "npx"].contains(name) {
                let action = args.first == "run" ? args.dropFirst().first : args.first
                return action.map { ["build", "test", "lint", "typecheck", "check", "dev", "start", "preview", "vite"].contains($0) } ?? false
            }
            if ["flutter", "gradle", "gradlew"].contains(name) {
                return args.contains { ["build", "test", "check", "lint", "analyze", "run"].contains($0) || $0.contains("assemble") }
            }
            if ["python", "python2", "python3"].contains(name) {
                return args.count >= 1
            }
            if ["xcodebuild", "swiftc", "pytest", "tsc", "clang", "clang++", "gcc", "g++", "curl", "lsof"].contains(name) {
                return !args.contains { ["--version", "-version", "--help", "-help", "-list", "-showsdks", "-showbuildsettings"].contains($0) }
            }
            return executable.hasPrefix("./") && matches(#"^(?:build|test|check|verify|run)[^\s]*\.(?:sh|py)$"#, name)
        }
    }

    /// Split actual shell commands while keeping quoted argument text opaque.
    /// For example, `echo "cargo test"` cannot become test evidence.
    private static func shellCommands(_ command: String) -> [[String]] {
        var commands: [[String]] = [], words: [String] = [], word = ""
        var quote: Character?, escaped = false
        func finishWord() { if !word.isEmpty { words.append(word); word = "" } }
        func finishCommand() { finishWord(); if !words.isEmpty { commands.append(words); words = [] } }
        for character in command {
            if escaped { word.append(character); escaped = false; continue }
            if character == "\\", quote != "'" { escaped = true; continue }
            if let activeQuote = quote {
                if character == activeQuote { quote = nil } else { word.append(character) }
                continue
            }
            if character == "'" || character == "\"" { quote = character; continue }
            if character == ";" || character == "&" || character == "|" || character == "\n" { finishCommand(); continue }
            if character.isWhitespace { finishWord() } else { word.append(character) }
        }
        finishCommand()
        return commands
    }

    private static func matches(_ pattern: String, _ value: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
