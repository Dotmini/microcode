//
//  NotebookView.swift (Enhanced Multi-Notebook)
//  MicroCode
//
//  Enhanced with: Multi-notebook support, editable names, data file browser,
//  uniform cell colors, and auto-height code blocks
//
//  Created by SPU AI CLUB
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers


// MARK: - Data File Model

struct DataFile: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let type: DataFileType
    let size: Int64
    
    enum DataFileType: String {
        case csv = "CSV"
        case excel = "Excel"
        case json = "JSON"
        case sql = "SQL"
        case parquet = "Parquet"
        case unknown = "File"
        
        var icon: String {
            switch self {
            case .csv: return "tablecells"
            case .excel: return "tablecells.fill"
            case .json: return "curlybraces"
            case .sql: return "cylinder"
            case .parquet: return "doc.zipper"
            case .unknown: return "doc"
            }
        }
        
        var color: Color {
            switch self {
            case .csv: return .green
            case .excel: return .green
            case .json: return .orange
            case .sql: return .blue
            case .parquet: return .purple
            case .unknown: return .gray
            }
        }
        
        static func from(extension ext: String) -> DataFileType {
            switch ext.lowercased() {
            case "csv": return .csv
            case "xlsx", "xls": return .excel
            case "json": return .json
            case "sql", "sqlite", "db": return .sql
            case "parquet": return .parquet
            default: return .unknown
            }
        }
    }
}

// MARK: - Notebook Model

final class NotebookModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    @Published var cells: [NotebookCellModel] = []
    @Published var dataFiles: [DataFile] = []
    @Published var createdAt: Date = Date()
    @Published var modifiedAt: Date = Date()
    
    init(name: String = "Untitled Notebook") {
        self.name = name
        let initialCell = NotebookCellModel(type: .code, content: "# Your Python code here\nprint('Hello, World!')")
        cells = [initialCell]
    }
}

// MARK: - Cell Language

enum CellLanguage: String, CaseIterable, Identifiable {
    case python = "Python"
    case r = "R"
    case julia = "Julia"
    case sql = "SQL"
    case rust = "Rust"
    case go = "Go"
    case cpp = "C++"
    case objc = "Objective-C"
    case java = "Java"
    case csharp = "C#"
    case rmarkdown = "R Markdown"
    case latex = "LaTeX"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .python: return "p.circle.fill"
        case .r: return "r.circle.fill"
        case .julia: return "j.circle.fill"
        case .sql: return "cylinder.fill"
        case .rust: return "gearshape.fill"
        case .go: return "g.circle.fill"
        case .cpp: return "c.circle.fill"
        case .objc: return "apple.logo"
        case .java: return "cup.and.saucer.fill"
        case .csharp: return "number.circle.fill"
        case .rmarkdown: return "doc.richtext.fill"
        case .latex: return "function"
        }
    }
    
    var color: Color {
        switch self {
        case .python: return .blue
        case .r: return .purple
        case .julia: return .green
        case .sql: return .cyan
        case .rust: return .orange
        case .go: return .mint
        case .cpp: return .blue
        case .objc: return .indigo
        case .java: return .red
        case .csharp: return .purple
        case .rmarkdown: return .teal
        case .latex: return .orange
        }
    }
    
    var defaultContent: String {
        switch self {
        case .python: 
            return "# Your Python code here\nprint('Hello, World!')"
        case .r: 
            return "# Your R code here\nprint('Hello, World!')"
        case .julia:
            return """
            # Your Julia code here
            println("Hello, Julia!")
            
            # Example: Calculate factorial
            function factorial(n)
                n <= 1 ? 1 : n * factorial(n - 1)
            end
            
            println("5! = ", factorial(5))
            """
        case .sql:
            return """
            -- SQL Query
            -- Connect to: sqlite:///path/to/database.db
            
            SELECT * FROM users
            WHERE active = 1
            ORDER BY created_at DESC
            LIMIT 10;
            """
        case .rust:
            return """
            // Rust Code
            fn main() {
                println!("Hello from Rust!");
            }
            """
        case .go:
            return """
            // Go Code
            package main
            
            import "fmt"
            
            func main() {
                fmt.Println("Hello from Go!")
            }

            """
        case .cpp:
            return """
            // C++ Code
            #include <iostream>
            #include <vector>
            #include <numeric>
            
            int main() {
                std::cout << "Hello, C++!" << std::endl;
                
                std::vector<int> numbers = {1, 2, 3, 4, 5};
                int sum = std::accumulate(numbers.begin(), numbers.end(), 0);
                std::cout << "Sum: " << sum << std::endl;
                
                return 0;
            }
            """
        case .objc:
            return """
            // Objective-C Code
            #import <Foundation/Foundation.h>
            
            int main(int argc, const char * argv[]) {
                @autoreleasepool {
                    NSLog(@"Hello, Objective-C!");
                }
                return 0;
            }
            """
        case .java:
            return """
            // Java Code
            public class Main {
                public static void main(String[] args) {
                    System.out.println("Hello, Java!");
                }
            }
            """
        case .csharp:
            return """
            // C# Code
            using System;
            
            Console.WriteLine("Hello, C#!");
            """
        case .rmarkdown:
            return """
            ---
            title: "My Document"
            output: html_document
            ---
            
            ## Introduction
            
            This is an **R Markdown** document.
            
            ```{r}
            # R code chunk
            summary(cars)
            ```
            
            ## Conclusion
            
            You can include LaTeX math: $E = mc^2$
            """
        case .latex:
            return """
            \\documentclass{article}
            \\usepackage{amsmath}
            
            \\begin{document}
            
            \\section{Introduction}
            
            This is a \\LaTeX\\ document.
            
            The quadratic formula:
            \\begin{equation}
                x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}
            \\end{equation}
            
            \\end{document}
            """
        }
    }
    
    /// Whether this language is executable code
    var isExecutable: Bool {
        switch self {
        case .python, .r, .julia, .sql, .rust, .go, .cpp, .objc, .java, .csharp: return true
        case .rmarkdown, .latex: return true  // Rendered via external tools
        }
    }
    
    /// File extension for temp files
    var fileExtension: String {
        switch self {
        case .python: return "py"
        case .r: return "R"
        case .julia: return "jl"
        case .sql: return "sql"
        case .rust: return "rs"
        case .go: return "go"
        case .cpp: return "cpp"
        case .objc: return "m"
        case .java: return "java"
        case .csharp: return "cs"
        case .rmarkdown: return "Rmd"
        case .latex: return "tex"
        }
    }

    /// Resolve a Markdown code-fence tag (```python, ```tex, ```cpp …) to a
    /// CellLanguage, covering the common aliases AI models emit. Returns nil
    /// for unknown tags so the caller can fall back sensibly.
    static func from(fenceTag raw: String) -> CellLanguage? {
        let t = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        switch t {
        case "python", "py", "python3", "ipython": return .python
        case "r", "rscript": return .r
        case "julia", "jl": return .julia
        case "sql", "mysql", "postgresql", "postgres", "sqlite", "plsql", "tsql": return .sql
        case "rust", "rs": return .rust
        case "go", "golang": return .go
        case "cpp", "c++", "cxx", "cc", "c", "h", "hpp": return .cpp
        case "objc", "objective-c", "objectivec", "m", "mm": return .objc
        case "java": return .java
        case "csharp", "c#", "cs", "dotnet", ".net": return .csharp
        case "rmarkdown", "rmd": return .rmarkdown
        case "latex", "tex", "katex": return .latex
        default:
            // Fall back to enum rawValue / fileExtension match.
            return allCases.first {
                $0.rawValue.lowercased() == t || $0.fileExtension.lowercased() == t
            }
        }
    }
}

// MARK: - Notebook Cell Model

final class NotebookCellModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var type: CellType = .code
    @Published var language: CellLanguage = .python  // Default to Python
    @Published var content: String = ""
    @Published var output: String = ""
    @Published var outputImages: [URL] = []  // Images/graphs generated by code
    @Published var executionCount: Int? = nil
    @Published var isExecuting: Bool = false
    @Published var colorTheme: CellColorTheme = .none
    @Published var customColor: CustomCellColor? = nil  // Custom RGB color
    @Published var useCustomColor: Bool = false
    @Published var tag: String = ""   // User name-tag / catalog label for selective run
    @Published var isCollapsed: Bool = false
    @Published var dataFramePath: String? = nil
    @Published var isDataFrame: Bool = false
    
    // Procedure Metadata
    @Published var procedureMetadata: [String: AnyCodable] = [:]
    @Published var generatedCode: String = ""
    
    enum CellType: String, CaseIterable {
        case code = "Code"
        case markdown = "Markdown"
        case raw = "Raw"
        case procedure = "Procedure"
        case agent = "Agent"
    }
    
    init(type: CellType = .code, language: CellLanguage = .python, content: String = "") {
        self.type = type
        self.language = language
        self.content = content.isEmpty && type == .code ? language.defaultContent : content
    }
    
    func clearOutput() {
        output = ""
        outputImages = []
        dataFramePath = nil
        isDataFrame = false
    }
    
    func appendOutput(_ text: String) {
        output += text
    }
    
    // Get the effective background color
    var backgroundColor: Color {
        if useCustomColor, let custom = customColor {
            return custom.color
        }
        return colorTheme.color
    }
    
    // Get the effective border color
    var borderColorValue: Color {
        if useCustomColor, let custom = customColor {
            return custom.borderColor
        }
        return colorTheme.borderColor
    }
}

// MARK: - Notebook ViewModel

@MainActor
final class NotebookViewModel: ObservableObject {
    @Published var notebooks: [NotebookModel] = []
    @Published var activeNotebookId: UUID?
    @Published var selectedCellId: UUID?
    @Published var kernelStatus: String = "Idle"
    @Published var showingSidebar: Bool = true
    @Published var totalExecutions: Int = 0
    @Published var showingDataFilePicker: Bool = false
    @Published var isEditingName: Bool = false
    @Published var workingDirectory: URL
    @Published var selectedPythonPath: String = "python3"  // Can be set from UI
    /// The .mic file this notebook is bound to (Quick Save target). nil → not
    /// yet saved to a user-chosen file (autosave still protects the work).
    @Published var currentFileURL: URL?
    @Published var lastAutoSave: Date?
    private var autoSaveWork: DispatchWorkItem?

    /// Realtime autosave: debounced so rapid typing/runs don't thrash disk.
    /// Always writes the UserDefaults crash-recovery snapshot AND a real .mic
    /// file (the bound file, or a stable autosave.mic) so work is never lost.
    func scheduleAutoSave() {
        autoSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performAutoSave() }
        autoSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func performAutoSave() {
        autoSave() // UserDefaults snapshot (crash recovery — keep)
        guard let notebook = activeNotebook else { return }
        let url = currentFileURL
            ?? workingDirectory.appendingPathComponent("autosave.mic")
        exportAsMic(notebook: notebook, to: url)
        lastAutoSave = Date()
    }

    /// Quick Save → write straight to the bound .mic file (no dialog). If the
    /// notebook has never been saved to a user file, fall back to Save As.
    func quickSave() {
        guard let notebook = activeNotebook else { return }
        if let url = currentFileURL {
            exportAsMic(notebook: notebook, to: url)
            lastAutoSave = Date()
        } else {
            saveAs()
        }
    }

    /// Save As → .mic by default. Remembers the chosen file for Quick Save.
    func saveAs() {
        guard let notebook = activeNotebook else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mic") ?? .data]
        panel.nameFieldStringValue = "\(notebook.name).mic"
        panel.title = "Save Notebook"
        panel.begin { [weak self] response in
            guard response == .OK, var url = panel.url else { return }
            if url.pathExtension != "mic" { url.deletePathExtension(); url.appendPathExtension("mic") }
            self?.exportAsMic(notebook: notebook, to: url)
            self?.currentFileURL = url
            self?.lastAutoSave = Date()
        }
    }

