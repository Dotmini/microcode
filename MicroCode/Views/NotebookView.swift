//
//  NotebookView.swift (Enhanced Multi-Notebook)
//  MicroCode
//
//  Enhanced with: Multi-notebook support, editable names, data file browser,
//  uniform cell colors, and auto-height code blocks
//
//  Created by Tirawat Nantamas
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers


// MARK: - Data File Model

struct DataFile: Identifiable {
    let id = UUID()
    var name: String
    var url: URL
    let type: DataFileType
    let size: Int64
    
    enum DataFileType: String {
        case csv = "CSV"
        case excel = "Excel"
        case json = "JSON"
        case sql = "SQL"
        case parquet = "Parquet"
        case structure = "Structure"
        case sequence = "Sequence"
        case image = "Figure"
        case document = "Paper"
        case latex = "LaTeX"
        case scientific = "Scientific"
        case unknown = "File"
        
        var icon: String {
            switch self {
            case .csv: return "tablecells"
            case .excel: return "tablecells.fill"
            case .json: return "curlybraces"
            case .sql: return "cylinder"
            case .parquet: return "doc.zipper"
            case .structure: return "atom"
            case .sequence: return "text.line.first.and.arrowtriangle.forward"
            case .image: return "photo"
            case .document: return "doc.richtext"
            case .latex: return "textformat"
            case .scientific: return "waveform.path.ecg"
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
            case .structure: return .cyan
            case .sequence: return .mint
            case .image: return .indigo
            case .document: return .red
            case .latex: return .orange
            case .scientific: return .teal
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
            case "pdb", "ent", "cif", "mmcif": return .structure
            case "fasta", "fa", "faa", "fna", "a3m": return .sequence
            case "png", "jpg", "jpeg", "gif", "webp", "svg", "tiff": return .image
            case "pdf": return .document
            case "tex", "bib": return .latex
            case "h5", "hdf5", "h5ad", "npy", "npz", "sdf", "mol", "mol2": return .scientific
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
    case ardium = "Ardium"
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
        case .ardium: return "sparkles"
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
        case .ardium: return .purple
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
        case .ardium:
            return """
            // ==========================================
            // Ardium Native High-Performance Module
            // ==========================================

            let version = "v2.3";
            let sum = 0;
            let i = 1;

            fn main() {
                println("=========================================");
                println("      HELLO FROM ARDIUM NOTEBOOK!        ");
                println("=========================================");
                
                print("Ardium Native Toolchain: ");
                println(version);
                
                while (i < 11) {
                    sum = sum + (i * i);
                    i = i + 1;
                }
                
                print("Sum of squares (1..10) = ");
                println(sum);
                println("=========================================");
            }
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
        case .python, .r, .julia, .sql, .ardium, .rust, .go, .cpp, .objc, .java, .csharp: return true
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
        case .ardium: return "ar"
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
        case "ardium", "ar": return .ardium
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
    @Published var computeTargetOverride: ComputeTarget? = nil // Per-cell heterogeneous compute target
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
    @Published private(set) var scientificProjectURL: URL?
    @Published var selectedPythonPath: String = PythonEnvManager.shared.systemPythonExecutable  // Can be set from UI
    /// The .mic file this notebook is bound to (Quick Save target). nil → not
    /// yet saved to a user-chosen file (autosave still protects the work).
    @Published var currentFileURL: URL?
    @Published var lastAutoSave: Date?
    private var autoSaveWork: DispatchWorkItem?

    private var dataDirectory: URL {
        (scientificProjectURL ?? workingDirectory).appendingPathComponent("data", isDirectory: true)
    }

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
    
    /// Export as Git-Friendly Plain-Text Python Script with # %% cell markers
    func exportPlainPythonScript() {
        guard let notebook = activeNotebook else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "py") ?? .plainText]
        let baseName = notebook.name.replacingOccurrences(of: ".mic", with: "").replacingOccurrences(of: ".ipynb", with: "")
        panel.nameFieldStringValue = baseName + ".py"
        panel.title = "Export as Plain-Text Python Script (# %%)"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let script = PythonScriptNotebookBridge.export(cells: notebook.cells)
            try? script.write(to: url, atomically: true, encoding: .utf8)
            print("✅ Exported plain-text Python script to \(url.lastPathComponent)")
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
            let notebook = NotebookModel(name: "Cell Sheet 1")
            notebooks = [notebook]
            activeNotebookId = notebook.id
            if let firstCell = notebook.cells.first {
                selectedCellId = firstCell.id
            }
        }
        print("📝 NotebookViewModel: Init complete with \(notebooks.count) cell sheet(s)")
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
        let notebook = NotebookModel(name: "Cell Sheet \(notebooks.count + 1)")
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
    
    func runCell(_ cell: NotebookCellModel, computeTarget: ComputeTarget? = nil) {
        guard cell.type == .code || cell.type == .procedure || cell.type == .agent else { return }

        let effectiveTarget: ComputeTarget = cell.computeTargetOverride ?? computeTarget ?? AppState.shared?.currentComputeTarget ?? .localCPU

        // Auto-detect 3rd-party imports so the env manager always reflects what
        // the code actually needs without the user typing anything.
        if cell.language == .python {
            _ = PythonEnvManager.shared.detectImportsFromCode(cell.content)
        }

        cell.isExecuting = true
        cell.clearOutput()
        kernelStatus = "Running"
        
        // If it's not a local execution, route to the Compute Kernel
        if effectiveTarget != .localCPU && effectiveTarget != .localMLX && effectiveTarget != .localNvidia {
            Task {
                do {
                    if effectiveTarget == .customHPC {
                        try await CloudGPUService.shared.ensureManagedSession()
                    }
                    if effectiveTarget == .googleColab {
                        if !GoogleColabService.shared.status.isConnected {
                            // Check if Colab session is already in clipboard before erroring out
                            if GoogleColabService.shared.checkAndConnectFromClipboardIfValid() {
                                for _ in 0..<8 {
                                    if GoogleColabService.shared.status.isConnected { break }
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                }
                            }
                        }
                    }
                    let kernel = ComputeKernelRouter.shared.getKernel(for: effectiveTarget)
                    try await kernel.start()
                    
                    let result = try await kernel.execute(code: cell.content, language: cell.language.rawValue) { chunk in
                        DispatchQueue.main.async {
                            cell.appendOutput(chunk)
                        }
                    }
                    
                    DispatchQueue.main.async {
                        let clean = result.trimmingCharacters(in: .whitespacesAndNewlines)
                        if cell.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            cell.output = clean.isEmpty ? "(Executed with no output)" : clean
                        }
                        cell.isExecuting = false
                        self.kernelStatus = "Idle"
                        cell.executionCount = (cell.executionCount ?? 0) + 1
                        self.totalExecutions += 1
                    }
                } catch {
                    DispatchQueue.main.async {
                        if effectiveTarget == .googleColab {
                            NotificationCenter.default.post(name: NSNotification.Name("MicroCodeOpenColabSheet"), object: nil)
                        }
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
        case .ardium:
            runArdiumCell(cell)
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
                cell.appendOutput("❌ Local execution for \(cell.language.rawValue) is not supported natively. Open MicroCode Cloud (cloud icon in toolbar) and Connect to a GPU.\n")
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
    
    private func runArdiumCell(_ cell: NotebookCellModel) {
        let cellID = cell.id
        let code = cell.content
        let workingDir = workingDirectory
        
        DispatchQueue.main.async {
            cell.isExecuting = true
            cell.output = ""
        }
        
        Task {
            var finalCode = code
            if !finalCode.contains("fn main(") && !finalCode.contains("func main(") {
                let trimmed = finalCode.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains("print") || trimmed.contains("println") || trimmed.contains("show()") {
                    finalCode = "fn main() {\n" + finalCode + "\n}"
                }
            }
            
            let res = await ArdiumRunner.execute(code: finalCode)
            var out = res.stdout
            if !res.stderr.isEmpty {
                out += (out.isEmpty ? "" : "\n") + res.stderr
            }
            if out.isEmpty && res.exitCode == 0 {
                out = "(Executed with no output)"
            }
            
            let cleanPattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
            let cleanOut = out.replacingOccurrences(of: cleanPattern, with: "", options: .regularExpression)
            
            await MainActor.run {
                self.handleCellOutput(cellID: cellID, result: cleanOut)
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
        // Honour the R interpreter explicitly selected in Manage Environments
        // before falling back to conventional Rscript locations.
        let rPaths = ["/opt/homebrew/bin/Rscript", "/usr/local/bin/Rscript", "/usr/bin/Rscript"]
        guard let rPath = RuntimeManager.shared.selectedExecutable(for: .r)
            ?? rPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
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
                let isRscript = URL(fileURLWithPath: rPath).lastPathComponent.lowercased().contains("rscript")
                process.arguments = isRscript
                    ? ["--vanilla", tempFile.path]
                    : ["--vanilla", "--slave", "-f", tempFile.path]
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
        // Honour the Julia executable selected in Manage Environments.
        let juliaPaths = [
            "/Applications/Julia-1.10.app/Contents/Resources/julia/bin/julia",
            "/Applications/Julia-1.9.app/Contents/Resources/julia/bin/julia",
            "/opt/homebrew/bin/julia",
            "/usr/local/bin/julia",
            "/usr/bin/julia"
        ]
        guard let juliaPath = RuntimeManager.shared.selectedExecutable(for: .julia)
            ?? juliaPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
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
        let lines = cell.content.components(separatedBy: "\n")
        var hasExplicitConnection = false
        var dbPath = workingDirectory.appendingPathComponent("notebook.db").path
        
        for line in lines {
            if line.lowercased().contains("connect to:") {
                hasExplicitConnection = true
                if let range = line.range(of: "sqlite:///") {
                    dbPath = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        let sqlStatements = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("--") }.joined(separator: "\n")
        let cellID = cell.id

        // If no explicit external database connection is requested, execute directly over
        // the Rosetta In-Memory DataFrames in POSIX Shared Memory
        if !hasExplicitConnection {
            let session = activeNotebookId?.uuidString ?? "default_notebook"
            Task {
                do {
                    let result = try await BackendService.shared.executeInMemorySQL(sessionId: session, query: sqlStatements)
                    if !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        DispatchQueue.main.async { [weak self] in
                            self?.handleCellOutput(cellID: cellID, result: result)
                        }
                        return
                    }
                } catch {
                    // Fall back to local SQLite execution below
                }
                
                executeLocalSqlite(dbPath: dbPath, sqlStatements: sqlStatements, cellID: cellID)
            }
            return
        }

        executeLocalSqlite(dbPath: dbPath, sqlStatements: sqlStatements, cellID: cellID)
    }

    private func executeLocalSqlite(dbPath: String, sqlStatements: String, cellID: UUID) {
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
        
        // When a Science project is open, imported data belongs to that
        // project's data directory so Science Mode, Cells and the Agent share
        // one durable source of truth. The notebook workspace is a fallback.
        let dataDir = dataDirectory
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let destURL = url.deletingLastPathComponent().standardizedFileURL == dataDir.standardizedFileURL
            ? url.standardizedFileURL
            : uniqueDataDestination(for: url.lastPathComponent, in: dataDir)

        if url.standardizedFileURL != destURL.standardizedFileURL {
            do {
                try FileManager.default.copyItem(at: url, to: destURL)
            } catch {
                print("Failed to copy data file: \(error)")
                return
            }
        }
        
        let attributes = try? FileManager.default.attributesOfItem(atPath: destURL.path)
        let size = (attributes?[.size] as? Int64) ?? 0
        let dataFile = DataFile(
            name: destURL.lastPathComponent,
            url: destURL,
            type: DataFile.DataFileType.from(extension: destURL.pathExtension),
            size: size
        )
        if let index = notebook.dataFiles.firstIndex(where: { $0.url.standardizedFileURL.path == destURL.standardizedFileURL.path }) {
            notebook.dataFiles[index] = dataFile
        } else {
            notebook.dataFiles.append(dataFile)
        }
        scheduleAutoSave()
        notifyScienceContextChanged()
    }

    func configureScientificProject(_ workspace: URL?) {
        let normalized = workspace?.standardizedFileURL
        guard scientificProjectURL?.path != normalized?.path else { return }
        scientificProjectURL = normalized
        guard let normalized else { return }
        try? FileManager.default.createDirectory(at: normalized.appendingPathComponent("data", isDirectory: true), withIntermediateDirectories: true)
    }

    func syncScientificFiles(from workspace: URL) {
        let expectedPath = workspace.standardizedFileURL.path
        Task {
            let context = await Task.detached(priority: .utility) {
                ScienceService.indexWorkspace(at: workspace)
            }.value
            guard let notebook = self.activeNotebook else { return }
            // A file can be renamed or deleted in Science Mode between syncs.
            // Remove only stale references inside this project; imported files
            // in other notebook workspaces must remain untouched.
            notebook.dataFiles.removeAll { file in
                file.url.standardizedFileURL.path.hasPrefix(expectedPath + "/") &&
                !FileManager.default.fileExists(atPath: file.url.path)
            }
            let paths = context.structures + context.sequences + context.results + context.papers + context.datasets
            for relative in paths.prefix(1_000) {
                let url = workspace.appendingPathComponent(relative).standardizedFileURL
                guard url.path.hasPrefix(expectedPath + "/"),
                      !notebook.dataFiles.contains(where: { $0.url.standardizedFileURL.path == url.path }) else { continue }
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                notebook.dataFiles.append(DataFile(name: url.lastPathComponent, url: url, type: DataFile.DataFileType.from(extension: url.pathExtension), size: (attributes?[.size] as? Int64) ?? 0))
            }
            self.scheduleAutoSave()
            self.notifyScienceContextChanged()
        }
    }

    func createDataFile() {
        guard let notebook = activeNotebook else { return }
        let dataDir = dataDirectory
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        var index = 1
        var url = dataDir.appendingPathComponent("dataset.csv")
        while FileManager.default.fileExists(atPath: url.path) {
            index += 1
            url = dataDir.appendingPathComponent("dataset_\(index).csv")
        }
        do {
            try "column,value\n".write(to: url, atomically: true, encoding: .utf8)
            notebook.dataFiles.append(DataFile(name: url.lastPathComponent, url: url, type: .csv, size: 13))
            scheduleAutoSave()
            notifyScienceContextChanged()
        } catch { print("Failed to create data file: \(error)") }
    }

    func renameDataFile(_ file: DataFile, to proposedName: String) {
        guard let notebook = activeNotebook,
              let index = notebook.dataFiles.firstIndex(where: { $0.id == file.id }) else { return }
        let safeName = URL(fileURLWithPath: proposedName).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeName.isEmpty, safeName != ".", safeName != ".." else { return }
        let destination = file.url.deletingLastPathComponent().appendingPathComponent(safeName)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        do {
            try FileManager.default.moveItem(at: file.url, to: destination)
            notebook.dataFiles[index].name = destination.lastPathComponent
            notebook.dataFiles[index].url = destination
            scheduleAutoSave()
            notifyScienceContextChanged()
        } catch { print("Failed to rename data file: \(error)") }
    }
    
    func removeDataFile(_ file: DataFile) {
        guard let notebook = activeNotebook else { return }
        notebook.dataFiles.removeAll { $0.id == file.id }
        SharedMemoryService.shared.removeArtifact(file.url)
        scheduleAutoSave()
        notifyScienceContextChanged()
    }

    func deleteDataFile(_ file: DataFile) {
        do {
            if FileManager.default.fileExists(atPath: file.url.path) {
                try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
            }
            removeDataFile(file)
            notifyScienceContextChanged()
        } catch { print("Failed to move data file to Trash: \(error)") }
    }

    func insertLoaderCell(for file: DataFile) {
        let path = file.url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let code: String
        switch file.type {
        case .structure:
            code = """
            from pathlib import Path
            structure_path = Path(r"\(path)")
            print(f"Structure: {structure_path.name}")
            try:
                from Bio.PDB import PDBParser, MMCIFParser
            except ImportError:
                print("Biopython is not installed. Run: pip install biopython")
            else:
                parser = MMCIFParser(QUIET=True) if structure_path.suffix.lower() in {".cif", ".mmcif"} else PDBParser(QUIET=True)
                structure = parser.get_structure(structure_path.stem, structure_path)
                print("Models:", len(list(structure.get_models())))
                print("Chains:", [chain.id for chain in structure.get_chains()])
            """
        case .sequence:
            code = """
            from pathlib import Path
            fasta_path = Path(r"\(path)")
            try:
                from Bio import SeqIO
            except ImportError:
                print("Biopython is not installed. Run: pip install biopython")
            else:
                records = list(SeqIO.parse(fasta_path, "fasta"))
                print(f"{len(records)} sequences", [len(r.seq) for r in records[:20]])
            """
        case .csv:
            code = "import pandas as pd\ndata = pd.read_csv(r\"\(path)\")\ndisplay(data.head())"
        case .parquet:
            code = "import pandas as pd\ndata = pd.read_parquet(r\"\(path)\")\ndisplay(data.head())"
        case .json:
            code = "import json\nwith open(r\"\(path)\") as f:\n    data = json.load(f)\nprint(type(data), data if isinstance(data, dict) else f\"{len(data)} records\")"
        default:
            code = "from pathlib import Path\nartifact = Path(r\"\(path)\")\nprint(artifact, artifact.stat().st_size, \"bytes\")"
        }
        addCell(type: .code, language: .python)
        if let cell = activeNotebook?.cells.first(where: { $0.id == selectedCellId }) { cell.content = code }
        scheduleAutoSave()
    }

    private func uniqueDataDestination(for originalName: String, in directory: URL) -> URL {
        let cleanName = URL(fileURLWithPath: originalName).lastPathComponent
        let stem = (cleanName as NSString).deletingPathExtension
        let ext = (cleanName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(cleanName)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            candidate = directory.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }

    private func notifyScienceContextChanged() {
        guard scientificProjectURL != nil else { return }
        AgentService.shared.refreshScienceProjectContext()
    }
    
    func saveNotebook() {
        guard let notebook = activeNotebook else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "mic") ?? .data,
            UTType(filenameExtension: "mcnb") ?? .json,
            UTType(filenameExtension: "ipynb") ?? .json,
            UTType(filenameExtension: "py") ?? .plainText,
            .json,
            .plainText
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
            "data_files": notebook.dataFiles.map { ["name": $0.name, "path": $0.url.path, "type": $0.type.rawValue, "size": $0.size] as [String: Any] },
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
        if url.pathExtension.lowercased() == "mic" {
            loadFromMic(url: url)
            return
        }
        if url.pathExtension.lowercased() == "py" {
            if let script = try? String(contentsOf: url, encoding: .utf8) {
                let cells = PythonScriptNotebookBridge.parse(script: script)
                let notebook = NotebookModel(name: url.lastPathComponent)
                notebook.cells = cells
                notebooks.append(notebook)
                activeNotebookId = notebook.id
                print("✅ Loaded plain Python script (# %%) as Notebook: \(url.lastPathComponent)")
            }
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
        restoreDataFiles(from: dict["data_files"], into: notebook)
        
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
                "data_files": notebook.dataFiles.map { ["name": $0.name, "path": $0.url.path, "type": $0.type.rawValue, "size": $0.size] as [String: Any] },
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
            restoreDataFiles(from: nbDict["data_files"], into: notebook)
            
            notebooks.append(notebook)
        }
        
        let activeIdStr = dict["active_id"] as? String ?? ""
        activeNotebookId = notebooks.first(where: { $0.id.uuidString == activeIdStr })?.id ?? notebooks.first?.id
        selectedCellId = activeNotebook?.cells.first?.id
        
        print("✅ Restored \(notebooks.count) notebook(s) from auto-save")
    }

    private func restoreDataFiles(from value: Any?, into notebook: NotebookModel) {
        guard let rows = value as? [[String: Any]] else { return }
        for row in rows {
            guard let path = row["path"] as? String else { continue }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            notebook.dataFiles.append(DataFile(
                name: row["name"] as? String ?? url.lastPathComponent,
                url: url,
                type: DataFile.DataFileType.from(extension: url.pathExtension),
                size: (row["size"] as? NSNumber)?.int64Value ?? 0
            ))
        }
    }
}

// MARK: - Main Notebook View

struct NotebookView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = NotebookViewModel()
    @ObservedObject private var pythonEnvManager = PythonEnvManager.shared
    @ObservedObject private var cloudGPU = CloudGPUService.shared
    @ObservedObject private var sharedMemory = SharedMemoryService.shared
    @ObservedObject private var colabService = GoogleColabService.shared
    @State private var isReady = false
    @State private var showAIPanel = false
    @State private var showingHPCSettings = false
    @State private var showingColabSettings = false
    @State private var showingExportPopover = false
    private let notebookHeaderHeight: CGFloat = 28
    
    private var panelBackground: Color {
        appState.appTheme.isGlass ? Color.white.opacity(0.05) : Color(nsColor: appState.appTheme.panelBackground)
    }
    
    private var controlBackground: Color {
        appState.appTheme.isGlass ? Color.white.opacity(0.08) : Color(nsColor: appState.appTheme.elevatedBackground)
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
            if let workspace = appState.workspaceFolder {
                viewModel.configureScientificProject(workspace)
                viewModel.syncScientificFiles(from: workspace)
            }
            Task {
                await SharedMemoryService.shared.refreshList()
            }
            
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
            
            // Check if notebook URL was requested from Editor ipynb convert
            if let notebookURL = appState.pendingNotebookURL {
                viewModel.loadNotebook(from: notebookURL)
                appState.pendingNotebookURL = nil
                print("🚀 NotebookView: Loaded notebook from pendingNotebookURL: \(notebookURL.path)")
            }
        }
        .onReceive(appState.$pendingNotebookURL) { url in
            if let url = url {
                viewModel.loadNotebook(from: url)
                appState.pendingNotebookURL = nil
                print("🚀 NotebookView: Received notebook from pendingNotebookURL: \(url.path)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ImportNotebookFile"))) { notification in
            if let info = notification.userInfo,
               let path = info["path"] as? String {
                let url = URL(fileURLWithPath: path)
                viewModel.loadNotebook(from: url)
                print("🚀 NotebookView: Imported ipynb from Editor convert: \(path)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ImportScriptToNotebook"))) { notification in
            if let info = notification.userInfo,
               let code = info["code"] as? String,
               let ext = info["extension"] as? String {
                // Map extension to notebook language
                let langMap: [String: CellLanguage] = [
                    "py": .python, "r": .r, "jl": .julia, "sql": .sql,
                    "go": .go, "rs": .rust, "cpp": .cpp, "c": .cpp,
                    "swift": .python, "rb": .python, "js": .python, "ts": .python
                ]
                let lang = langMap[ext] ?? .python
                let filename = info["filename"] as? String ?? "Imported"
                
                // Create a new notebook with the script as a cell
                let notebook = NotebookModel(name: filename)
                let cell = NotebookCellModel(type: .code, language: lang)
                cell.content = code
                notebook.cells = [cell]
                viewModel.notebooks.append(notebook)
                viewModel.activeNotebookId = notebook.id
                print("🚀 NotebookView: Created notebook from \(ext) script: \(filename)")
            }
        }
        .onChange(of: appState.workspaceFolder?.path) { _ in
            viewModel.configureScientificProject(appState.workspaceFolder)
            if let workspace = appState.workspaceFolder {
                viewModel.syncScientificFiles(from: workspace)
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

    private func insertSharedArtifactCell(_ url: URL) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let file = DataFile(name: url.lastPathComponent, url: url, type: DataFile.DataFileType.from(extension: url.pathExtension), size: (attributes?[.size] as? Int64) ?? 0)
        viewModel.insertLoaderCell(for: file)
    }

    private func insertSharedDataFrameCell(_ name: String) {
        viewModel.addCell(type: .code, language: .python)
        if let cell = viewModel.activeNotebook?.cells.first(where: { $0.id == viewModel.selectedCellId }) {
            cell.content = """
            # Load shared dataframe from MicroCode SHM
            \(SharedMemoryService.shared.getPythonBridgeCode())
            data = shm.get("\(name)")
            display(data.head())
            """
            viewModel.scheduleAutoSave()
        }
    }
    
    // MARK: - Sidebar
    
    private var notebookSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.orange)
                Text("Cell Sheets")
                    .font(.headline)
                Spacer()
                
                Button(action: { viewModel.createNotebook() }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: notebookHeaderHeight)
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
                            
                            // Python Env Selector - Dual Cloud & Local Support
                            if appState.currentComputeTarget == .yourCloud {
                                VStack(alignment: .leading, spacing: 8) {
                                    // 1. Cloud Target Environment
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text("CLOUD COMPUTE")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text("Default")
                                                .font(.system(size: 8, weight: .medium))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.green.opacity(0.15))
                                                .foregroundColor(.green)
                                                .cornerRadius(3)
                                        }

                                        Menu {
                                            Button(action: {}) {
                                                Label("Cloud Auto-ENV (~/.microcode/venv)", systemImage: "checkmark")
                                            }
                                            Divider()
                                            let detected = pythonEnvManager.detectedPackages
                                            if !detected.isEmpty {
                                                Button("Auto-Install \(detected.count) Detected Packages on Cloud") {
                                                    Task {
                                                        let kernel = ComputeKernelRouter.shared.getKernel(for: .yourCloud)
                                                        let installCmd = "pip install -q " + detected.joined(separator: " ")
                                                        _ = try? await kernel.execute(code: installCmd, language: "bash") { _ in }
                                                    }
                                                }
                                            }
                                            Button("Manage Environments...") {
                                                let allCode = (viewModel.activeNotebook?.cells ?? [])
                                                    .filter { $0.type == .code }
                                                    .map { $0.content }
                                                    .joined(separator: "\n")
                                                _ = pythonEnvManager.detectImportsFromCode(allCode)
                                                appState.showingPythonEnv = true
                                            }
                                        } label: {
                                            HStack {
                                                Image(systemName: "cloud.fill")
                                                    .foregroundColor(.green)
                                                Text("Cloud: Auto venv")
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
                                    }

                                    // 2. Local Mac / Apple Silicon Environment (for Cells with Local / MLX override)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text("LOCAL / APPLE SILICON")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text("MLX / Metal")
                                                .font(.system(size: 8, weight: .bold))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.accentColor.opacity(0.15))
                                                .foregroundColor(.accentColor)
                                                .cornerRadius(3)
                                        }

                                        Menu {
                                            Button("System Python") {
                                                pythonEnvManager.activeEnvironment = nil
                                                viewModel.selectedPythonPath = pythonEnvManager.systemPythonExecutable
                                            }
                                            Divider()
                                            ForEach(pythonEnvManager.environments) { env in
                                                Button(env.name) {
                                                    pythonEnvManager.activateEnvironment(env)
                                                    viewModel.selectedPythonPath = env.pythonPath
                                                }
                                            }
                                            Divider()
                                            Button("Manage Local Environments...") {
                                                let allCode = (viewModel.activeNotebook?.cells ?? [])
                                                    .filter { $0.type == .code }
                                                    .map { $0.content }
                                                    .joined(separator: "\n")
                                                _ = pythonEnvManager.detectImportsFromCode(allCode)
                                                appState.showingPythonEnv = true
                                            }
                                        } label: {
                                            HStack {
                                                Image(systemName: "cpu.fill")
                                                    .foregroundColor(.accentColor)
                                                Text(pythonEnvManager.activeEnvironment?.name ?? "System Python")
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
                                    }
                                }
                            } else if isReady {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("LOCAL / APPLE SILICON")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("Default")
                                            .font(.system(size: 8, weight: .medium))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.15))
                                            .foregroundColor(.accentColor)
                                            .cornerRadius(3)
                                    }

                                    Menu {
                                        Button("System Python") {
                                            pythonEnvManager.activeEnvironment = nil
                                            viewModel.selectedPythonPath = pythonEnvManager.systemPythonExecutable
                                        }
                                        Divider()
                                        ForEach(pythonEnvManager.environments) { env in
                                            Button(env.name) {
                                                pythonEnvManager.activateEnvironment(env)
                                                viewModel.selectedPythonPath = env.pythonPath
                                            }
                                        }
                                        Divider()
                                        Button("Manage Environments...") {
                                            let allCode = (viewModel.activeNotebook?.cells ?? [])
                                                .filter { $0.type == .code }
                                                .map { $0.content }
                                                .joined(separator: "\n")
                                            _ = pythonEnvManager.detectImportsFromCode(allCode)
                                            appState.showingPythonEnv = true
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: "cpu.fill")
                                                .foregroundColor(.green)
                                            Text(pythonEnvManager.activeEnvironment?.name ?? "System Python")
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
                                }
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
                                if let workspace = appState.workspaceFolder {
                                    Button(action: { viewModel.syncScientificFiles(from: workspace) }) {
                                        Image(systemName: "arrow.triangle.2.circlepath").font(.caption)
                                    }
                                    .buttonStyle(.plain).help("Sync scientific artifacts from project")
                                }
                                Menu {
                                    Button("Import Files…") { viewModel.showingDataFilePicker = true }
                                    Button("New CSV File") { viewModel.createDataFile() }
                                } label: {
                                    Image(systemName: "plus.circle").font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if let notebook = viewModel.activeNotebook, !notebook.dataFiles.isEmpty {
                                let displayedFiles = Array(notebook.dataFiles.prefix(5))
                                let remainingFiles = Array(notebook.dataFiles.dropFirst(5))
                                
                                ForEach(displayedFiles) { file in
                                    DataFileRow(
                                        file: file,
                                        onInsertCell: { viewModel.insertLoaderCell(for: file) },
                                        onPreviewScience: {
                                            Task {
                                                await appState.loadFile(url: file.url)
                                                appState.setEditorMode(.science)
                                            }
                                        },
                                        onShare: { SharedMemoryService.shared.shareArtifact(file.url) },
                                        onRename: { viewModel.renameDataFile(file, to: $0) },
                                        onRemove: { viewModel.removeDataFile(file) },
                                        onDelete: { viewModel.deleteDataFile(file) }
                                    )
                                }
                                
                                if !remainingFiles.isEmpty {
                                    Menu {
                                        ForEach(remainingFiles) { file in
                                            Menu {
                                                Button {
                                                    viewModel.insertLoaderCell(for: file)
                                                } label: {
                                                    Label("Insert Loader Cell", systemImage: "arrow.down.to.line")
                                                }
                                                Button {
                                                    Task {
                                                        await appState.loadFile(url: file.url)
                                                        appState.setEditorMode(.science)
                                                    }
                                                } label: {
                                                    Label("Preview in Science Mode", systemImage: "waveform.path.ecg")
                                                }
                                                Button {
                                                    SharedMemoryService.shared.shareArtifact(file.url)
                                                } label: {
                                                    Label("Share to Shared Memory", systemImage: "memorychip")
                                                }
                                                Divider()
                                                Button(role: .destructive) {
                                                    viewModel.removeDataFile(file)
                                                } label: {
                                                    Label("Remove from List", systemImage: "trash")
                                                }
                                            } label: {
                                                Label("\(file.name) (\(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)))", systemImage: file.type.icon)
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "folder.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                            Text("More Files (+\(remainingFiles.count))...")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(appState.appTheme.isGlass ? Color.white.opacity(0.06) : Color(nsColor: appState.appTheme.elevatedBackground))
                                        .cornerRadius(5)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Access remaining data files in this notebook")
                                    .padding(.top, 2)
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
                                Text("Shared Data")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: { Task { await SharedMemoryService.shared.refreshList() } }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if !sharedMemory.sharedDataFrames.isEmpty {
                                ForEach(sharedMemory.sharedDataFrames, id: \.self) { name in
                                    HStack {
                                        Image(systemName: "memorychip")
                                            .foregroundColor(.blue)
                                        Text(name)
                                            .font(.system(size: 11))
                                        Spacer()
                                        Button(action: {
                                            insertSharedDataFrameCell(name)
                                        }) {
                                            Image(systemName: "arrow.down.to.line")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Insert into cell")
                                    }
                                }
                            } else {
                                if sharedMemory.sharedArtifacts.isEmpty {
                                    Text("No shared data")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 8)
                                }
                            }

                            ForEach(sharedMemory.sharedArtifacts, id: \.path) { url in
                                HStack(spacing: 7) {
                                    Image(systemName: DataFile.DataFileType.from(extension: url.pathExtension).icon)
                                        .foregroundColor(DataFile.DataFileType.from(extension: url.pathExtension).color)
                                    Text(url.lastPathComponent).font(.system(size: 10)).lineLimit(1)
                                    Spacer()
                                    Button { insertSharedArtifactCell(url) } label: {
                                        Image(systemName: "arrow.down.to.line").font(.caption2)
                                    }.buttonStyle(.plain).help("Insert into cell")
                                    Button { SharedMemoryService.shared.removeArtifact(url) } label: {
                                        Image(systemName: "xmark").font(.caption2)
                                    }.buttonStyle(.plain)
                                }
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
        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))
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
            
            Divider().frame(height: 14)
            
            // Python version
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
                
                Button { viewModel.addCell(type: .code, language: .ardium) } label: {
                    Label("Ardium", systemImage: "sparkles")
                }
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
            
            // Run Selected
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
            
            Spacer()
            
            // --- Right side: compute, open, export, count, AI ---
            
            // Compute Engine Selector
            Menu {
                Text("Compute Engine")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(ComputeTarget.userSelectable) { target in
                    Button {
                        appState.currentComputeTarget = target
                    } label: {
                        HStack {
                            Text(target.displayName)
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
                        .foregroundColor(appState.currentComputeTarget == .yourCloud ? .green : (appState.currentComputeTarget.isPremium ? .orange : .secondary))
                    if appState.currentComputeTarget == .yourCloud {
                        Text("Your Cloud")
                            .font(.system(size: 11, weight: .medium))
                    } else if appState.currentComputeTarget == .googleColab {
                        Text("Google Colab")
                            .font(.system(size: 11, weight: .medium))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .font(.system(size: 11))
            }
            .menuIndicator(.hidden)
            .help("Select Compute Engine: \(appState.currentComputeTarget.displayName)")
            
            // Google Colab Cloud GPU Status & Settings
            if appState.currentComputeTarget == .googleColab {
                Button(action: { showingColabSettings = true }) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(colabService.status.statusColor)
                            .frame(width: 6, height: 6)
                        
                        Text(colabService.status.isConnected ? colabService.detectedGPU : "Colab Runtime")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(colabService.status.isConnected ? .green : .primary)
                        
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Google Colab Cloud Compute & Runtime Bridge Settings")
                .popover(isPresented: $showingColabSettings, arrowEdge: .bottom) {
                    GoogleColabSheetView()
                        .environmentObject(appState)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeOpenColabSheet"))) { _ in
                    showingColabSettings = true
                }
            }
            
            // Your Cloud SSH Server Selector (Auto-synced with Remote Explorer)
            if appState.currentComputeTarget == .yourCloud {
                Menu {
                    Text("Synced SSH Servers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    let servers = RemoteConnectionManager.shared.servers
                    if servers.isEmpty {
                        Text("No SSH servers configured")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(servers) { s in
                            Button {
                                appState.selectedSSHComputeServer = s
                                RemoteConnectionManager.shared.currentConnection = s
                            } label: {
                                HStack {
                                    Text("\(s.name) (\(s.username)@\(s.host))")
                                    let isSel = (appState.selectedSSHComputeServer?.id ?? RemoteConnectionManager.shared.currentConnection?.id ?? servers.first?.id) == s.id
                                    if isSel {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    let activeServer = appState.selectedSSHComputeServer ?? RemoteConnectionManager.shared.currentConnection ?? RemoteConnectionManager.shared.servers.first
                    HStack(spacing: 4) {
                        Circle()
                            .fill(activeServer != nil ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(activeServer?.name ?? "Auto SSH")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
                .menuIndicator(.hidden)
                .help("Active SSH Compute Server (Auto-synced with Remote Explorer)")
                
                // Auto-ENV Indicator
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                    Text("Auto ENV")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .cornerRadius(4)
                .help("Remote Python Environment: Auto venv (~/.microcode/venv) with on-demand package installation")
            }
            
            if appState.currentComputeTarget == .customHPC {
                Button(action: { showingHPCSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("MicroCode Cloud — advanced settings")
                .popover(isPresented: $showingHPCSettings, arrowEdge: .bottom) {
                    HPCSettingsView()
                        .environmentObject(appState)
                }
            }
            
            // GPU Wallet — deliberately separate from AI-token balance.
            if appState.currentComputeTarget.isPremium {
                HStack(spacing: 2) {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.yellow)
                    Text(cloudGPU.balanceText)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(4)
                .help("Cloud GPU Wallet: \(cloudGPU.balanceText). This is separate from AI tokens.")
                
                Divider().frame(height: 14)
            }
            
            // Open
            Button(action: { openNotebookFile() }) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
            }
            .help("Open Notebook")
            
            // Export is a persistent popover: one click opens it and it stays
            // available until the user explicitly closes it.
            Button(action: { showingExportPopover = true }) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingExportPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Export Notebook").font(.headline)
                            Text("Save .mic or export a Jupyter .ipynb copy")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button { showingExportPopover = false } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Close")
                    }
                    Divider()
                    Button(action: { viewModel.quickSave() }) {
                        Label("Quick Save (.mic)", systemImage: "bolt.fill")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    Button(action: { viewModel.saveAs() }) {
                        Label("Save As… (.mic)", systemImage: "square.and.arrow.down")
                    }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    Button(action: { viewModel.exportIpynb() }) {
                        Label("Export as Jupyter (.ipynb)", systemImage: "arrow.up.forward.square")
                    }
                    Button(action: { viewModel.exportPlainPythonScript() }) {
                        Label("Export as Git-Clean Script (.py # %%)", systemImage: "doc.text.fill")
                    }
                    Button(action: {
                        if let nb = viewModel.activeNotebook {
                            colabService.openColabInBrowser(notebook: nb)
                        }
                    }) {
                        Label("Open in Google Colab", systemImage: "sparkles.rectangle.stack")
                    }
                    Divider()
                    Text(viewModel.lastAutoSave.map { "Autosaved \($0.formatted(date: .omitted, time: .standard))" } ?? "Autosave on")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(14)
                .frame(width: 300)
            }
            .help("Export Notebook (.mic / .ipynb)")
            
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
        .frame(height: notebookHeaderHeight)
        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))
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
                    viewModel.selectedPythonPath = PythonEnvManager.shared.systemPythonExecutable
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
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 190, minHeight: 28, maxHeight: 28)
            .contentShape(Rectangle())
            .background(controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
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
    let onInsertCell: () -> Void
    let onPreviewScience: () -> Void
    let onShare: () -> Void
    let onRename: (String) -> Void
    let onRemove: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var confirmsDelete = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file.type.icon)
                .foregroundColor(file.type.color)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 1) {
                if isRenaming {
                    TextField("File name", text: $draftName)
                        .textFieldStyle(.plain).font(.system(size: 11))
                        .onSubmit { onRename(draftName); isRenaming = false }
                } else {
                    Text(file.name).font(.system(size: 11)).lineLimit(1)
                }
                
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
                Button(action: onInsertCell) { Image(systemName: "arrow.down.to.line").font(.caption).foregroundColor(.secondary) }
                    .buttonStyle(.plain).help("Insert loader cell")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onInsertCell)
        .contextMenu {
            Button("Insert Loader Cell", action: onInsertCell)
            Button("Preview in Science Mode", action: onPreviewScience)
            Button("Share Data", action: onShare)
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.url.path, forType: .string)
            }
            Button("Rename…") {
                draftName = file.name
                isRenaming = true
            }
            Divider()
            Button("Remove Reference", action: onRemove)
            Button("Move File to Trash", role: .destructive) { confirmsDelete = true }
        }
        .alert("Move \(file.name) to Trash?", isPresented: $confirmsDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive, action: onDelete)
        } message: {
            Text("The file will be moved to the macOS Trash and removed from this notebook.")
        }
    }
}

// MARK: - Notebook Cells List (observes NotebookModel for realtime add/delete)

struct NotebookCellsList: View {
    @ObservedObject var notebook: NotebookModel
    @ObservedObject var viewModel: NotebookViewModel
    @EnvironmentObject var appState: AppState

    private var controlBackground: Color {
        appState.appTheme.isGlass ? Color.white.opacity(0.08) : Color(nsColor: appState.appTheme.elevatedBackground)
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
        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.workspaceBackground))
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
        appState.appTheme.isGlass ? Color.white.opacity(0.05) : Color(nsColor: appState.appTheme.panelBackground)
    }
    
    private var controlBackground: Color {
        appState.appTheme.isGlass ? Color.white.opacity(0.08) : Color(nsColor: appState.appTheme.elevatedBackground)
    }
    
    private var cellCardBackground: some View {
        ZStack {
            if appState.appTheme.isGlass {
                if cell.useCustomColor, let custom = cell.customColor {
                    custom.color
                } else if cell.colorTheme != .none {
                    cell.colorTheme.color
                } else {
                    Color.white.opacity(0.05)
                }
            } else {
                // Solid theme (e.g. Near Black #090A0C / elevated #131416)
                Color(nsColor: appState.appTheme.elevatedBackground)
                if cell.useCustomColor, let custom = cell.customColor {
                    custom.color
                } else if cell.colorTheme != .none {
                    cell.colorTheme.color
                }
            }
        }
    }
    
    private var cellBorderColor: Color {
        if cell.useCustomColor, let custom = cell.customColor {
            return custom.borderColor
        }
        if cell.colorTheme != .none {
            return cell.colorTheme.borderColor
        }
        return appState.appTheme.isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.1)
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
                        // Zero-allocation UTF8 scan instead of components(separatedBy:)
                        let lineCount = max(1, cell.content.utf8.reduce(1) { $0 + ($1 == 0x0A ? 1 : 0) })
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
                            isTransparent: true,
                            showLineNumbers: appState.showLineNumbers,
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
                                let hasError = cell.output.contains("Error") || cell.output.contains("Traceback") || cell.output.contains("Exception") || cell.output.contains("CUDA out of memory")
                                if hasError {
                                    CellSelfHealingBanner(cell: cell, onRun: onRun)
                                }
                                
                                ScrollView {
                                    Text(cell.output)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(hasError ? .red : .primary)
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
                                                    .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))
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
                                                    .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))
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
        .background(cellCardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : cellBorderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: appState.appTheme.isGlass ? Color.black.opacity(0.05) : Color.clear, radius: 4, x: 0, y: 2)
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
                
                // Per-Cell Heterogeneous Compute Target Chip
                Menu {
                    Button {
                        cell.computeTargetOverride = nil
                    } label: {
                        HStack {
                            Text("Default (\(appState.currentComputeTarget.displayName))")
                            if cell.computeTargetOverride == nil { Image(systemName: "checkmark") }
                        }
                    }
                    Divider()
                    ForEach(ComputeTarget.userSelectable, id: \.self) { t in
                        Button {
                            cell.computeTargetOverride = t
                        } label: {
                            HStack {
                                Image(systemName: t.icon)
                                Text(t.displayName)
                                if cell.computeTargetOverride == t { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    let current = cell.computeTargetOverride ?? appState.currentComputeTarget
                    HStack(spacing: 3) {
                        Image(systemName: cell.computeTargetOverride != nil ? current.icon : "arrow.triangle.branch")
                            .font(.system(size: 8))
                        Text(cell.computeTargetOverride != nil ? current.displayName : "Default")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(cell.computeTargetOverride != nil ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    .foregroundColor(cell.computeTargetOverride != nil ? .accentColor : .secondary)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Per-Cell Compute Engine (Overrides default target for this cell)")
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

// MARK: - Cell Self-Healing Banner

struct CellSelfHealingBanner: View {
    @ObservedObject var cell: NotebookCellModel
    let onRun: () -> Void
    
    @State private var isFixing = false
    @State private var fixStatus = ""
    @State private var showCopied = false
    
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("Cell Error")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            if isFixing {
                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text(fixStatus)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Colab One-Click Resolvers
            if cell.output.contains("Colab") || cell.output.contains("Google Colab") {
                Button {
                    cell.computeTargetOverride = .localCPU
                    onRun()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 9))
                        Text("Run on Local Mac")
                    }
                    .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Execute this cell immediately on your local Mac processor")
                
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("MicroCodeOpenColabSheet"), object: nil)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                        Text("Connect Colab")
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // 1. AI Agent Auto-Fix Button (Monochrome / Theme-matching)
            Button {
                triggerAgentAutoFix()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.badge.automatic.fill")
                        .font(.system(size: 10))
                    Text("Agent Auto-Fix")
                }
                .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .disabled(isFixing)
            .help("MicroCode AI Agent repairs and re-runs this cell automatically")
            
            // 2. Open in Full AI Agent Chat
            Button {
                openInAgentChat()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 9))
                    Text("Ask Agent")
                }
                .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
            .disabled(isFixing)
            .help("Switch to MicroCode AI Agent to interactively debug and fix this error")
            
            // 3. Copy Traceback Button
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cell.output, forType: .string)
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCopied = false }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                    Text(showCopied ? "Copied" : "Copy")
                }
                .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
            .disabled(isFixing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
    
    private func triggerAgentAutoFix() {
        isFixing = true
        fixStatus = "Agent analyzing traceback..."
        
        let prompt = """
        You are the MicroCode Autonomous AI Agent.
        The following \(cell.language.rawValue) notebook cell failed with an execution error.
        
        LANGUAGE: \(cell.language.rawValue)
        CODE:
        ```\(cell.language.rawValue.lowercased())
        \(cell.content)
        ```
        
        TRACEBACK:
        ```
        \(cell.output)
        ```
        
        Analyze the exact failure (syntax, missing import, compiler flags, or logic).
        Repair the code completely.
        Output ONLY the corrected runnable code inside a single ```\(cell.language.rawValue.lowercased()) ... ``` block.
        Do NOT write explanations or conversation.
        """
        
        let providerStr = UserDefaults.standard.string(forKey: "aiProvider") ?? "omni"
        let provider = StreamableAIProvider(rawValue: providerStr) ?? .omni
        let model = UserDefaults.standard.string(forKey: "aiModel") ?? provider.defaultModel
        let key = UserDefaults.standard.string(forKey: "\(provider.rawValue)_api_key") ?? UserDefaults.standard.string(forKey: "apiKey") ?? ""
        
        AIClient.shared.sendMessage(
            prompt: prompt,
            systemPrompt: "You are the MicroCode AI Agent. Output ONLY the fixed code inside a single markdown code block.",
            provider: provider,
            model: model,
            apiKey: key,
            onToken: { _ in },
            onComplete: { response in
                DispatchQueue.main.async {
                    self.isFixing = false
                    
                    var fixed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    if fixed.contains("```") {
                        let lines = fixed.components(separatedBy: .newlines)
                        var codeLines: [String] = []
                        var inside = false
                        for l in lines {
                            let trimmed = l.trimmingCharacters(in: .whitespaces)
                            if trimmed.hasPrefix("```") {
                                inside.toggle()
                                continue
                            }
                            if inside {
                                codeLines.append(l)
                            }
                        }
                        if !codeLines.isEmpty {
                            fixed = codeLines.joined(separator: "\n")
                        }
                    }
                    
                    if !fixed.isEmpty {
                        self.cell.content = fixed
                        self.cell.appendOutput("\n⚡ [Agent Self-Healing] Code patched. Re-executing now...\n")
                        self.onRun()
                    }
                }
            },
            onError: { err in
                DispatchQueue.main.async {
                    self.isFixing = false
                    self.cell.appendOutput("\n⚠️ [Agent Self-Healing] Repair error: \(err)\n")
                }
            }
        )
    }
    
    private func openInAgentChat() {
        let inquiry = """
        Please analyze and fix this \(cell.language.rawValue) notebook cell error:
        
        CODE:
        ```\(cell.language.rawValue.lowercased())
        \(cell.content)
        ```
        
        ERROR TRACEBACK:
        ```
        \(cell.output)
        ```
        """
        
        // Copy error prompt to pasteboard so user can easily paste into chat
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(inquiry, forType: .string)
        
        // Post notification to switch to Agent surface
        NotificationCenter.default.post(name: NSNotification.Name("SwitchToAgentSurface"), object: inquiry)
    }
}


// MARK: - HPC Settings View

// MARK: - Dotmini Cloud GPU Hub & Settings View

struct HPCSettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var cloudGPU = CloudGPUService.shared
    @ObservedObject private var gpu = RemoteGPUService.shared
    @ObservedObject private var prov = RemoteProviderService.shared
    
    @AppStorage("remoteSSHCommand") private var sshCmd = ""
    @AppStorage("remoteSSHKey") private var sshKey = ""
    @AppStorage("runpodApiKey") private var runpodKey = ""
    @AppStorage("vastApiKey") private var vastKey = ""
    @AppStorage("cloudGPUBaseURL") private var cloudGPUBase = ""
    
    @State private var selectedTab = 0 // 0=Cluster, 1=Wallet, 2=Git Ingest, 3=SSH
    @State private var providerSel: RemoteProviderService.Provider = .runpod
    @State private var customTopupAmount: String = "300"
    @State private var isTopupLoading: Bool = false
    @State private var topupError: String = ""
    
    // Git Ingestion State
    @State private var gitRepoURL: String = ""
    @State private var gitBranch: String = "main"
    @State private var gitToken: String = ""
    @State private var gitDestination: String = "data"
    @State private var isIngesting: Bool = false
    @State private var ingestLogs: String = ""
    @State private var cloudFileList: [String] = []
    @State private var isRefreshingFiles: Bool = false
    
    @State private var testing = false
    @State private var testOK: Bool? = nil
    @State private var testMsg = ""

    private var isConnected: Bool {
        cloudGPU.activeSession != nil || gpu.status == .connected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            headerView
            
            // Tab Selector
            Picker("", selection: $selectedTab) {
                Text("GPU Cluster").tag(0)
                Text("GPU Wallet").tag(1)
                Text("Git Ingest").tag(2)
                Text("SSH / Custom").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            Divider()
            
            // Content by Tab
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch selectedTab {
                    case 0:
                        gpuClusterTab
                    case 1:
                        gpuWalletTab
                    case 2:
                        gitIngestTab
                    case 3:
                        sshManualTab
                    default:
                        gpuClusterTab
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 380)
        }
        .padding(14)
        .frame(width: 440)
        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))
        .onAppear {
            Task {
                await cloudGPU.refresh()
            }
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Dotmini Cloud GPU Hub")
                    .font(.headline)
                Text("High-performance compute clusters & persistent storage")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Wallet Badge
            Button {
                selectedTab = 1
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "creditcard.fill")
                        .foregroundColor(.green)
                        .font(.caption2)
                    Text(cloudGPU.balanceText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(appState.appTheme.isGlass ? Color.white.opacity(0.08) : Color(nsColor: appState.appTheme.elevatedBackground))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("GPU Credit Balance")
        }
    }

    // MARK: - Tab 0: GPU Cluster
    private var gpuClusterTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session = cloudGPU.activeSession {
                // Active Session Info
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Active: \(session.gpuLabel)")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(cloudGPU.priceText(session.pricePerMinute))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Jupyter WSS tunnel active. Cells are executed directly on the cloud GPU.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button(role: .destructive) {
                            Task { await cloudGPU.stop() }
                        } label: {
                            Label("Disconnect GPU", systemImage: "stop.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                        
                        Spacer()
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
            } else {
                Text("Select an NVIDIA GPU instance. Pricing includes compute rate + 7% VAT + service fee.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // GPU Catalog List
            VStack(spacing: 6) {
                ForEach(cloudGPU.catalog) { gpu in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(gpu.label)
                                    .font(.system(size: 11, weight: .medium))
                                Text("\(gpu.vramGB)GB VRAM")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .cornerRadius(3)
                            }
                            Text(gpu.pricePerHourText + " (\(cloudGPU.priceText(gpu.pricePerMinute)))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            Task {
                                await cloudGPU.connect(gpu: gpu) {
                                    selectedTab = 1 // Switch to wallet on insufficient balance
                                }
                            }
                        } label: {
                            if cloudGPU.status == .connecting && cloudGPU.activeSession == nil {
                                ProgressView().scaleEffect(0.6)
                            } else {
                                Text(cloudGPU.activeSession?.gpuLabel == gpu.label ? "Connected" : "Launch")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(cloudGPU.activeSession != nil || cloudGPU.status == .connecting)
                    }
                    .padding(8)
                    .background(appState.appTheme.isGlass ? Color.white.opacity(0.05) : Color(nsColor: appState.appTheme.elevatedBackground))
                    .cornerRadius(8)
                }
            }

            if !cloudGPU.lastError.isEmpty {
                Text(cloudGPU.lastError)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Tab 1: GPU Wallet (Credit)
    private var gpuWalletTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GPU CREDIT BALANCE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                
                HStack(alignment: .firstTextBaseline) {
                    Text(cloudGPU.balanceText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                    Spacer()
                    Button {
                        Task { await cloudGPU.loadWallet() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh Balance")
                }
                
                Text("GPU Credit is dedicated to cloud computing only (RunPod + VAT + margin) and is separate from AI Assistant subscriptions.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(appState.appTheme.isGlass ? Color.white.opacity(0.05) : Color(nsColor: appState.appTheme.elevatedBackground))
            .cornerRadius(8)

            Text("Top-up Packages")
                .font(.system(size: 11, weight: .semibold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(CloudGPUService.defaultTopupPackages) { pkg in
                    Button {
                        Task {
                            isTopupLoading = true
                            topupError = ""
                            let (url, err) = await cloudGPU.topUp(packageId: pkg.id)
                            isTopupLoading = false
                            if let u = url { NSWorkspace.shared.open(u) }
                            else if let e = err { topupError = e }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(pkg.name)
                                    .font(.system(size: 11, weight: .bold))
                                Spacer()
                                if let b = pkg.badge {
                                    Text(b)
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundColor(.orange)
                                        .cornerRadius(3)
                                }
                            }
                            Text("฿\(pkg.amountTHB)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary)
                            if pkg.bonusTHB > 0 {
                                Text("+฿\(pkg.bonusTHB) Bonus Credit")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(appState.appTheme.isGlass ? Color.white.opacity(0.06) : Color(nsColor: appState.appTheme.elevatedBackground))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Custom Top-up
            VStack(alignment: .leading, spacing: 6) {
                Text("Custom Top-up (THB)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    TextField("Amount in THB (e.g. 300)", text: $customTopupAmount)
                        .textFieldStyle(.roundedBorder)
                    
                    Button {
                        if let amt = Int(customTopupAmount), amt >= 50 {
                            Task {
                                isTopupLoading = true
                                topupError = ""
                                let (url, err) = await cloudGPU.topUpCustom(amountTHB: amt)
                                isTopupLoading = false
                                if let u = url { NSWorkspace.shared.open(u) }
                                else if let e = err { topupError = e }
                            }
                        }
                    } label: {
                        if isTopupLoading {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Text("Checkout")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if !topupError.isEmpty {
                Text(topupError)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Tab 2: Git Cloud Ingest (10Gbps Direct Clone)
    private var gitIngestTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ingest large datasets or repositories from GitHub / GitLab / HuggingFace directly to the Cloud Pod's 10Gbps storage without using your local bandwidth.")
                .font(.caption2)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("REPOSITORY URL").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                TextField("https://github.com/username/large-dataset", text: $gitRepoURL)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BRANCH").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                        TextField("main", text: $gitBranch)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TARGET DIR").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                        TextField("data", text: $gitDestination)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                }

                Text("AUTH TOKEN (Optional for Private Repos)").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                SecureField("Personal Access Token (ghp_... / glpat-...)", text: $gitToken)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task {
                        isIngesting = true
                        ingestLogs = "Starting 10Gbps Git Ingestion on Cloud Pod...\n"
                        do {
                            let res = try await cloudGPU.cloneGitRepository(
                                repoURL: gitRepoURL,
                                branch: gitBranch,
                                token: gitToken.isEmpty ? nil : gitToken,
                                destination: gitDestination
                            ) { progressLine in
                                ingestLogs += progressLine
                            }
                            ingestLogs += "\n" + res
                            await refreshCloudFiles()
                        } catch {
                            ingestLogs += "\n❌ Error: \(error.localizedDescription)"
                        }
                        isIngesting = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isIngesting { ProgressView().scaleEffect(0.6) }
                        Image(systemName: "arrow.down.to.line.circle.fill")
                        Text(isIngesting ? "Ingesting..." : "Ingest Dataset to Cloud Volume")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                .disabled(isIngesting || gitRepoURL.trimmingCharacters(in: .whitespaces).isEmpty || cloudGPU.activeSession == nil)

                if cloudGPU.activeSession == nil {
                    Text("⚠️ Launch a GPU instance in Tab 1 first before ingesting.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            if !ingestLogs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("INGESTION LOGS").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    ScrollView {
                        Text(ingestLogs)
                            .font(.system(size: 9, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 80)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3)))
                }
            }
        }
    }

    private func refreshCloudFiles() async {
        isRefreshingFiles = true
        cloudFileList = await cloudGPU.listCloudFiles(remotePath: gitDestination)
        isRefreshingFiles = false
    }

    // MARK: - Tab 3: SSH / Custom Provider
    private var sshManualTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect directly to self-hosted instances or private SSH tunnels.")
                .font(.caption2)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("SSH COMMAND").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                TextField("ssh -p 41122 root@1.2.3.4 -i ~/.ssh/key", text: $sshCmd, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...2)
            }

            HStack(spacing: 8) {
                Button {
                    gpu.connect(sshCommand: sshCmd, keyPath: sshKey.isEmpty ? nil : sshKey)
                } label: {
                    Text(gpu.status == .connected ? "Connected" : "Connect via SSH")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(gpu.status == .connecting || sshCmd.trimmingCharacters(in: .whitespaces).isEmpty)

                if gpu.status == .connected {
                    Button(role: .destructive) { gpu.disconnect() } label: {
                        Text("Disconnect")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            DisclosureGroup("Advanced: Cloudflare / Custom Jupyter URL") {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("https://xxxx.trycloudflare.com", text: $appState.hpcEndpoint)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Jupyter Token", text: $appState.hpcToken)
                        .textFieldStyle(.roundedBorder)
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if !testMsg.isEmpty {
                        Text(testMsg)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(testOK == true ? .green : .red)
                    }
                }
                .padding(.top, 4)
            }
            .font(.system(size: 10))
        }
    }

    private func testConnection() async {
        testing = true; testOK = nil; testMsg = ""
        defer { testing = false }
        var base = appState.hpcEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }
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
            } else {
                testOK = false; testMsg = "HTTP \(http.statusCode)"
            }
        } catch {
            testOK = false
            testMsg = "Unreachable: \(error.localizedDescription)"
        }
    }
}