    /// Export a copy as Jupyter .ipynb (does not change the bound .mic file).
    func exportIpynb() {
        guard let notebook = activeNotebook else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ipynb") ?? .json]
        panel.nameFieldStringValue = "\(notebook.name).ipynb"
        panel.title = "Export as Jupyter Notebook"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.exportAsIPYNB(notebook: notebook, to: url)
        }
    }

    var activeNotebook: NotebookModel? {
        notebooks.first { $0.id == activeNotebookId }
    }
    
    init() {
        print("📝 NotebookViewModel: Initializing...")
        // Create working directory with read/write permissions
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let workDir = appSupport.appendingPathComponent("MicroCode/notebooks_workspace")
        self.workingDirectory = workDir
        
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            print("❌ NotebookViewModel: Failed to create directory: \(error)")
        }
        
        // Try to restore from auto-save first
        loadAutoSave()
        
        // If no saved notebooks, create initial
        if notebooks.isEmpty {
            let notebook = NotebookModel(name: "Notebook 1")
            notebooks = [notebook]
            activeNotebookId = notebook.id
            if let firstCell = notebook.cells.first {
                selectedCellId = firstCell.id
            }
        }
        print("📝 NotebookViewModel: Init complete with \(notebooks.count) notebook(s)")
    }
    
    // Get data file paths as Python code for easy import
    func dataFilePaths() -> String {
        guard let notebook = activeNotebook else { return "" }
        var code = "# Data Files\n"
        for file in notebook.dataFiles {
            let varName = file.name.replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: " ", with: "_")
            code += "\(varName) = r'\(file.url.path)'\n"
        }
        return code
    }
    
    func createNotebook() {
        let notebook = NotebookModel(name: "Notebook \(notebooks.count + 1)")
        notebooks.append(notebook)
        activeNotebookId = notebook.id
        if let firstCell = notebook.cells.first {
            selectedCellId = firstCell.id
        }
    }
    
    func deleteNotebook(_ notebook: NotebookModel) {
        guard notebooks.count > 1 else { return }
        notebooks.removeAll { $0.id == notebook.id }
        if activeNotebookId == notebook.id {
            activeNotebookId = notebooks.first?.id
        }
    }
    
    func addCell(type: NotebookCellModel.CellType, language: CellLanguage = .python) {
        guard let notebook = activeNotebook else { return }
        let content: String
        if type == .code {
            content = ""  // Will use language default content
        } else if type == .agent {
            content = "Use the shell tool to list files in the current directory."
        } else {
            content = "# Heading\n\nText here..."
        }
        let newCell = NotebookCellModel(type: type, language: language, content: content)
        
        if let selectedId = selectedCellId,
           let index = notebook.cells.firstIndex(where: { $0.id == selectedId }) {
            notebook.cells.insert(newCell, at: index + 1)
        } else {
            notebook.cells.append(newCell)
        }
        
        selectedCellId = newCell.id
        notebook.modifiedAt = Date()
        scheduleAutoSave()
    }

    func deleteCell(_ cell: NotebookCellModel) {
        guard let notebook = activeNotebook else { return }
        if let idx = notebook.cells.firstIndex(where: { $0.id == cell.id }) {
            notebook.cells.remove(at: idx)
            if selectedCellId == cell.id {
                selectedCellId = notebook.cells.first?.id
            }
            notebook.modifiedAt = Date()
            scheduleAutoSave()
        }
    }

    func moveCell(_ cell: NotebookCellModel, direction: Int) {
        guard let notebook = activeNotebook else { return }
        guard let index = notebook.cells.firstIndex(where: { $0.id == cell.id }) else { return }
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < notebook.cells.count else { return }
        notebook.cells.swapAt(index, newIndex)
        notebook.modifiedAt = Date()
        scheduleAutoSave()
    }
    
    func runCell(_ cell: NotebookCellModel, computeTarget: ComputeTarget = .localCPU) {
        guard cell.type == .code || cell.type == .procedure || cell.type == .agent else { return }

        // Auto-detect 3rd-party imports so the env manager always reflects what
        // the code actually needs without the user typing anything.
        if cell.language == .python {
            _ = PythonEnvManager.shared.detectImportsFromCode(cell.content)
        }

        cell.isExecuting = true
        cell.clearOutput()
        kernelStatus = "Running"
        
        // If it's not a local execution, route to the Compute Kernel
        if computeTarget != .localCPU && computeTarget != .localMLX && computeTarget != .localNvidia {
            Task {
                do {
                    let kernel = ComputeKernelRouter.shared.getKernel(for: computeTarget)
                    try await kernel.start()
                    
                    let result = try await kernel.execute(code: cell.content, language: cell.language.rawValue) { progress in
                        DispatchQueue.main.async {
                            cell.appendOutput(progress)
                        }
                    }
                    
                    DispatchQueue.main.async {
                        cell.appendOutput(result + "\n")
                        cell.isExecuting = false
                        self.kernelStatus = "Idle"
                        cell.executionCount = (cell.executionCount ?? 0) + 1
                        self.totalExecutions += 1
                    }
                } catch {
                    DispatchQueue.main.async {
                        cell.appendOutput("❌ Kernel Error: \(error.localizedDescription)\n")
                        cell.isExecuting = false
                        self.kernelStatus = "Error"
                    }
                }
            }
            return
        }
        
        if cell.type == .agent {
            runAgentCell(cell)
            return
        }
        
        if cell.type == .procedure {
            runProcedureCell(cell)
            return
        }
        
        switch cell.language {
        case .python:
            runPythonCell(cell)
        case .r:
            runRCell(cell)
        case .julia:
            runJuliaCell(cell)
        case .sql:
            runSQLCell(cell)
        case .rmarkdown:
            runRMarkdownCell(cell)
        case .latex:
            runLaTeXCell(cell)
        case .rust:
            runRustCell(cell)
        case .go:
            runGoCell(cell)

        case .cpp:
            runCppCell(cell)
        case .objc:
            runObjcCell(cell)
        case .java, .csharp:
            Task { @MainActor in
                cell.isExecuting = true
                cell.output = ""
                cell.appendOutput("❌ Local execution for \(cell.language.rawValue) is not supported natively. Please use 'Custom HPC Agent' to connect to a Jupyter Kernel.\n")
                cell.isExecuting = false
            }
        }
    }
    
    private func runProcedureCell(_ cell: NotebookCellModel) {
        // Procedure cells always run as Python with generated code
        runPythonCell(cell)
    }
    
    private func runAgentCell(_ cell: NotebookCellModel) {
        let cellID = cell.id
        let prompt = cell.content
        let workingDir = workingDirectory.path
        
        // Find existing AgentToolBox instance or create a local scope one
        let toolBox = AgentToolBox.shared
        toolBox.workspaceRoot = workingDir
        
        let systemPrompt = """
        You are a highly capable OS-Level Agent executing inside a MicroCode Notebook cell.
        You have direct access to the user's local machine via tool calls.
        Your current working directory is: \(workingDir)
        
        You can execute tools by using the following XML format:
        <call:shell_command>{"command": "ls -la"}</call:shell_command>
        <call:file_write>{"path": "test.txt", "content": "hello"}</call:file_write>
        
        Available Tools:
        - shell_command: Run any bash command (arguments: command)
        - file_write: Write a file (arguments: path, content)
        - file_read: Read a file (arguments: path)
        
        Execute the user's instructions and output your findings or actions taken.
        """
        
        // We capture the view model context to update UI
        DispatchQueue.main.async {
            cell.appendOutput("🤖 [Agent Booting] Initializing OS-Level execution...\n")
        }
        
        let model = UserDefaults.standard.string(forKey: "aiModel") ?? "gemini-2.5-flash"
        
        AIClient.shared.sendMessage(
            prompt: prompt,
            systemPrompt: systemPrompt,
            provider: .gemini,
            model: model,
            apiKey: "",
            onToken: { token in
                DispatchQueue.main.async {
                    cell.appendOutput(token)
                }
            },
            onComplete: { fullResponse in
                // Extremely simple tool execution regex fallback
                // If the response contains <call:shell_command>{"command": "..."}</call:shell_command>
                let regex = try? NSRegularExpression(pattern: "<call:(shell_command|file_write|file_read)>\\s*\\{(.*?)\\}\\s*</call:\\1>", options: [.dotMatchesLineSeparators])
                let nsString = fullResponse as NSString
                
                if let matches = regex?.matches(in: fullResponse, range: NSRange(location: 0, length: nsString.length)), !matches.isEmpty {
                    DispatchQueue.main.async {
                        cell.appendOutput("\n\n⚙️ [Agent Executing Tool]...\n")
                    }
                    
                    for match in matches {
                        let toolName = nsString.substring(with: match.range(at: 1))
                        let argsString = "{" + nsString.substring(with: match.range(at: 2)) + "}"
                        
                        var args: [String: Any] = [:]
                        if let data = argsString.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            args = json
                        } else {
                            // Basic fallback if JSON parsing fails
                            if toolName == "shell_command" {
                                let cmdRegex = try? NSRegularExpression(pattern: "\"command\"\\s*:\\s*\"([^\"]+)\"")
                                if let cmdMatch = cmdRegex?.firstMatch(in: argsString, range: NSRange(location: 0, length: argsString.utf16.count)) {
                                    args["command"] = (argsString as NSString).substring(with: cmdMatch.range(at: 1))
                                }
                            }
                        }
                        
                        // Execute Tool
                        Task {
                            let result = (try? await toolBox.execute(toolName, params: args)) ?? "Error executing tool"
                            DispatchQueue.main.async {
                                cell.appendOutput("\n[Tool Output (\(toolName))]:\n\(result)\n")
                                cell.isExecuting = false
                                self.kernelStatus = "Idle"
                                cell.executionCount = (cell.executionCount ?? 0) + 1
                                self.totalExecutions += 1
                            }
                        }
                        return // Wait for tool execution
                    }
                } else {
                    DispatchQueue.main.async {
                        cell.isExecuting = false
                        self.kernelStatus = "Idle"
                        cell.executionCount = (cell.executionCount ?? 0) + 1
                        self.totalExecutions += 1
                    }
                }
            },
            onError: { error in
                DispatchQueue.main.async {
                    cell.appendOutput("\n❌ Agent Error: \(error)\n")
                    cell.isExecuting = false
                    self.kernelStatus = "Error"
                }
            }
        )
    }
    
    private func runRustCell(_ cell: NotebookCellModel) {
        // Find rustc
        var rustcPath = "rustc"
        if let runtime = RuntimeManager.shared.runtimes.first(where: { $0.type == .rust }), let path = runtime.path {
             rustcPath = path
        }
        
        let uuid = UUID().uuidString.prefix(8)
        let workingDir = workingDirectory
        let tempRs = workingDir.appendingPathComponent("temp_\(uuid).rs")
        let tempBin = workingDir.appendingPathComponent("temp_\(uuid)")
        let content = cell.content
        let cellID = cell.id
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try content.write(to: tempRs, atomically: true, encoding: .utf8)
                
                // 1. Compile
                let compileProcess = Process()
                // Handle if rustcPath is just command or full path
                if rustcPath.contains("/") {
                    compileProcess.executableURL = URL(fileURLWithPath: rustcPath)
                } else {
                    compileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    compileProcess.arguments = ["rustc", tempRs.path, "-o", tempBin.path]
                }
                
                if compileProcess.arguments == nil { // If using absolute path
                    compileProcess.arguments = [tempRs.path, "-o", tempBin.path]
                }
                
                compileProcess.currentDirectoryURL = workingDir
                
                let compileErrorPipe = Pipe()
                compileProcess.standardError = compileErrorPipe
                
                try compileProcess.run()
                compileProcess.waitUntilExit()
                
                let compileErrorData = compileErrorPipe.fileHandleForReading.readDataToEndOfFile()
                let compileError = String(data: compileErrorData, encoding: .utf8) ?? ""
                
                if compileProcess.terminationStatus == 0 {
                    // 2. Run
                    let runProcess = Process()
                    runProcess.executableURL = tempBin
                    runProcess.currentDirectoryURL = workingDir
                    
                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    runProcess.standardOutput = outputPipe
                    runProcess.standardError = errorPipe
                    
                    try runProcess.run()
                    runProcess.waitUntilExit()
                    
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let error = String(data: errorData, encoding: .utf8) ?? ""
                    
                    // Cleanup binary
                    try? FileManager.default.removeItem(at: tempBin)
                    
                    let result = output + (error.isEmpty ? "" : "\n" + error)
                    self.handleCellOutput(cellID: cellID, result: result)
                    
                } else {
                    // Compile failed
                    let result = "❌ Compilation Failed:\n" + compileError
                    self.handleCellOutput(cellID: cellID, result: result)
                }
                
                // Cleanup source
                try? FileManager.default.removeItem(at: tempRs)
                
            } catch {
                let result = "❌ Error: \(error.localizedDescription)"
                self.handleCellOutput(cellID: cellID, result: result)
            }
        }
    }
    


    private func runGoCell(_ cell: NotebookCellModel) {
        // Find go
        var goPath = "go"
        if let runtime = RuntimeManager.shared.runtimes.first(where: { $0.type == .go }), let path = runtime.path {
             goPath = path
             // Helper: if path points to 'go' binary inside bin, use it.
             // Usually RuntimeManager returns path to binary.
        }
        
        let uuid = UUID().uuidString.prefix(8)
        let workingDir = workingDirectory
        let tempGo = workingDir.appendingPathComponent("temp_\(uuid).go")
        let content = cell.content
        let cellID = cell.id
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try content.write(to: tempGo, atomically: true, encoding: .utf8)
                
                let process = Process()
                if goPath.contains("/") {
                    process.executableURL = URL(fileURLWithPath: goPath)
                } else {
                     process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                     process.arguments = ["go", "run", tempGo.path]
                }
                
                if process.arguments == nil {
                    process.arguments = ["run", tempGo.path]
                }
                
                process.currentDirectoryURL = workingDir
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                try process.run()
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                // Cleanup
                try? FileManager.default.removeItem(at: tempGo)
                
                let result = output + (error.isEmpty ? "" : "\n" + error)
                self.handleCellOutput(cellID: cellID, result: result)
                
            } catch {
                let result = "❌ Error: \(error.localizedDescription)"
                self.handleCellOutput(cellID: cellID, result: result)
            }
        }
    }
    
    private func runCppCell(_ cell: NotebookCellModel) {
        let uuid = UUID().uuidString.prefix(8)
        let workingDir = workingDirectory
        let tempCpp = workingDir.appendingPathComponent("temp_\(uuid).cpp")
        let tempBin = workingDir.appendingPathComponent("temp_\(uuid)")
        let content = cell.content
        let cellID = cell.id
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try content.write(to: tempCpp, atomically: true, encoding: .utf8)
                
                // 1. Compile: clang++ -o tempBin tempCpp
                let compileProcess = Process()
                compileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                compileProcess.arguments = ["clang++", tempCpp.path, "-o", tempBin.path]
                compileProcess.currentDirectoryURL = workingDir
                
                let compileErrorPipe = Pipe()
                compileProcess.standardError = compileErrorPipe
                
                try compileProcess.run()
                compileProcess.waitUntilExit()
                
                let compileErrorData = compileErrorPipe.fileHandleForReading.readDataToEndOfFile()
                let compileError = String(data: compileErrorData, encoding: .utf8) ?? ""
                
                if compileProcess.terminationStatus == 0 {
                    // 2. Run
                    let runProcess = Process()
                    runProcess.executableURL = tempBin
                    runProcess.currentDirectoryURL = workingDir
                    
                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    runProcess.standardOutput = outputPipe
                    runProcess.standardError = errorPipe
                    
                    try runProcess.run()
                    runProcess.waitUntilExit()
                    
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let error = String(data: errorData, encoding: .utf8) ?? ""
                    
                    // Cleanup binary
                    try? FileManager.default.removeItem(at: tempBin)
                    
                    let result = output + (error.isEmpty ? "" : "\n" + error)
                    self.handleCellOutput(cellID: cellID, result: result)
                    
                } else {
                    // Compile failed
                    let result = "❌ Compilation Failed:\n" + compileError
                    self.handleCellOutput(cellID: cellID, result: result)
                }
                
                // Cleanup source
                try? FileManager.default.removeItem(at: tempCpp)
                
            } catch {
                let result = "❌ Error: \(error.localizedDescription)"
                self.handleCellOutput(cellID: cellID, result: result)
            }
        }
    }
    
    private func runObjcCell(_ cell: NotebookCellModel) {
        let uuid = UUID().uuidString.prefix(8)
        let workingDir = workingDirectory
        let tempObjc = workingDir.appendingPathComponent("temp_\(uuid).m")
        let tempBin = workingDir.appendingPathComponent("temp_\(uuid)")
        let content = cell.content
        let cellID = cell.id
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try content.write(to: tempObjc, atomically: true, encoding: .utf8)
                
                // 1. Compile: clang -framework Foundation -o tempBin tempObjc
                let compileProcess = Process()
                compileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                compileProcess.arguments = ["clang", "-framework", "Foundation", tempObjc.path, "-o", tempBin.path]
                compileProcess.currentDirectoryURL = workingDir
                
                let compileErrorPipe = Pipe()
                compileProcess.standardError = compileErrorPipe
                
                try compileProcess.run()
                compileProcess.waitUntilExit()
                
                let compileErrorData = compileErrorPipe.fileHandleForReading.readDataToEndOfFile()
                let compileError = String(data: compileErrorData, encoding: .utf8) ?? ""
                
                if compileProcess.terminationStatus == 0 {
                    // 2. Run
                    let runProcess = Process()
                    runProcess.executableURL = tempBin
                    runProcess.currentDirectoryURL = workingDir
                    
                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    runProcess.standardOutput = outputPipe
                    runProcess.standardError = errorPipe
                    
                    try runProcess.run()
                    runProcess.waitUntilExit()
                    
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let error = String(data: errorData, encoding: .utf8) ?? ""
                    
                    // Cleanup binary
                    try? FileManager.default.removeItem(at: tempBin)
                    
                    let result = output + (error.isEmpty ? "" : "\n" + error)
                    self.handleCellOutput(cellID: cellID, result: result)
                    
                } else {
                    // Compile failed
                    let result = "❌ Compilation Failed:\n" + compileError
                    self.handleCellOutput(cellID: cellID, result: result)
                }
                
                // Cleanup source
                try? FileManager.default.removeItem(at: tempObjc)
                
            } catch {
                let result = "❌ Error: \(error.localizedDescription)"
                self.handleCellOutput(cellID: cellID, result: result)
            }
        }
    }
    
    private func runPythonCell(_ cell: NotebookCellModel) {
        // Simple setup code - no user content in strings to avoid syntax issues
        let setupCode = """
        import os
        import sys
        os.chdir(r'\(workingDirectory.path)')
        
        # MicroCode Shared Memory Bridge
        \(SharedMemoryService.shared.getPythonBridgeCode())
        
        # Setup matplotlib for inline display
        try:
            import matplotlib
            matplotlib.use('Agg')
            import matplotlib.pyplot as plt
            plt.ioff()
        except:
            pass
        
        """
        
        
        // User's code runs here
        let userCode = cell.type == .procedure ? cell.generatedCode : cell.content
        
        // Auto-save matplotlib figures after execution
        let saveCode = """
        
        # Auto-save matplotlib figures
        try:
            import matplotlib.pyplot as plt
            figs = [plt.figure(n) for n in plt.get_fignums()]
            for i, fig in enumerate(figs):
                fig.savefig(f'output_{i}.png', dpi=100, bbox_inches='tight')
                print(f'[IMAGE:output_{i}.png]')
            plt.close('all')
        except:
            pass
        """
        
        let fullCode = setupCode + userCode + saveCode
        
        // Use selected Python version or active environment
        let pythonPath = PythonEnvManager.shared.activeEnvironment?.pythonPath ?? selectedPythonPath
        let cellID = cell.id
        PythonEnvManager.shared.executeCode(fullCode, pythonPath: pythonPath) { [weak self] result, success in
            self?.handleCellOutput(cellID: cellID, result: result)
        }
    }
    
    private func runRCell(_ cell: NotebookCellModel) {
        // Find Rscript
        let rPaths = ["/opt/homebrew/bin/Rscript", "/usr/local/bin/Rscript", "/usr/bin/Rscript"]
        guard let rPath = rPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            DispatchQueue.main.async {
                cell.output = "❌ R is not installed. Please install R from https://cran.r-project.org/"
                cell.isExecuting = false
                self.kernelStatus = "Idle"
            }
            return
        }
        
        // R setup code for graphics
        let setupCode = """
        setwd("\(workingDirectory.path)")
        
        # Setup for saving plots
        .plot_counter <- 0
        .save_plot <- function() {
            .plot_counter <<- .plot_counter + 1
            filename <- paste0("output_", .plot_counter, ".png")
            dev.copy(png, filename, width = 800, height = 600)
            dev.off()
            cat(paste0("[IMAGE:", filename, "]\\n"))
        }
        
        """
        
        // Auto-save plots code
        let saveCode = """
        
        # Auto-save any open plots
        tryCatch({
            if (dev.cur() > 1) {
                .save_plot()
            }
        }, error = function(e) {})
        """
        
        let fullCode = setupCode + cell.content + saveCode
        let workingDir = workingDirectory
        let tempFile = workingDir.appendingPathComponent("temp_script_\(UUID().uuidString).R")
        let cellID = cell.id
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try fullCode.write(to: tempFile, atomically: true, encoding: .utf8)
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: rPath)
                process.arguments = ["--vanilla", tempFile.path]
                process.currentDirectoryURL = workingDir
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                try process.run()
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let result = process.terminationStatus == 0 ? output : (output + "\n" + error)
                
                // Cleanup temp file
                try? FileManager.default.removeItem(at: tempFile)
                
                self.handleCellOutput(cellID: cellID, result: result)
            } catch {
                DispatchQueue.main.async {
                    // This creates a capture of 'cell'. We need to avoid it.
                    // But we used 'cell.id' and 'cellID'. We need to resolve cell safely.
                    // For simplicity, we can use handleCellOutput for errors too.
                    self.handleCellOutput(cellID: cellID, result: "❌ Error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    nonisolated private func handleCellOutput(cellID: UUID, result: String) {
        // Check for DataFrame metadata
        var isDataFrame = false
        var dfPath: String? = nil
        
        if let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let isDF = json["__microcode_dataframe__"] as? Bool, isDF,
           let path = json["path"] as? String {
            isDataFrame = true
            dfPath = path
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let notebook = self.activeNotebook,
                  let cell = notebook.cells.first(where: { $0.id == cellID }) else { return }
            
            if isDataFrame, let path = dfPath {
                cell.output = "" // Clear text output
                cell.dataFramePath = path
                cell.isDataFrame = true
                cell.executionCount = (self.totalExecutions + 1)
                cell.isExecuting = false
                self.totalExecutions += 1
                self.kernelStatus = "Idle"
                return
            }
            
            // Parse output for image markers
            var textOutput = result
            var images: [URL] = []
            
            // Find [IMAGE:filename] markers
            let pattern = "\\[IMAGE:([^\\]]+)\\]"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: result) {
                        let filename = String(result[range])
                        let imageURL = self.workingDirectory.appendingPathComponent(filename)
                        if FileManager.default.fileExists(atPath: imageURL.path) {
                            images.append(imageURL)
                        }
                    }
                }
                // Remove image markers from text output
                textOutput = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
            
            cell.output = textOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            cell.outputImages = images
            cell.isExecuting = false
            self.totalExecutions += 1
            cell.executionCount = self.totalExecutions
            self.kernelStatus = "Idle"
            self.activeNotebook?.modifiedAt = Date()
        }
    }
    
    private func runRMarkdownCell(_ cell: NotebookCellModel) {
        // Find R executable
        let rPaths = ["/opt/homebrew/bin/R", "/usr/local/bin/R", "/usr/bin/R"]
        guard let rPath = rPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            DispatchQueue.main.async {
                cell.output = "❌ R is not installed. Install R from https://cran.r-project.org/"
                cell.isExecuting = false
                self.kernelStatus = "Idle"
            }
            return
        }
        
        let workingDir = workingDirectory
        let tempRmd = workingDir.appendingPathComponent("temp_\(UUID().uuidString).Rmd")
        let outputHtml = workingDir.appendingPathComponent("temp_\(UUID().uuidString).html")
        let content = cell.content
        let cellID = cell.id
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try content.write(to: tempRmd, atomically: true, encoding: .utf8)
                
                // Render R Markdown using rmarkdown::render()
                let renderScript = """
                rmarkdown::render('\(tempRmd.path)', output_file = '\(outputHtml.path)', quiet = TRUE)
                cat('[RMARKDOWN_OUTPUT:\(outputHtml.path)]')
                """
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: rPath)
                process.arguments = ["-e", renderScript]
                process.currentDirectoryURL = workingDir
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                try process.run()
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                // Cleanup temp files
                try? FileManager.default.removeItem(at: tempRmd)
                
                if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputHtml.path) {
                    // Read the HTML output
                    let htmlContent = try? String(contentsOf: outputHtml, encoding: .utf8)
                    let summary = "✅ R Markdown rendered successfully!\n📄 Output: \(outputHtml.lastPathComponent)\n\nPreview (first 500 chars):\n" + (htmlContent?.prefix(500).description ?? "")
                    
                    self.handleCellOutput(cellID: cellID, result: summary)
                    // Note: We need to set outputImages too. handleCellOutput parses them.
                    // But here we construct a summary.
                    // To support outputImages properly via handleCellOutput, we normally embed [IMAGE:path].
                    // Or we can modify cell if we Dispatch.main (which we do in handleCellOutput).
                    // But here we had custom logic.
                    // Let's rely on handleCellOutput, but it overwrites outputImages based on parsing.
                    // We can embed the [IMAGE:...] for the HTML file.
                    // Or update handleCellOutput to append?
                    // The original code set cell.outputImages = [outputHtml] directly.
                    // Let's modify handleCellOutput to accept optional images?
                    // Or, stick to the original logic which updated cell directly in Dispatch.main.
                    // BUT we have cellID now. So we need to look it up.
                } else {
                    let result = "❌ R Markdown render failed:\n" + error + "\n" + output
                    self.handleCellOutput(cellID: cellID, result: result)
                }
            } catch {
                self.handleCellOutput(cellID: cellID, result: "❌ Error: \(error.localizedDescription)")
            }
        }
    }
    
    private func runLaTeXCell(_ cell: NotebookCellModel) {
        // Find pdflatex or xelatex
        let latexPaths = [
            "/Library/TeX/texbin/pdflatex",
            "/usr/local/texlive/2024/bin/universal-darwin/pdflatex",
            "/usr/local/texlive/2023/bin/universal-darwin/pdflatex",
            "/opt/homebrew/bin/pdflatex",
            "/usr/bin/pdflatex"
        ]
        guard let latexPath = latexPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            DispatchQueue.main.async {
                cell.output = "❌ LaTeX is not installed. Install MacTeX from https://tug.org/mactex/"
                cell.isExecuting = false
                self.kernelStatus = "Idle"
            }
            return
        }
        
        let uuid = UUID().uuidString.prefix(8)
        let workingDir = workingDirectory
        let tempTex = workingDir.appendingPathComponent("temp_\(uuid).tex")
        let tempPdf = workingDir.appendingPathComponent("temp_\(uuid).pdf")
        let content = cell.content
        let cellID = cell.id
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try content.write(to: tempTex, atomically: true, encoding: .utf8)
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: latexPath)
                process.arguments = ["-interaction=nonstopmode", "-output-directory=\(workingDir.path)", tempTex.path]
                process.currentDirectoryURL = workingDir
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                try process.run()
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                // Cleanup auxiliary files
                let auxExtensions = ["aux", "log", "out", "toc", "tex"]
                for ext in auxExtensions {
                    let auxFile = workingDir.appendingPathComponent("temp_\(uuid).\(ext)")
                    try? FileManager.default.removeItem(at: auxFile)
                }
                
                if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: tempPdf.path) {
                     // For correct handling in handleCellOutput, we need to ensure the PDF is picked up.
                     // handleCellOutput looks for [IMAGE:filename].
                     // Let's construct a result string that includes that.
                     let summary = "✅ LaTeX compiled successfully!\n📄 PDF: \(tempPdf.lastPathComponent)\n\n💡 Tip: Click the PDF to open it.\n[IMAGE:\(tempPdf.lastPathComponent)]"
                     
                     self.handleCellOutput(cellID: cellID, result: summary)
                } else {
                    // Extract errors from log
                    let logFile = workingDir.appendingPathComponent("temp_\(uuid).log")
                    let logContent = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
                    let errorLines = logContent.components(separatedBy: "\n").filter { $0.contains("!") || $0.contains("Error") }
                    
                    let errorSummary = errorLines.isEmpty ? error + output : errorLines.joined(separator: "\n")
                    let result = "❌ LaTeX compilation failed:\n\(errorSummary)"
                    self.handleCellOutput(cellID: cellID, result: result)
                }
            } catch {
                self.handleCellOutput(cellID: cellID, result: "❌ Error: \(error.localizedDescription)")
            }
        }
    }
    
    private func runJuliaCell(_ cell: NotebookCellModel) {
        // Find Julia executable
        let juliaPaths = [
            "/Applications/Julia-1.10.app/Contents/Resources/julia/bin/julia",
            "/Applications/Julia-1.9.app/Contents/Resources/julia/bin/julia",
            "/opt/homebrew/bin/julia",
            "/usr/local/bin/julia",
            "/usr/bin/julia"
        ]
        guard let juliaPath = juliaPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            DispatchQueue.main.async {
                cell.output = "❌ Julia is not installed. Install from https://julialang.org/downloads/"
                cell.isExecuting = false
                self.kernelStatus = "Idle"
            }
            return
        }
        
        let workingDir = workingDirectory
        let tempFile = workingDir.appendingPathComponent("temp_\(UUID().uuidString).jl")
        
        // Setup code for plots
        let setupCode = """
        cd("\(workingDir.path)")
        
        """
        
        let fullCode = setupCode + cell.content
        let cellID = cell.id
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try fullCode.write(to: tempFile, atomically: true, encoding: .utf8)
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: juliaPath)
                process.arguments = [tempFile.path]
                process.currentDirectoryURL = workingDir
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                try process.run()
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let result = process.terminationStatus == 0 ? output : (output + "\n" + error)
                
                try? FileManager.default.removeItem(at: tempFile)
                
                self.handleCellOutput(cellID: cellID, result: result)
            } catch {
                self.handleCellOutput(cellID: cellID, result: "❌ Error: \(error.localizedDescription)")
            }
        }
    }
    
    private func runSQLCell(_ cell: NotebookCellModel) {
        // Parse connection string from comment: -- Connect to: sqlite:///path/to/db
        var dbPath = workingDirectory.appendingPathComponent("notebook.db").path
        
        let lines = cell.content.components(separatedBy: "\n")
        for line in lines {
            if line.lowercased().contains("connect to:") {
                if let range = line.range(of: "sqlite:///") {
                    dbPath = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        // Filter out comments for execution
        let sqlStatements = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("--") }.joined(separator: "\n")
        
        // Use Python's sqlite3 to execute SQL
        let pythonCode = """
        import sqlite3
        import os
        
        db_path = r'\(dbPath)'
        
        # Create database if it doesn't exist
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        sql = '''\(sqlStatements)'''
        
        try:
            # Split and execute multiple statements
            for statement in sql.strip().split(';'):
                statement = statement.strip()
                if statement:
                    cursor.execute(statement)
            
            # If it's a SELECT query, fetch and display results
            if sql.strip().upper().startswith('SELECT'):
                rows = cursor.fetchall()
                columns = [desc[0] for desc in cursor.description] if cursor.description else []
                
                if columns:
                    # Print header
                    print(' | '.join(columns))
                    print('-' * (len(' | '.join(columns)) + 10))
                    
                    # Print rows
                    for row in rows:
                        print(' | '.join(str(cell) for cell in row))
                    
                    print(f'\\n{len(rows)} rows returned')
            else:
                conn.commit()
                print(f'Query executed successfully. Rows affected: {cursor.rowcount}')
        
        except Exception as e:
            print(f'SQL Error: {e}')
        finally:
            conn.close()
        """
        
        let pythonPath = PythonEnvManager.shared.activeEnvironment?.pythonPath ?? selectedPythonPath
        let cellID = cell.id
        PythonEnvManager.shared.executeCode(pythonCode, pythonPath: pythonPath) { [weak self] result, success in
            self?.handleCellOutput(cellID: cellID, result: result)
        }
    }
    
    // MARK: - Run Cells by Color
    
    func runCellsByColor(_ colorTheme: CellColorTheme, computeTarget: ComputeTarget = .localCPU) {
        guard let notebook = activeNotebook else { return }
        let cellsToRun = notebook.cells.filter { $0.colorTheme == colorTheme && $0.type == .code }
        
        for cell in cellsToRun {
            runCell(cell, computeTarget: computeTarget)
        }
    }
    
    func getCellsByColor() -> [CellColorTheme: [NotebookCellModel]] {
        guard let notebook = activeNotebook else { return [:] }
        
        var grouped: [CellColorTheme: [NotebookCellModel]] = [:]
        for cell in notebook.cells where cell.type == .code {
            let theme = cell.colorTheme
            if grouped[theme] == nil {
                grouped[theme] = []
            }
            grouped[theme]?.append(cell)
        }
        return grouped
    }
    
    func getUsedColors() -> [CellColorTheme] {
        let grouped = getCellsByColor()
        return grouped.keys.sorted { $0.rawValue < $1.rawValue }
    }

    /// Distinct non-empty name-tags across runnable cells (any language).
    func getUsedTags() -> [String] {
        guard let notebook = activeNotebook else { return [] }
        let tags = notebook.cells
            .filter { $0.type == .code || $0.type == .procedure || $0.type == .agent }
            .map { $0.tag.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(Set(tags)).sorted()
    }

    /// Run every runnable cell carrying the given name-tag, in order, across
    /// all languages (each cell runs via its own `cell.language`).
    func runCellsByTag(_ tag: String, computeTarget: ComputeTarget = .localCPU) {
        guard let notebook = activeNotebook else { return }
        let key = tag.trimmingCharacters(in: .whitespaces)
        for cell in notebook.cells where
            (cell.type == .code || cell.type == .procedure || cell.type == .agent)
            && cell.tag.trimmingCharacters(in: .whitespaces) == key {
            runCell(cell, computeTarget: computeTarget)
        }
    }
    
    func runSelectedCell(computeTarget: ComputeTarget = .localCPU) {
        guard let notebook = activeNotebook,
              let id = selectedCellId,
              let cell = notebook.cells.first(where: { $0.id == id }) else { return }
        runCell(cell, computeTarget: computeTarget)
    }
    
    func runAllCells(computeTarget: ComputeTarget = .localCPU) {
        guard let notebook = activeNotebook else { return }
        for cell in notebook.cells where cell.type == .code {
            runCell(cell, computeTarget: computeTarget)
        }
    }
    
    func clearAllOutputs() {
        guard let notebook = activeNotebook else { return }
        for cell in notebook.cells {
            cell.output = ""
            cell.executionCount = nil
        }
    }
    
    func restartKernel() {
        clearAllOutputs()
        totalExecutions = 0
        kernelStatus = "Restarted"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.kernelStatus = "Idle"
        }
    }
    
    func addDataFile(_ url: URL) {
        guard let notebook = activeNotebook else { return }
        
        // Prepare data directory in workspace
        let dataDir = workingDirectory.appendingPathComponent("data")
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let destURL = dataDir.appendingPathComponent(url.lastPathComponent)
        
        // Remove existing mock file if any
        try? FileManager.default.removeItem(at: destURL)
        
        // Copy file to workspace data folder to allow access via "data/filename"
        do {
            try FileManager.default.copyItem(at: url, to: destURL)
        } catch {
            print("Failed to copy data file: \(error)")
        }
        
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? Int64) ?? 0
        let dataFile = DataFile(
            name: url.lastPathComponent,
            url: url,
            type: DataFile.DataFileType.from(extension: url.pathExtension),
            size: size
        )
        notebook.dataFiles.append(dataFile)
    }
    
    func removeDataFile(_ file: DataFile) {
        guard let notebook = activeNotebook else { return }
        notebook.dataFiles.removeAll { $0.id == file.id }
    }
    
    func saveNotebook() {
        guard let notebook = activeNotebook else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "mic") ?? .data,
            UTType(filenameExtension: "mcnb") ?? .json,
            UTType(filenameExtension: "ipynb") ?? .json,
            .json
        ]
        panel.nameFieldStringValue = "\(notebook.name).mic"
        panel.title = "Save Notebook"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            if url.pathExtension == "ipynb" {
                self.exportAsIPYNB(notebook: notebook, to: url)
            } else if url.pathExtension == "mic" {
                self.exportAsMic(notebook: notebook, to: url)
            } else {
                self.saveAsMCNB(notebook: notebook, to: url)
            }
        }
    }
    
    // MARK: - MicroCode Native Format (.mcnb)
    
    func saveAsMCNB(notebook: NotebookModel, to url: URL) {
        var cellsArray: [[String: Any]] = []
        
        for cell in notebook.cells {
            var cellDict: [String: Any] = [
                "id": cell.id.uuidString,
                "type": cell.type.rawValue,
                "language": cell.language.rawValue,
                "content": cell.content,
                "output": cell.output,
                "execution_count": cell.executionCount as Any,
                "color_theme": cell.colorTheme.rawValue,
                "tag": cell.tag,
                "is_collapsed": cell.isCollapsed,
                "use_custom_color": cell.useCustomColor,
            ]
            
            if let custom = cell.customColor {
                cellDict["custom_color"] = [
                    "red": custom.red,
                    "green": custom.green,
                    "blue": custom.blue,
                    "opacity": custom.opacity
                ]
            }
            
            // Save output images paths
            if !cell.outputImages.isEmpty {
                cellDict["output_images"] = cell.outputImages.map { $0.path }
            }
            
            cellsArray.append(cellDict)
        }
        
        let notebookDict: [String: Any] = [
            "format": "mcnb",
            "version": 1,
            "name": notebook.name,
            "created_at": ISO8601DateFormatter().string(from: notebook.createdAt),
            "modified_at": ISO8601DateFormatter().string(from: Date()),
            "cells": cellsArray,
            "metadata": [
                "app": "MicroCode",
                "app_version": "1.0.1",
                "total_executions": totalExecutions
            ]
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: notebookDict, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
            print("✅ Saved notebook to \(url.lastPathComponent)")
        } catch {
            print("❌ Failed to save notebook: \(error)")
        }
    }
    
    // MARK: - Load MicroCode Notebook (.mcnb)
    
    func loadNotebook(from url: URL) {
        if url.pathExtension == "mic" {
            loadFromMic(url: url)
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Invalid notebook format")
                return
            }
            
            let format = dict["format"] as? String ?? ""
            
            if format == "mcnb" {
                loadMCNB(dict: dict)
            } else if dict["nbformat"] != nil {
                loadIPYNB(dict: dict, fileName: url.deletingPathExtension().lastPathComponent)
            } else {
                print("❌ Unknown notebook format")
            }
        } catch {
            print("❌ Failed to load notebook: \(error)")
        }
    }
    
    private func loadMCNB(dict: [String: Any]) {
        let name = dict["name"] as? String ?? "Imported Notebook"
        let notebook = NotebookModel(name: name)
        notebook.cells.removeAll()
        
        if let cellsArray = dict["cells"] as? [[String: Any]] {
            for cellDict in cellsArray {
                let typeStr = cellDict["type"] as? String ?? "Code"
                let langStr = cellDict["language"] as? String ?? "Python"
                let content = cellDict["content"] as? String ?? ""
                let output = cellDict["output"] as? String ?? ""
                let executionCount = cellDict["execution_count"] as? Int
                let colorThemeStr = cellDict["color_theme"] as? String ?? "none"
                let isCollapsed = cellDict["is_collapsed"] as? Bool ?? false
                let useCustomColor = cellDict["use_custom_color"] as? Bool ?? false
                
                let cellType = NotebookCellModel.CellType(rawValue: typeStr) ?? .code
                let language = CellLanguage(rawValue: langStr) ?? .python
                
                let cell = NotebookCellModel(type: cellType, language: language, content: content)
                cell.output = output
                cell.executionCount = executionCount
                cell.colorTheme = CellColorTheme(rawValue: colorThemeStr) ?? .none
                cell.tag = cellDict["tag"] as? String ?? ""
                cell.isCollapsed = isCollapsed
                cell.useCustomColor = useCustomColor
                
                if let customColorDict = cellDict["custom_color"] as? [String: Double] {
                    cell.customColor = CustomCellColor(
                        red: customColorDict["red"] ?? 0,
                        green: customColorDict["green"] ?? 0,
                        blue: customColorDict["blue"] ?? 0,
                        opacity: customColorDict["opacity"] ?? 1
                    )
                }
                
                notebook.cells.append(cell)
            }
        }
        
        if let createdStr = dict["created_at"] as? String {
            notebook.createdAt = ISO8601DateFormatter().date(from: createdStr) ?? Date()
        }
        
        notebooks.append(notebook)
        activeNotebookId = notebook.id
        selectedCellId = notebook.cells.first?.id
        
        print("✅ Loaded notebook: \(name) (\(notebook.cells.count) cells)")
    }
    
    // MARK: - Load Jupyter Notebook (.ipynb)
    
    private func loadIPYNB(dict: [String: Any], fileName: String) {
        let notebook = NotebookModel(name: fileName)
        notebook.cells.removeAll()
        
        if let cellsArray = dict["cells"] as? [[String: Any]] {
            for cellDict in cellsArray {
                let cellTypeStr = cellDict["cell_type"] as? String ?? "code"
                let cellType: NotebookCellModel.CellType
                switch cellTypeStr {
                case "code": cellType = .code
                case "markdown": cellType = .markdown
                case "raw": cellType = .raw
                default: cellType = .code
                }
                
                // Source can be array of strings or a single string
                let content: String
                if let sourceArray = cellDict["source"] as? [String] {
                    content = sourceArray.joined()
                } else {
                    content = cellDict["source"] as? String ?? ""
                }
                
                // Detect language from metadata or kernel
                var language: CellLanguage = .python
                if let metadata = cellDict["metadata"] as? [String: Any],
                   let langStr = metadata["language"] as? String {
                    language = CellLanguage.allCases.first(where: { $0.rawValue.lowercased() == langStr.lowercased() }) ?? .python
                }
                
                let cell = NotebookCellModel(type: cellType, language: language, content: content)
                cell.executionCount = cellDict["execution_count"] as? Int
                
                // Parse outputs
                if let outputs = cellDict["outputs"] as? [[String: Any]] {
                    var outputText = ""
                    for output in outputs {
                        if let text = output["text"] as? [String] {
                            outputText += text.joined()
                        } else if let text = output["text"] as? String {
                            outputText += text
                        } else if let data = output["data"] as? [String: Any],
                                  let plainText = data["text/plain"] as? [String] {
                            outputText += plainText.joined()
                        }
                    }
                    cell.output = outputText
                }
                
                notebook.cells.append(cell)
            }
        }
        
        notebooks.append(notebook)
        activeNotebookId = notebook.id
        selectedCellId = notebook.cells.first?.id
        
        print("✅ Imported Jupyter notebook: \(fileName) (\(notebook.cells.count) cells)")
    }
    
    // MARK: - Export as Jupyter (.ipynb)
    
    func exportAsIPYNB(notebook: NotebookModel, to url: URL) {
        var jsonCells: [[String: Any]] = []
        
        for cell in notebook.cells {
            var cellDict: [String: Any] = [
                "cell_type": cell.type == .code ? "code" : (cell.type == .markdown ? "markdown" : "raw"),
                "metadata": [
                    "language": cell.language.rawValue
                ],
                "source": cell.content.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) + "\n" }
            ]
            
            if cell.type == .code {
                cellDict["execution_count"] = cell.executionCount
                cellDict["outputs"] = cell.output.isEmpty ? [] : [
                    [
                        "output_type": "stream",
                        "name": "stdout",
                        "text": cell.output.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) + "\n" }
                    ]
                ]
            }
            
            jsonCells.append(cellDict)
        }
        
        let notebookDict: [String: Any] = [
            "cells": jsonCells,
            "metadata": [
                "kernelspec": [
                    "display_name": "Python 3",
                    "language": "python",
                    "name": "python3"
                ],
                "language_info": [
                    "name": "python",
                    "version": "3.8.5"
                ],
                "microcode": [
                    "version": "1.0.1",
                    "multi_language": true
                ]
            ],
            "nbformat": 4,
            "nbformat_minor": 4
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: notebookDict, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
            print("✅ Exported as .ipynb to \(url.lastPathComponent)")
        } catch {
            print("❌ Failed to export .ipynb: \(error)")
        }
    }
    
    // MARK: - .mic Format (MicroCode Notebook)
    func exportAsMic(notebook: NotebookModel, to url: URL) {
        do {
            let micNotebook = MicNotebook(from: notebook)
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(micNotebook)
            // LZFSE Compression
            let compressedData = try (jsonData as NSData).compressed(using: .lzfse)
            try compressedData.write(to: url)
            print("✅ Exported as .mic to \(url.lastPathComponent)")
        } catch {
            print("❌ Failed to export .mic: \(error)")
        }
    }
    
    func loadFromMic(url: URL) {
        do {
            let compressedData = try Data(contentsOf: url)
            // LZFSE Decompression
            let decompressedData = try (compressedData as NSData).decompressed(using: .lzfse)
            let decoder = JSONDecoder()
            let micNotebook = try decoder.decode(MicNotebook.self, from: decompressedData as Data)
            let notebook = micNotebook.toModel()
            
            DispatchQueue.main.async {
                self.notebooks.append(notebook)
                self.activeNotebookId = notebook.id
                self.currentFileURL = url   // Quick Save now targets this file
                if let firstCell = notebook.cells.first {
                    self.selectedCellId = firstCell.id
                }
            }
            print("✅ Loaded .mic from \(url.lastPathComponent)")
        } catch {
            print("❌ Failed to load .mic: \(error)")
        }
    }
    
    // MARK: - Auto-Save to UserDefaults
    
    func autoSave() {
        var allNotebooks: [[String: Any]] = []
        
        for notebook in notebooks {
            var cellsArray: [[String: Any]] = []
            for cell in notebook.cells {
                var cellDict: [String: Any] = [
                    "type": cell.type.rawValue,
                    "language": cell.language.rawValue,
                    "content": cell.content,
                    "output": cell.output,
                    "color_theme": cell.colorTheme.rawValue,
                    "tag": cell.tag,
                    "is_collapsed": cell.isCollapsed,
                ]
                if let ec = cell.executionCount { cellDict["execution_count"] = ec }
                cellsArray.append(cellDict)
            }
            
            allNotebooks.append([
                "id": notebook.id.uuidString,
                "name": notebook.name,
                "cells": cellsArray,
                "created_at": ISO8601DateFormatter().string(from: notebook.createdAt),
                "modified_at": ISO8601DateFormatter().string(from: Date())
            ])
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: [
            "notebooks": allNotebooks,
            "active_id": activeNotebookId?.uuidString ?? ""
        ]) {
            UserDefaults.standard.set(data, forKey: "microcode_notebooks_autosave")
        }
    }
    
    func loadAutoSave() {
        guard let data = UserDefaults.standard.data(forKey: "microcode_notebooks_autosave"),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let notebooksArray = dict["notebooks"] as? [[String: Any]],
              !notebooksArray.isEmpty else { return }
        
        notebooks.removeAll()
        
        for nbDict in notebooksArray {
            let name = nbDict["name"] as? String ?? "Notebook"
            let notebook = NotebookModel(name: name)
            notebook.cells.removeAll()
            
            if let createdStr = nbDict["created_at"] as? String {
                notebook.createdAt = ISO8601DateFormatter().date(from: createdStr) ?? Date()
            }
            
            if let cellsArray = nbDict["cells"] as? [[String: Any]] {
                for cellDict in cellsArray {
                    let typeStr = cellDict["type"] as? String ?? "Code"
                    let langStr = cellDict["language"] as? String ?? "Python"
                    let content = cellDict["content"] as? String ?? ""
                    let output = cellDict["output"] as? String ?? ""
                    let executionCount = cellDict["execution_count"] as? Int
                    let colorStr = cellDict["color_theme"] as? String ?? "none"
                    let isCollapsed = cellDict["is_collapsed"] as? Bool ?? false
                    
                    let cellType = NotebookCellModel.CellType(rawValue: typeStr) ?? .code
                    let language = CellLanguage(rawValue: langStr) ?? .python
                    
                    let cell = NotebookCellModel(type: cellType, language: language, content: content)
                    cell.output = output
                    cell.executionCount = executionCount
                    cell.colorTheme = CellColorTheme(rawValue: colorStr) ?? .none
                    cell.tag = cellDict["tag"] as? String ?? ""
                    cell.isCollapsed = isCollapsed
                    
                    notebook.cells.append(cell)
                }
            }
            
            notebooks.append(notebook)
        }
        
        let activeIdStr = dict["active_id"] as? String ?? ""
        activeNotebookId = notebooks.first(where: { $0.id.uuidString == activeIdStr })?.id ?? notebooks.first?.id
        selectedCellId = activeNotebook?.cells.first?.id
        
        print("✅ Restored \(notebooks.count) notebook(s) from auto-save")
    }
}

// MARK: - Main Notebook View

struct NotebookView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = NotebookViewModel()
    @ObservedObject private var pythonEnvManager = PythonEnvManager.shared
    @ObservedObject private var shmService = SharedMemoryService.shared
    @State private var isReady = false
    @State private var showAIPanel = false
    @State private var showingHPCSettings = false
    
    private var panelBackground: Color {
        appState.appTheme == .transparent ? Color.white.opacity(0.05) : Color(nsColor: .windowBackgroundColor)
    }
    
    private var controlBackground: Color {
        appState.appTheme == .transparent ? Color.white.opacity(0.08) : Color(nsColor: .controlBackgroundColor)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            if viewModel.showingSidebar {
                notebookSidebar
                    .frame(width: 260)
                Divider()
            }
            
            // Main Content
            VStack(spacing: 0) {
                notebookToolbar
                
                Divider()
                
                // Cells Area
                if let notebook = viewModel.activeNotebook {
                    // Observes the NotebookModel directly so add/delete/reorder
                    // of cells refreshes the list INSTANTLY (previously the
                    // model was reached via a computed property and never
                    // @ObservedObject, so deleting a non-selected cell only
                    // updated on the next unrelated viewModel change → lag).
                    NotebookCellsList(notebook: notebook, viewModel: viewModel)
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading notebook...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            
            // AI Agent Panel (Right Side)
            if showAIPanel {
                Divider()
                NotebookAIPanel(
                    viewModel: viewModel,
                    isShowing: $showAIPanel
                )
                .frame(width: 380)
                .transition(.move(edge: .trailing))
            }
        }
        .fileImporter(
            isPresented: $viewModel.showingDataFilePicker,
            allowedContentTypes: [.commaSeparatedText, .json, .data, .item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    viewModel.addDataFile(url)
                }
            }
        }
        .onAppear {
            CrashReporter.shared.breadcrumb("NotebookView.onAppear notebooks=\(viewModel.notebooks.count)")
            isReady = true
            // Ensure notebook is active
            if viewModel.activeNotebookId == nil && !viewModel.notebooks.isEmpty {
                viewModel.activeNotebookId = viewModel.notebooks.first?.id
            }
            // Sync Python version with appState
            viewModel.selectedPythonPath = appState.selectedPythonVersion
            
            // Check if code was exported from AI Agent
            if let exportedCode = appState.aiExportedCode, !exportedCode.isEmpty {
                // Add a new cell with the exported code
                viewModel.addCell(type: .code, language: .python)
                if let lastCell = viewModel.activeNotebook?.cells.last {
                    lastCell.content = exportedCode
                }
                appState.aiExportedCode = nil // Clear after consuming
                print("🚀 NotebookView: Loaded code from AI Agent into new cell")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ApplyCodeToCell"))) { notification in
            guard let code = notification.userInfo?["code"] as? String,
                  !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            // SMART + SAFE: AI-generated code ALWAYS becomes a brand-new cell.
            // It must never overwrite or inject into an existing cell (the
            // user's previous work is untouchable). Language is resolved from
            // the AI code-fence tag for ALL supported languages — LaTeX, C++,
            // Go, Rust, SQL, Java, etc. — not just Python/R.
            let langStr = notification.userInfo?["language"] as? String ?? ""
            let language = CellLanguage.from(fenceTag: langStr)
                ?? viewModel.activeNotebook?.cells.last?.language
                ?? .python

            viewModel.addCell(type: .code, language: language)
            if let newCell = viewModel.activeNotebook?.cells.last {
                newCell.content = code
                viewModel.selectedCellId = newCell.id   // focus the new cell
                viewModel.scheduleAutoSave()
            }
        }
    }
    
    // MARK: - Open Notebook File
    
    private func openNotebookFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "mic") ?? .data,
            UTType(filenameExtension: "mcnb") ?? .json,
            UTType(filenameExtension: "ipynb") ?? .json,
            .json
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.loadNotebook(from: url)
        }
    }
    
    // MARK: - Sidebar
    
    private var notebookSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.orange)
                Text("Notebooks")
                    .font(.headline)
                Spacer()
                
                Button(action: { viewModel.createNotebook() }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(controlBackground)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Notebook List
                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.notebooks) { notebook in
                                NotebookListItem(
                                    notebook: notebook,
                                    isActive: viewModel.activeNotebookId == notebook.id,
                                    onSelect: { viewModel.activeNotebookId = notebook.id },
                                    onDelete: { viewModel.deleteNotebook(notebook) }
                                )
                            }
                        }
                    }
                    
                    // Kernel Status
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle()
                                    .fill(viewModel.kernelStatus == "Running" ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text("Python 3")
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                Text(viewModel.kernelStatus)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            // Python Env Selector - Safe access
                            if isReady {
                                Menu {
                                    Button("System Python") {
                                        pythonEnvManager.activeEnvironment = nil
                                    }
                                    Divider()
                                    ForEach(pythonEnvManager.environments) { env in
                                        Button(env.name) {
                                            pythonEnvManager.activateEnvironment(env)
                                        }
                                    }
                                    Divider()
                                    Button("Manage Environments...") {
                                        // Auto-detect required packages from ALL cells so the
                                        // env sheet opens with them pre-filled (Auto-first UX).
                                        let allCode = (viewModel.activeNotebook?.cells ?? [])
                                            .filter { $0.type == .code }
                                            .map { $0.content }
                                            .joined(separator: "\n")
                                        _ = pythonEnvManager.detectImportsFromCode(allCode)
                                        appState.showingPythonEnv = true
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "terminal")
                                            .foregroundColor(.green)
                                        Text(pythonEnvManager.activeEnvironment?.name ?? "System")
                                            .font(.caption)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                    }
                                    .padding(6)
                                    .background(controlBackground)
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text("Loading...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Data Files
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Data Files")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: { viewModel.showingDataFilePicker = true }) {
                                    Image(systemName: "plus.circle")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if let notebook = viewModel.activeNotebook, !notebook.dataFiles.isEmpty {
                                ForEach(notebook.dataFiles) { file in
                                    DataFileRow(file: file, onRemove: {
                                        viewModel.removeDataFile(file)
                                    })
                                }
                            } else {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 4) {
                                        Image(systemName: "doc.badge.plus")
                                            .font(.title3)
                                            .foregroundColor(.secondary)
                                        Text("No data files")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                            }
                        }
                    }

                    // Shared DataFrames
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Shared Memory (SHM)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: { Task { await SharedMemoryService.shared.refreshList() } }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if !SharedMemoryService.shared.sharedDataFrames.isEmpty {
                                ForEach(SharedMemoryService.shared.sharedDataFrames, id: \.self) { name in
                                    HStack {
                                        Image(systemName: "memorychip")
                                            .foregroundColor(.blue)
                                        Text(name)
                                            .font(.system(size: 11))
                                        Spacer()
                                        Button(action: {
                                            // Action to inspect/add cell to load
                                        }) {
                                            Image(systemName: "info.circle")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            } else {
                                Text("No shared data")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                    
                    // Actions
                    GroupBox {
                        VStack(spacing: 8) {
                            Menu {
                                Button {
                                    viewModel.runAllCells(computeTarget: appState.currentComputeTarget)
                                } label: { Label("Run All Cells", systemImage: "forward.fill") }

                                let colors = viewModel.getUsedColors().filter { $0 != .none }
                                if !colors.isEmpty {
                                    Menu("Run by Color") {
                                        ForEach(colors, id: \.self) { theme in
                                            Button {
                                                viewModel.runCellsByColor(theme, computeTarget: appState.currentComputeTarget)
                                            } label: {
                                                Label(theme.rawValue.capitalized, systemImage: "circle.fill")
                                            }
                                        }
                                    }
                                }

                                let tags = viewModel.getUsedTags()
                                if !tags.isEmpty {
                                    Menu("Run by Tag") {
                                        ForEach(tags, id: \.self) { t in
                                            Button {
                                                viewModel.runCellsByTag(t, computeTarget: appState.currentComputeTarget)
                                            } label: { Label(t, systemImage: "tag.fill") }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Run…")
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                                }
                            } primaryAction: {
                                viewModel.runAllCells(computeTarget: appState.currentComputeTarget)
                            }
                            .menuStyle(.borderlessButton)
                            .buttonStyle(.plain)
                            
                            Button(action: { viewModel.clearAllOutputs() }) {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Clear Outputs")
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { viewModel.restartKernel() }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Restart Kernel")
                                    Spacer()
                                }
                                .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Toolbar
    
    private var notebookToolbar: some View {
        HStack(spacing: 6) {
            // Sidebar toggle
            Button(action: { viewModel.showingSidebar.toggle() }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            
            Divider().frame(height: 14)
            
            // Notebook Name (compact, truncated)
            if let notebook = viewModel.activeNotebook {
                if viewModel.isEditingName {
                    TextField("Name", text: Binding(
                        get: { notebook.name },
                        set: { notebook.name = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: 140)
                    .onSubmit { viewModel.isEditingName = false }
                } else {
                    Text(notebook.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 120, alignment: .leading)
                        .onTapGesture(count: 2) {
                            viewModel.isEditingName = true
                        }
                }
                
                Button(action: { viewModel.isEditingName.toggle() }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // --- Right side: compact icon buttons ---
            
            // Compute Engine Selector
            Menu {
                Text("Compute Engine")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(ComputeTarget.allCases) { target in
                    Button {
                        appState.currentComputeTarget = target
                    } label: {
                        HStack {
                            Text(target.rawValue)
                            if appState.currentComputeTarget == target {
                                Image(systemName: "checkmark")
                            }
                            if target.isPremium {
                                Image(systemName: "star.fill")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.currentComputeTarget.icon)
                        .foregroundColor(appState.currentComputeTarget.isPremium ? .orange : .secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .font(.system(size: 11))
            }
            .menuIndicator(.hidden)
            .help("Select Compute Engine: \(appState.currentComputeTarget.rawValue)")
            
            if appState.currentComputeTarget == .customHPC {
                Button(action: { showingHPCSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Configure Custom HPC Agent")
                .popover(isPresented: $showingHPCSettings, arrowEdge: .bottom) {
                    HPCSettingsView()
                        .environmentObject(appState)
                }
            }
            
            // Token Balance
            if appState.currentComputeTarget.isPremium || appState.userTokenBalance > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.yellow)
                    Text("\(appState.userTokenBalance)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(4)
                .help("Token Balance: \(appState.userTokenBalance)")
                
                Divider().frame(height: 14)
            }
            
            // Python version (icon-only)
            pythonVersionMenu
            
            // Add Cell
            Menu {
                Text("Code Cells")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button { viewModel.addCell(type: .code, language: .python) } label: {
                    Label("Python", systemImage: "p.circle.fill")
                }
                Button { viewModel.addCell(type: .code, language: .r) } label: {
                    Label("R", systemImage: "r.circle.fill")
                }
                Button { viewModel.addCell(type: .code, language: .julia) } label: {
                    Label("Julia", systemImage: "j.circle.fill")
                }
                Button { viewModel.addCell(type: .code, language: .sql) } label: {
                    Label("SQL", systemImage: "cylinder.fill")
                }
                
                Divider()
                
                Text("Compiled")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button { viewModel.addCell(type: .code, language: .rust) } label: {
                    Label("Rust", systemImage: "gearshape.fill")
                }
                Button { viewModel.addCell(type: .code, language: .go) } label: {
                    Label("Go", systemImage: "g.circle.fill")
                }
                Button { viewModel.addCell(type: .code, language: .cpp) } label: {
                    Label("C++", systemImage: "c.circle.fill")
                }
                Button { viewModel.addCell(type: .code, language: .objc) } label: {
                    Label("Objective-C", systemImage: "apple.logo")
                }
                
                Divider()
                
                Text("Documents")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button { viewModel.addCell(type: .code, language: .rmarkdown) } label: {
                    Label("R Markdown", systemImage: "doc.richtext.fill")
                }
                Button { viewModel.addCell(type: .code, language: .latex) } label: {
                    Label("LaTeX", systemImage: "function")
                }
                
                Divider()
                
                Button("Markdown") { viewModel.addCell(type: .markdown) }
                Button("Raw") { viewModel.addCell(type: .raw) }
                
                Divider()
                
                Button { viewModel.addCell(type: .procedure) } label: {
                    Label("SAS Procedure", systemImage: "tablecells.fill")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12))
            }
            .menuIndicator(.hidden)
            .help("Add Cell")
            
            Divider().frame(height: 14)
            
            // Run
            Button(action: { viewModel.runSelectedCell(computeTarget: appState.currentComputeTarget) }) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
            }
            .disabled(viewModel.selectedCellId == nil)
            .help("Run Selected Cell")
            
            // Run All
            Menu {
                Button(action: { viewModel.runAllCells(computeTarget: appState.currentComputeTarget) }) {
                    Label("Run All Cells", systemImage: "forward.fill")
                }
                
                Divider()
                
                let usedColors = viewModel.getUsedColors().filter { $0 != .none }
                if !usedColors.isEmpty {
                    Menu("Run by Color") {
                        ForEach(usedColors) { theme in
                            Button {
                                viewModel.runCellsByColor(theme, computeTarget: appState.currentComputeTarget)
                            } label: {
                                HStack {
                                    Circle().fill(theme.iconColor).frame(width: 8, height: 8)
                                    Text(theme.rawValue.capitalized)
                                }
                            }
                        }
                    }
                }

                let usedTags = viewModel.getUsedTags()
                if !usedTags.isEmpty {
                    Menu("Run by Tag") {
                        ForEach(usedTags, id: \.self) { t in
                            Button {
                                viewModel.runCellsByTag(t, computeTarget: appState.currentComputeTarget)
                            } label: { Label(t, systemImage: "tag.fill") }
                        }
                    }
                }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 11))
            } primaryAction: {
                viewModel.runAllCells(computeTarget: appState.currentComputeTarget)
            }
            .menuIndicator(.hidden)
            .help("Run All")
            
            Divider().frame(height: 14)
            
            // Open
            Button(action: { openNotebookFile() }) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
            }
            .help("Open Notebook")
            
            // Save (autosaves continuously; .mic is the default format)
            Menu {
                Button(action: { viewModel.quickSave() }) {
                    Label("Quick Save (.mic)", systemImage: "bolt.fill")
                }
                .keyboardShortcut("s", modifiers: .command)
                Button(action: { viewModel.saveAs() }) {
                    Label("Save As… (.mic)", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button(action: { viewModel.exportIpynb() }) {
                    Label("Export as Jupyter (.ipynb)", systemImage: "arrow.up.forward.square")
                }
                Divider()
                if let t = viewModel.lastAutoSave {
                    Text("Autosaved \(t.formatted(date: .omitted, time: .standard))")
                } else {
                    Text("Autosave on")
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11))
            } primaryAction: {
                viewModel.quickSave()
            }
            .menuIndicator(.hidden)
            .help("Save — autosaves continuously (.mic). Menu: Save As / Export .ipynb")
            
            Divider().frame(height: 14)
            
            // Execution count (compact)
            Text("\(viewModel.totalExecutions)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
                .help("Total Executions: \(viewModel.totalExecutions)")
            
            // AI Toggle
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showAIPanel.toggle() } }) {
                Image(systemName: showAIPanel ? "brain.fill" : "brain")
                    .font(.system(size: 12))
                    .foregroundColor(showAIPanel ? .accentColor : .secondary)
                    .frame(width: 24, height: 24)
                    .background(showAIPanel ? Color.accentColor.opacity(0.12) : Color.clear)
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("AI Agent")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Python Version Menu
    
    private var pythonVersionMenu: some View {
        Menu {
            Text("Python Version")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if appState.availablePythonVersions.isEmpty {
                Button("python3 (default)") {
                    appState.selectedPythonVersion = "python3"
                    viewModel.selectedPythonPath = "python3"
                    pythonEnvManager.activeEnvironment = nil
                }
            } else {
                ForEach(appState.availablePythonVersions) { version in
                    Button {
                        appState.selectedPythonVersion = version.path
                        viewModel.selectedPythonPath = version.path
                        pythonEnvManager.activeEnvironment = nil
                    } label: {
                        HStack {
                            Text(version.displayName)
                            if appState.selectedPythonVersion == version.path {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            if !pythonEnvManager.environments.isEmpty {
                Divider()
                
                Text("Virtual Environments")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(pythonEnvManager.environments) { env in
                    Button {
                        pythonEnvManager.activateEnvironment(env)
                    } label: {
                        HStack {
                            Text(env.name)
                            if pythonEnvManager.activeEnvironment?.id == env.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            Button("Refresh Versions") {
                // TODO: Fix AppState access pattern
                // appState.detectPythonVersions()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundColor(.green)
                Text(currentPythonDisplay)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(controlBackground)
            .cornerRadius(4)
        }
    }
    
    private var currentPythonDisplay: String {
        if let env = pythonEnvManager.activeEnvironment {
            return "venv: \(env.name)"
        }
        if let version = appState.availablePythonVersions.first(where: { $0.path == appState.selectedPythonVersion }) {
            return version.displayName
        }
        return "Python"
    }
    
}

// MARK: - Notebook List Item

struct NotebookListItem: View {
    @ObservedObject var notebook: NotebookModel
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundColor(isActive ? .orange : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(notebook.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                
                Text("\(notebook.cells.count) cells")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Data File Row

struct DataFileRow: View {
    let file: DataFile
    let onRemove: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file.type.icon)
                .foregroundColor(file.type.color)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                
                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(file.type.rawValue)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(file.type.color.opacity(0.2))
                .cornerRadius(3)
            
            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            // Copy mock path to clipboard
            let mockPath = "data/\(file.name)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(mockPath, forType: .string)
            
            // Show toast or feedback (here just printing to console for simplicity, ideally visual feedback)
            print("Copied path: \(mockPath)")
        }
        .contextMenu {
            Button("Copy Path") {
                let mockPath = "data/\(file.name)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(mockPath, forType: .string)
            }
            
            Button("Copy Full Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.url.path, forType: .string)
            }
            
            Divider()
            
            Button("Remove") {
                onRemove()
            }
        }
    }
}

// MARK: - Notebook Cells List (observes NotebookModel for realtime add/delete)

struct NotebookCellsList: View {
    @ObservedObject var notebook: NotebookModel
    @ObservedObject var viewModel: NotebookViewModel
    @EnvironmentObject var appState: AppState

    private var controlBackground: Color {
        appState.appTheme == .transparent ? Color.white.opacity(0.08) : Color(nsColor: .controlBackgroundColor)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(notebook.cells) { cell in
                    NotebookCellView(
                        cell: cell,
                        isSelected: viewModel.selectedCellId == cell.id,
                        onSelect: { viewModel.selectedCellId = cell.id },
                        onRun: { viewModel.runCell(cell, computeTarget: appState.currentComputeTarget) },
                        onDelete: { viewModel.deleteCell(cell) },
                        onMoveUp: { viewModel.moveCell(cell, direction: -1) },
                        onMoveDown: { viewModel.moveCell(cell, direction: 1) },
                        onGenerateCode: { code in
                            viewModel.addCell(type: .code, language: .python)
                            if let lastCell = viewModel.activeNotebook?.cells.last {
                                lastCell.content = code
                                viewModel.runCell(lastCell, computeTarget: appState.currentComputeTarget)
                            }
                        }
                    )
                    // Realtime autosave on every keystroke / output / tag /
                    // language change (debounced inside the view model).
                    .onChange(of: cell.content) { _ in viewModel.scheduleAutoSave() }
                    .onChange(of: cell.output) { _ in viewModel.scheduleAutoSave() }
                    .onChange(of: cell.tag) { _ in viewModel.scheduleAutoSave() }
                    .onChange(of: cell.language) { _ in viewModel.scheduleAutoSave() }
                }

                HStack(spacing: 16) {
                    Button(action: { viewModel.addCell(type: .code) }) {
                        HStack { Image(systemName: "chevron.left.forwardslash.chevron.right"); Text("Code") }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(controlBackground).cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    Button(action: { viewModel.addCell(type: .markdown) }) {
                        HStack { Image(systemName: "text.alignleft"); Text("Text") }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(controlBackground).cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    Button(action: { viewModel.addCell(type: .procedure) }) {
                        HStack { Image(systemName: "tablecells.fill"); Text("Procedure") }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(controlBackground).cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 20)
            }
            .padding()
        }
        .background(appState.appTheme == .transparent ? Color.clear : Color(nsColor: .textBackgroundColor).opacity(0.3))
    }
}

// MARK: - Notebook Cell View

struct NotebookCellView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var cell: NotebookCellModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onRun: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onGenerateCode: (String) -> Void
    
    @State private var isHovering = false
    @State private var showTagEditor = false
    @State private var tagDraft = ""
    @State private var codeHeight: CGFloat = 80
    
    private var panelBackground: Color {
        appState.appTheme == .transparent ? Color.white.opacity(0.05) : Color(nsColor: .windowBackgroundColor)
    }
    
    private var controlBackground: Color {
        appState.appTheme == .transparent ? Color.white.opacity(0.08) : Color(nsColor: .controlBackgroundColor)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left Gutter
            VStack(spacing: 4) {
                Text(executionLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 40)
                
                // Play Button
                Button(action: onRun) {
                    Image(systemName: cell.isExecuting ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(cell.isExecuting ? .red : .green)
                        .opacity(isHovering || isSelected || cell.isExecuting ? 1 : 0)
                }
                .buttonStyle(.plain)
                .disabled(cell.type != .code && cell.type != .agent && cell.type != .procedure)
            }
            .frame(width: 50)
            .padding(.top, 12)
            
            // Main Cell Content - All same background color
            VStack(alignment: .leading, spacing: 0) {
                // Cell Header
                cellHeader
                
                if !cell.isCollapsed {
                    if cell.type == .procedure {
                        SASProcedureView(cell: cell, onRun: onRun)
                    } else if cell.type == .markdown {
                        // Render Markdown
                        TextEditor(text: Binding(
                            get: { cell.content },
                            set: { cell.content = $0 }
                        ))
                        .font(.body)
                        .padding(8)
                    } else {
                        // Code Editor - height matches line count exactly
                        let lineCount = max(1, cell.content.components(separatedBy: "\n").count)
                        let lineHeight: CGFloat = 20  // line height for 13pt monospaced font
                        let calculatedHeight = CGFloat(lineCount) * lineHeight + 16  // +16 for padding
                        
                        // Use appTheme rawValue directly — ThemeManager.setActiveTheme resolves
                        // "system" to dark/light automatically based on macOS appearance.
                        SyntaxHighlightedCodeView(
                            text: Binding(
                                get: { cell.content },
                                set: { cell.content = $0 }
                            ),
                            language: cell.language.rawValue.lowercased(),
                            fontSize: appState.cellFontSize,
                            isDark: appState.appTheme.isDark,
                            themeName: appState.appTheme.rawValue,
                            fontName: appState.cellFontName,
                            fontWeight: appState.cellFontWeight,
                            editorID: "cell-\(cell.id.uuidString)"
                        )
                        .frame(height: max(50, min(calculatedHeight, 500)))
                        .cornerRadius(4)
                        .padding(4)

                    }
                    
                    // Output Section
                    if !cell.output.isEmpty || !cell.outputImages.isEmpty || cell.isDataFrame {
                        Divider()
                            .padding(.horizontal, 8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // DataFrame Output
                            if let dfPath = cell.dataFramePath, cell.isDataFrame {
                                DataFrameView(rawPath: dfPath, onGenerateCode: onGenerateCode)
                                    .frame(height: 300)
                            }
                            
                            // Text Output
                            if !cell.output.isEmpty {
                                ScrollView {
                                    Text(cell.output)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(cell.output.contains("Error") || cell.output.contains("Traceback") ? .red : .primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .frame(maxHeight: 200)
                            }
                            
                            // Image Output (matplotlib, PIL, etc.)
                            if !cell.outputImages.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(cell.outputImages, id: \.self) { imageURL in
                                            if imageURL.pathExtension.lowercased() == "pdf" {
                                                // PDF File
                                                Button(action: { NSWorkspace.shared.open(imageURL) }) {
                                                    VStack(spacing: 8) {
                                                        Image(systemName: "doc.text.fill")
                                                            .font(.largeTitle)
                                                            .foregroundColor(.red)
                                                        Text("Open PDF")
                                                            .font(.caption)
                                                            .foregroundColor(.primary)
                                                    }
                                                    .frame(width: 120, height: 120)
                                                    .background(appState.appTheme == .transparent ? Color.clear : Color(nsColor: .textBackgroundColor))
                                                    .cornerRadius(8)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            } else if imageURL.pathExtension.lowercased() == "html" {
                                                // HTML File
                                                Button(action: { NSWorkspace.shared.open(imageURL) }) {
                                                    VStack(spacing: 8) {
                                                        Image(systemName: "safari.fill")
                                                            .font(.largeTitle)
                                                            .foregroundColor(.blue)
                                                        Text("View Report")
                                                            .font(.caption)
                                                            .foregroundColor(.primary)
                                                    }
                                                    .frame(width: 120, height: 120)
                                                    .background(appState.appTheme == .transparent ? Color.clear : Color(nsColor: .textBackgroundColor))
                                                    .cornerRadius(8)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            } else if let nsImage = NSImage(contentsOf: imageURL) {
                                                VStack(spacing: 4) {
                                                    Image(nsImage: nsImage)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fit)
                                                        .frame(maxHeight: 300)
                                                        .cornerRadius(8)
                                                        .shadow(radius: 2)
                                                        .onTapGesture {
                                                            NSWorkspace.shared.open(imageURL)
                                                        }
                                                    
                                                    Text(imageURL.lastPathComponent)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                                .contextMenu {
                                                    Button("Save Image...") {
                                                        let panel = NSSavePanel()
                                                        panel.allowedContentTypes = [.png]
                                                        panel.nameFieldStringValue = imageURL.lastPathComponent
                                                        if panel.runModal() == .OK, let url = panel.url {
                                                            try? FileManager.default.copyItem(at: imageURL, to: url)
                                                        }
                                                    }
                                                    Button("Copy Image") {
                                                        NSPasteboard.general.clearContents()
                                                        NSPasteboard.general.writeObjects([nsImage])
                                                    }
                                                }
                                            }
                                        }
                                    }
                                        }
                                    }
                        }
                        .padding(8)
                    }
                }
            }
            .cornerRadius(6) 
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .background(cell.backgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : cell.borderColorValue.opacity(0.5), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
    
    private var cellHeader: some View {
        HStack {
            // Cell Type Badge
            Text(cell.type.rawValue)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(cellTypeColor.opacity(0.2))
                .foregroundColor(cellTypeColor)
                .cornerRadius(4)
            
            // Language Badge (for code cells)
            if cell.type == .code {
                Menu {
                    ForEach(CellLanguage.allCases) { lang in
                        Button {
                            cell.language = lang
                        } label: {
                            HStack {
                                Image(systemName: lang.icon)
                                    .foregroundColor(lang.color)
                                Text(lang.rawValue)
                                if cell.language == lang {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: cell.language.icon)
                            .font(.system(size: 10))
                        Text(cell.language.rawValue)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(cell.language.color.opacity(0.2))
                    .foregroundColor(cell.language.color)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            } else if cell.type == .agent {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                    Text("OS-Level Agent")
                        .font(.system(size: 9, weight: .medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.2))
                .foregroundColor(.purple)
                .cornerRadius(4)
            }
            
            // Name-tag (catalog) chip — used for "Run by Tag"
            Button {
                tagDraft = cell.tag
                showTagEditor = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "tag\(cell.tag.isEmpty ? "" : ".fill")")
                        .font(.system(size: 9))
                    Text(cell.tag.isEmpty ? "Tag" : cell.tag)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((cell.tag.isEmpty ? Color.secondary : Color.accentColor).opacity(0.18))
                .foregroundColor(cell.tag.isEmpty ? .secondary : .accentColor)
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Name this cell for selective Run by Tag")
            .popover(isPresented: $showTagEditor, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Cell Name-tag").font(.system(size: 12, weight: .semibold))
                    TextField("e.g. setup, train, report", text: $tagDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit {
                            cell.tag = tagDraft.trimmingCharacters(in: .whitespaces)
                            showTagEditor = false
                        }
                    HStack {
                        Button("Clear") { cell.tag = ""; tagDraft = ""; showTagEditor = false }
                        Spacer()
                        Button("Set") {
                            cell.tag = tagDraft.trimmingCharacters(in: .whitespaces)
                            showTagEditor = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(width: 220)
                }
                .padding(14)
            }

            // Enhanced Color Picker
            Menu {
                // Preset Colors in Grid-like sections
                Text("Preset Colors")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Row 1: Basics
                HStack {
                    ForEach([CellColorTheme.none, .gray, .blue, .green], id: \.self) { theme in
                        Button { 
                            cell.colorTheme = theme
                            cell.useCustomColor = false
                        } label: {
                            HStack {
                                Circle().fill(theme.iconColor).frame(width: 12, height: 12)
                                Text(theme.rawValue)
                                if cell.colorTheme == theme && !cell.useCustomColor {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                ForEach([CellColorTheme.purple, .orange, .pink, .yellow], id: \.self) { theme in
                    Button { 
                        cell.colorTheme = theme
                        cell.useCustomColor = false
                    } label: {
                        HStack {
                            Circle().fill(theme.iconColor).frame(width: 12, height: 12)
                            Text(theme.rawValue)
                            if cell.colorTheme == theme && !cell.useCustomColor {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                ForEach([CellColorTheme.red, .cyan, .teal, .indigo], id: \.self) { theme in
                    Button { 
                        cell.colorTheme = theme
                        cell.useCustomColor = false
                    } label: {
                        HStack {
                            Circle().fill(theme.iconColor).frame(width: 12, height: 12)
                            Text(theme.rawValue)
                            if cell.colorTheme == theme && !cell.useCustomColor {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                ForEach([CellColorTheme.mint, .brown], id: \.self) { theme in
                    Button { 
                        cell.colorTheme = theme
                        cell.useCustomColor = false
                    } label: {
                        HStack {
                            Circle().fill(theme.iconColor).frame(width: 12, height: 12)
                            Text(theme.rawValue)
                            if cell.colorTheme == theme && !cell.useCustomColor {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                Divider()
                
                // Custom Color Option
                Button {
                    cell.useCustomColor = true
                    if cell.customColor == nil {
                        cell.customColor = CustomCellColor()
                    }
                } label: {
                    HStack {
                        Image(systemName: "paintpalette")
                        Text("Custom Color...")
                        if cell.useCustomColor {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Circle()
                        .fill(cell.useCustomColor ? (cell.customColor?.borderColor ?? .gray) : cell.colorTheme.iconColor)
                        .frame(width: 10, height: 10)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(controlBackground)
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            
            // Custom Color Picker (shows when custom is selected)
            if cell.useCustomColor {
                ColorPicker("", selection: Binding(
                    get: { 
                        Color(red: cell.customColor?.red ?? 0.5, 
                              green: cell.customColor?.green ?? 0.5, 
                              blue: cell.customColor?.blue ?? 0.8)
                    },
                    set: { newColor in
                        if let components = newColor.cgColor?.components, components.count >= 3 {
                            cell.customColor = CustomCellColor(
                                red: components[0],
                                green: components[1],
                                blue: components[2],
                                opacity: 0.15
                            )
                        }
                    }
                ))
                .labelsHidden()
                .frame(width: 24, height: 24)
            }
            
            Spacer()
            
            if isHovering || isSelected {
                HStack(spacing: 8) {
                    Button(action: onMoveUp) {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onMoveDown) {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { cell.isCollapsed.toggle() }) {
                        Image(systemName: cell.isCollapsed ? "chevron.down" : "chevron.up")
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(cell.backgroundColor.opacity(0.5))
    }
    
    private var executionLabel: String {
        if cell.isExecuting { return "[*]" }
        if let count = cell.executionCount { return "[\(count)]" }
        return "[ ]"
    }
    
    private var cellTypeColor: Color {
        switch cell.type {
        case .code: return .blue
        case .markdown: return .green
        case .raw: return .gray
        case .procedure: return .orange
        case .agent: return .purple
        }
    }
}

// MARK: - HPC Settings View

struct HPCSettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var gpu = RemoteGPUService.shared
    @ObservedObject private var prov = RemoteProviderService.shared
    @AppStorage("remoteSSHCommand") private var sshCmd = ""
    @AppStorage("remoteSSHKey") private var sshKey = ""
    @AppStorage("runpodApiKey") private var runpodKey = ""
    @AppStorage("vastApiKey") private var vastKey = ""
    @AppStorage("cloudGPUBaseURL") private var cloudGPUBase = ""
    @State private var providerSel: RemoteProviderService.Provider = .runpod
    @State private var showProvider = false
    @State private var showAdvanced = false
    @State private var showGateway = false
    @State private var testing = false
    @State private var testOK: Bool? = nil
    @State private var testMsg = ""

    private var connected: Bool { gpu.status == .connected }
    private var connecting: Bool { gpu.status == .connecting }
    private var statusText: String {
        switch gpu.status {
        case .disconnected: return "Not connected"
        case .connecting:   return "Connecting…"
        case .connected:    return "Connected — cells run on the remote GPU"
        case .failed(let m): return m
        }
    }
    private var statusColor: Color {
        switch gpu.status {
        case .connected: return .green
        case .connecting: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.title2).foregroundColor(.blue)
                Text("Remote GPU — RunPod / Vast.ai")
                    .font(.headline)
            }

            Text("Paste the SSH command your provider gives you. MicroCode starts Jupyter, opens a secure tunnel and connects — no token, no URL to type.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("SSH COMMAND").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    TextField("ssh -p 41122 root@1.2.3.4 -i ~/.ssh/key", text: $sshCmd, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .disableAutocorrection(true)
                    Button {
                        if let s = NSPasteboard.general.string(forType: .string) {
                            sshCmd = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: { Image(systemName: "doc.on.clipboard") }
                    .buttonStyle(.borderless).help("Paste")
                }
            }

            // One-time key authorisation — no .pem juggling. MicroCode owns
            // its own key; the user just pastes our PUBLIC key into the
            // provider once.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("ONE-TIME SETUP").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(gpu.managedPublicKey, forType: .string)
                    } label: { Label("Copy MicroCode SSH key", systemImage: "key.fill") }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                Text("Paste this once into your provider: RunPod → Settings ▸ SSH Public Keys, or Vast → instance ▸ Manage SSH Keys. Then just Connect — no .pem to pick.")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(gpu.managedPublicKey.isEmpty ? "(generating key…)" :
                        String(gpu.managedPublicKey.prefix(46)) + "…")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary).lineLimit(1).textSelection(.enabled)

                DisclosureGroup("Use my own private key instead") {
                    HStack(spacing: 6) {
                        Text(sshKey.isEmpty ? "none" : (sshKey as NSString).lastPathComponent)
                            .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                        Spacer()
                        Button("Choose .pem…") {
                            let p = NSOpenPanel()
                            p.canChooseFiles = true; p.canChooseDirectories = false
                            p.allowsMultipleSelection = false
                            p.showsHiddenFiles = true
                            if p.runModal() == .OK, let u = p.url { sshKey = u.path }
                        }
                        .buttonStyle(.borderless).font(.system(size: 11))
                        if !sshKey.isEmpty {
                            Button { sshKey = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless).foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 10))
            }

            HStack(spacing: 10) {
                if connected {
                    Button(role: .destructive) { gpu.disconnect() } label: {
                        Label("Disconnect", systemImage: "stop.circle")
                    }
                } else {
                    Button {
                        gpu.connect(sshCommand: sshCmd, keyPath: sshKey.isEmpty ? nil : sshKey)
                    } label: {
                        HStack(spacing: 6) {
                            if connecting { ProgressView().scaleEffect(0.6) }
                            Image(systemName: "link")
                            Text(connecting ? "Connecting…" : "Connect")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(connecting || sshCmd.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText).font(.system(size: 11)).foregroundColor(statusColor)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }

            if !gpu.log.isEmpty {
                ScrollView {
                    Text(gpu.log)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 110)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.25)))
            }

            DisclosureGroup("Connect via provider API key (RunPod / Vast.ai)", isExpanded: $showProvider) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $providerSel) {
                        ForEach(RemoteProviderService.Provider.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()

                    SecureField(providerSel == .runpod ? "RunPod API key" : "Vast.ai API key",
                                text: providerSel == .runpod ? $runpodKey : $vastKey)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        Button {
                            Task {
                                await prov.listInstances(provider: providerSel,
                                                         apiKey: providerSel == .runpod ? runpodKey : vastKey)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if prov.isLoading { ProgressView().scaleEffect(0.6) }
                                Text(prov.isLoading ? "Loading…" : "List instances")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(prov.isLoading)
                        if !prov.error.isEmpty {
                            Text(prov.error).font(.system(size: 10)).foregroundColor(.red)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ForEach(prov.instances) { inst in
                        Button {
                            sshCmd = prov.sshCommand(for: inst)
                            let useKey = sshKey.isEmpty ? nil : sshKey
                            Task {
                                // Zero-setup: auto-register MicroCode's managed
                                // public key on the provider account using the
                                // same API key, so the SSH connect just works
                                // (no copy/paste). Best effort — connect anyway.
                                if useKey == nil {
                                    await prov.uploadKey(
                                        provider: providerSel,
                                        apiKey: providerSel == .runpod ? runpodKey : vastKey,
                                        publicKey: gpu.managedPublicKey)
                                }
                                gpu.connect(sshCommand: sshCmd, keyPath: useKey)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(inst.running ? Color.green : Color.secondary)
                                    .frame(width: 7, height: 7)
                                Text(inst.label).font(.system(size: 11)).lineLimit(1)
                                Spacer()
                                Image(systemName: "link").font(.system(size: 10))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!inst.running)
                    }

                    Text("Zero-setup: pick an instance → MicroCode auto-registers its key on your account via this API key, SSHes in, and connects. No SSH key or .pem to manage.")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            }
            .font(.system(size: 11))

            DisclosureGroup("Advanced — manual Jupyter URL/token", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("https://xxxx.trycloudflare.com", text: $appState.hpcEndpoint)
                        .textFieldStyle(.roundedBorder).disableAutocorrection(true)
                    SecureField("Jupyter token", text: $appState.hpcToken)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        Button {
                            Task { await testConnection() }
                        } label: {
                            HStack(spacing: 6) {
                                if testing { ProgressView().scaleEffect(0.6) }
                                Text(testing ? "Testing…" : "Test Connection")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(testing || appState.hpcEndpoint.trimmingCharacters(in: .whitespaces).isEmpty)
                        if let ok = testOK {
                            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundColor(ok ? .green : .red)
                        }
                    }
                    if !testMsg.isEmpty {
                        Text(testMsg).font(.system(size: 10, design: .monospaced))
                            .foregroundColor(testOK == true ? .green : .red)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
                .padding(.top, 6)
            }
            .font(.system(size: 11))

            DisclosureGroup("Managed Cloud GPU gateway (advanced)", isExpanded: $showGateway) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Endpoint MicroCode uses for one-click Cloud GPU. Leave blank to use the default.")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("https://gpu.dotmini.net/gpu/v1", text: $cloudGPUBase)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .autocorrectionDisabled(true)
                    HStack(spacing: 8) {
                        Text("Default: https://gpu.dotmini.net/gpu/v1")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        if !cloudGPUBase.isEmpty {
                            Button("Reset") { cloudGPUBase = "" }
                                .buttonStyle(.borderless).controlSize(.small)
                        }
                    }
                    Text("Authenticated with your MicroCode account token (same as AI). Billed from the separate Cloud GPU Wallet.")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            }
            .font(.system(size: 11))
        }
        .padding()
        .frame(width: 380)
    }

    private func testConnection() async {
        testing = true; testOK = nil; testMsg = ""
        defer { testing = false }
        var base = appState.hpcEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }
        // ws:// → http:// for the REST probe
        var probe = base
        if probe.hasPrefix("ws://") { probe = "http://" + probe.dropFirst(5) }
        if probe.hasPrefix("wss://") { probe = "https://" + probe.dropFirst(6) }
        guard let url = URL(string: "\(probe)/api/kernelspecs") else {
            testOK = false; testMsg = "Invalid URL"; return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        let tok = appState.hpcToken.trimmingCharacters(in: .whitespaces)
        if !tok.isEmpty { req.setValue("Token \(tok)", forHTTPHeaderField: "Authorization") }
        let t0 = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            guard let http = resp as? HTTPURLResponse else {
                testOK = false; testMsg = "No HTTP response"; return
            }
            if http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let specs = json["kernelspecs"] as? [String: Any] {
                testOK = true
                testMsg = "✅ Jupyter reachable (\(ms) ms)\nKernels: \(specs.keys.sorted().joined(separator: ", "))"
            } else if http.statusCode == 403 || http.statusCode == 401 {
                testOK = false; testMsg = "Reached server but token rejected (HTTP \(http.statusCode)). Check the token."
            } else {
                testOK = false; testMsg = "HTTP \(http.statusCode) — is this a Jupyter server URL?"
            }
        } catch {
            testOK = false
            testMsg = "Unreachable: \(error.localizedDescription)\nCheck the tunnel is running and the URL is public."
        }
    }
}
