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

    // Per-Cell AI / Autonomous Agent Configuration & Live Execution State
    @Published var aiSelection: CellAISelection = .inherit
    @Published var agentExecutionMode: Bool = true
    @Published var agentThought: String = ""
    @Published var agentToolSteps: [CellAgentToolStep] = []
    @Published var agentStatusText: String = ""

    // Cell Mode v2: Sequential Queue, Reactive DAG Epoch, Inline DataFrame, Telemetry, Diff & Time-Travel
    @Published var isQueued: Bool = false
    @Published var lastRunEpoch: Int = 0
    @Published var inlineDataFrame: InlineDataFramePayload? = nil
    @Published var telemetry: CellExecutionTelemetry? = nil
    @Published var versionSnapshots: [CellVersionSnapshot] = []
    @Published var pendingDiffOldContent: String? = nil
    @Published var pendingDiffSource: String = "AI Agent"
    
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
        inlineDataFrame = nil
        telemetry = nil
        agentThought = ""
        agentToolSteps = []
        agentStatusText = ""
    }

    func recordAgentEditBaseline(previousContent: String, source: String = "AI Agent") {
        let trimmedPrev = previousContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrev.isEmpty else { return }
        if pendingDiffOldContent == nil {
            pendingDiffOldContent = previousContent
        }
        pendingDiffSource = source
        let nextVer = (versionSnapshots.last?.versionNumber ?? 0) + 1
        versionSnapshots.append(CellVersionSnapshot(
            versionNumber: nextVer,
            timestamp: Date(),
            sourceLabel: "Before \(source)",
            content: previousContent,
            outputPreview: String(output.prefix(160)),
            durationMs: telemetry?.durationMs
        ))
        if versionSnapshots.count > 12 {
            versionSnapshots.removeFirst(versionSnapshots.count - 12)
        }
    }

    func recordExecutionSnapshot(source: String = "Run") {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let last = versionSnapshots.last, last.content == content {
            return
        }
        let nextVer = (versionSnapshots.last?.versionNumber ?? 0) + 1
        versionSnapshots.append(CellVersionSnapshot(
            versionNumber: nextVer,
            timestamp: Date(),
            sourceLabel: source,
            content: content,
            outputPreview: String(output.prefix(160)),
            durationMs: telemetry?.durationMs
        ))
        if versionSnapshots.count > 12 {
            versionSnapshots.removeFirst(versionSnapshots.count - 12)
        }
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
    static let shared = NotebookViewModel()

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
    @Published var isReactiveMode: Bool = false
    @Published var showVariableInspector: Bool = false
    @Published var isAppPresentationMode: Bool = false
    @Published var globalExecutionEpoch: Int = 0
    private var autoSaveWork: DispatchWorkItem?
    private var executionQueue: [(cellId: UUID, target: ComputeTarget?)] = []
    private var isDrainingQueue: Bool = false

    var isAnyCellExecuting: Bool {
        activeNotebook?.cells.contains(where: { $0.isExecuting }) ?? false
    }

    private var dataDirectory: URL {
        (scientificProjectURL ?? workingDirectory).appendingPathComponent("data", isDirectory: true)
    }

    /// Realtime autosave: debounced & offloaded to `NotebookPersistenceActor` WAL
    /// so rapid typing or 60Hz output streaming never blocks `@MainActor` or `cfprefsd`.
    func scheduleAutoSave() {
        autoSaveWork?.cancel()
        let delay: TimeInterval = isAnyCellExecuting ? 1.8 : 0.8
        let work = DispatchWorkItem { [weak self] in self?.performAutoSave() }
        autoSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func performAutoSave() {
        guard !isAnyCellExecuting else {
            scheduleAutoSave()
            return
        }
        autoSave() // Off-MainActor atomic WAL snapshot
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
            content = ""  // Clean prompt composer with placeholder
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
    
    // MARK: - Cell Mode v2: Sequential Async Scheduler, Warm Kernels & Cached Polyglot Execution

    func cancelExecutionQueue() {
        guard let nb = activeNotebook else {
            executionQueue.removeAll()
            return
        }
        for queued in executionQueue {
            nb.cells.first(where: { $0.id == queued.cellId })?.isQueued = false
        }
        executionQueue.removeAll()
    }

    func enqueueCells(_ cells: [NotebookCellModel], computeTarget: ComputeTarget? = nil) {
        let runnable = cells.filter { $0.type == .code || $0.type == .procedure || $0.type == .agent }
        guard !runnable.isEmpty else { return }

        for c in runnable {
            if !c.isExecuting && !executionQueue.contains(where: { $0.cellId == c.id }) {
                c.isQueued = true
                executionQueue.append((cellId: c.id, target: computeTarget))
            }
        }

        Task { @MainActor in
            await self.drainExecutionQueueIfNeeded()
        }
    }

    private func drainExecutionQueueIfNeeded() async {
        guard !isDrainingQueue else { return }
        if isAnyCellExecuting {
            return
        }
        isDrainingQueue = true
        defer {
            isDrainingQueue = false
            if !isAnyCellExecuting && kernelStatus == "Running" {
                kernelStatus = "Idle"
            }
        }

        while !executionQueue.isEmpty {
            let nextItem = executionQueue.removeFirst()
            guard let notebook = activeNotebook,
                  let cell = notebook.cells.first(where: { $0.id == nextItem.cellId }) else {
                continue
            }
            cell.isQueued = false
            cell.isExecuting = true
            cell.clearOutput()
            kernelStatus = "Running"

            let ok = await performCellExecutionBody(cell, computeTarget: nextItem.target)
            if !ok {
                // Halt downstream batch cascade on runtime/compile failure
                cancelExecutionQueue()
                kernelStatus = "Error"
                break
            }
        }
    }

    private func enqueueReactiveDownstream(from rootCell: NotebookCellModel, computeTarget: ComputeTarget?) {
        guard isReactiveMode, let nb = activeNotebook else { return }
        let inputs = nb.cells.map {
            (
                id: $0.id,
                isRunnableCode: $0.type == .code || $0.type == .procedure,
                content: $0.type == .procedure ? $0.generatedCode : $0.content,
                lastRunEpoch: $0.lastRunEpoch
            )
        }
        let graph = CellLineageDAGAnalyzer.analyzeGraph(cells: inputs)
        let orderedIds = nb.cells.map(\.id)
        let downstreamIds = CellLineageDAGAnalyzer.transitiveDownstreamIds(
            from: rootCell.id,
            graph: graph,
            orderedIds: orderedIds
        )
        guard !downstreamIds.isEmpty else { return }
        let downstreamCells = downstreamIds.compactMap { id in nb.cells.first(where: { $0.id == id }) }
        enqueueCells(downstreamCells, computeTarget: computeTarget)
    }

    func runCell(_ cell: NotebookCellModel, computeTarget: ComputeTarget? = nil) {
        guard cell.type == .code || cell.type == .procedure || cell.type == .agent else { return }
        TelemetryService.shared.recordFeature("Notebook Cell (\(cell.language.rawValue))")

        let effectiveTarget: ComputeTarget = cell.computeTargetOverride ?? computeTarget ?? AppState.shared?.currentComputeTarget ?? .localCPU

        // 1. If queued but not yet running, unqueue immediately
        if cell.isQueued && !cell.isExecuting {
            executionQueue.removeAll { $0.cellId == cell.id }
            cell.isQueued = false
            return
        }

        // 2. If currently executing, interrupt/stop cleanly (preserving warm Python RAM state via SIGINT)
        if cell.isExecuting {
            cancelExecutionQueue()
            if cell.type == .agent {
                CellAgentCoordinator.shared.stop(sessionId: "agent-cell-\(cell.id.uuidString)")
                cell.agentStatusText = ""
                cell.isExecuting = false
                self.kernelStatus = "Idle"
                return
            }

            let isLocal = (effectiveTarget == .localCPU || effectiveTarget == .localMLX || effectiveTarget == .localNvidia)
            if isLocal {
                if (cell.language == .python || cell.type == .procedure || cell.language == .sql),
                   let nbId = activeNotebook?.id {
                    LocalPersistentPythonKernelPool.shared.interrupt(notebookId: nbId)
                } else if cell.language == .julia, let nbId = activeNotebook?.id {
                    LocalPersistentJuliaKernelPool.shared.restart(notebookId: nbId)
                    cell.appendOutput("\n⏹ Julia execution interrupted.\n")
                    cell.isExecuting = false
                    self.kernelStatus = "Idle"
                } else {
                    PolyglotStreamingAndCacheEngine.shared.cancelProcess(for: cell.id)
                }
                return
            }

            Task {
                let kernel = ComputeKernelRouter.shared.getKernel(for: effectiveTarget)
                try? await kernel.cancel()
                await MainActor.run {
                    cell.appendOutput("\n⏹ Interrupted by user.\n")
                    cell.isExecuting = false
                    self.kernelStatus = "Idle"
                }
            }
            return
        }

        // 3. If another cell is currently executing or queue is draining, enqueue sequentially
        if isDrainingQueue || isAnyCellExecuting {
            enqueueCells([cell], computeTarget: computeTarget)
            return
        }

        // 4. Synchronous state transition so callers & Agent tools observe `isExecuting == true` immediately
        cell.isQueued = false
        cell.isExecuting = true
        cell.clearOutput()
        kernelStatus = "Running"

        Task { @MainActor in
            let ok = await self.performCellExecutionBody(cell, computeTarget: computeTarget)
            if ok && self.isReactiveMode {
                self.enqueueReactiveDownstream(from: cell, computeTarget: computeTarget)
            }
            await self.drainExecutionQueueIfNeeded()
        }
    }

    private func performCellExecutionBody(_ cell: NotebookCellModel, computeTarget: ComputeTarget?) async -> Bool {
        let effectiveTarget: ComputeTarget = cell.computeTargetOverride ?? computeTarget ?? AppState.shared?.currentComputeTarget ?? .localCPU

        if cell.language == .python || cell.type == .procedure {
            let codeToScan = cell.type == .procedure ? cell.generatedCode : cell.content
            _ = PythonEnvManager.shared.detectImportsFromCode(codeToScan)
        }

        if cell.type == .agent {
            return await executeAgentCellAsync(cell)
        }

        if effectiveTarget != .localCPU && effectiveTarget != .localMLX && effectiveTarget != .localNvidia {
            return await executeRemoteKernelCellAsync(cell, effectiveTarget: effectiveTarget)
        }

        if cell.type == .procedure {
            return await executeLocalPythonOrProcedureCellAsync(cell)
        }

        switch cell.language {
        case .python:
            return await executeLocalPythonOrProcedureCellAsync(cell)
        case .rust:
            return await executeLocalRustCellAsync(cell)
        case .cpp:
            return await executeLocalCppCellAsync(cell)
        case .objc:
            return await executeLocalObjcCellAsync(cell)
        case .julia:
            return await executeLocalJuliaCellAsync(cell)
        case .go:
            return await executeLocalGoCellAsync(cell)
        case .r:
            return await executeLocalRCellAsync(cell)
        case .rmarkdown:
            return await executeLocalRMarkdownCellAsync(cell)
        case .latex:
            return await executeLocalLaTeXCellAsync(cell)
        case .sql:
            return await executeLocalSQLCellAsync(cell)
        case .ardium:
            return await executeLocalArdiumCellAsync(cell)
        case .java, .csharp:
            return await executeLocalManagedRuntimeCellAsync(cell)
        }
    }

    private func parseEmbeddedImageMarkers(from rawText: String) -> (cleanText: String, images: [URL]) {
        let pattern = "\\[IMAGE:([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (rawText, [])
        }
        var images: [URL] = []
        let matches = regex.matches(in: rawText, range: NSRange(rawText.startIndex..., in: rawText))
        for match in matches {
            if let range = Range(match.range(at: 1), in: rawText) {
                let filename = String(rawText[range])
                let imageURL = filename.hasPrefix("/")
                    ? URL(fileURLWithPath: filename)
                    : workingDirectory.appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: imageURL.path) && !images.contains(imageURL) {
                    images.append(imageURL)
                }
            }
        }
        let cleaned = regex.stringByReplacingMatches(
            in: rawText,
            range: NSRange(rawText.startIndex..., in: rawText),
            withTemplate: ""
        )
        return (cleaned, images)
    }

    private func finalizeCellExecution(
        cell: NotebookCellModel,
        outputText: String,
        images: [URL] = [],
        inlineDF: InlineDataFramePayload? = nil,
        telemetry: CellExecutionTelemetry? = nil,
        hadError: Bool = false
    ) -> Bool {
        // Backward-compatible check for legacy JSON DataFrame path marker
        if inlineDF == nil,
           let data = outputText.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let isDF = json["__microcode_dataframe__"] as? Bool, isDF,
           let path = json["path"] as? String {
            cell.output = ""
            cell.dataFramePath = path
            cell.isDataFrame = true
        } else {
            let parsed = parseEmbeddedImageMarkers(from: outputText)
            var mergedImages = images
            for img in parsed.images where !mergedImages.contains(img) {
                mergedImages.append(img)
            }
            cell.output = parsed.cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
            cell.outputImages = mergedImages
            cell.inlineDataFrame = inlineDF
        }

        cell.telemetry = telemetry
        cell.isExecuting = false
        totalExecutions += 1
        cell.executionCount = totalExecutions
        globalExecutionEpoch += 1
        cell.lastRunEpoch = globalExecutionEpoch
        cell.recordExecutionSnapshot(source: telemetry?.isCachedBinary == true ? "Cached Run" : "Run")
        kernelStatus = hadError ? "Error" : "Idle"
        activeNotebook?.modifiedAt = Date()
        scheduleAutoSave()
        return !hadError
    }

    nonisolated private func buildCellProcessEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let portableBins = RuntimeManager.shared.allRuntimeBinDirectories()
        let extraPaths = portableBins + [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.bun/bin",
            "\(home)/.deno/bin",
            "\(home)/.local/bin",
            "\(home)/go/bin",
            "/usr/local/go/bin"
        ]
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
        if env["JAVA_HOME"] == nil, let javaHome = RuntimeManager.shared.portableJavaHome() {
            env["JAVA_HOME"] = javaHome
        }
        if env["GOROOT"] == nil, let goRoot = RuntimeManager.shared.portableGoRoot() {
            env["GOROOT"] = goRoot
        }
        env["MICROCODE_LOCAL_API_TOKEN"] = LocalBackendAuth.token
        return env
    }

    private func executeAgentCellAsync(_ cell: NotebookCellModel) async -> Bool {
        let prompt = cell.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            cell.isExecuting = false
            self.kernelStatus = "Idle"
            return true
        }
        guard let appState = AppState.shared else {
            cell.output = "⚠️ Application state is not initialized."
            cell.isExecuting = false
            self.kernelStatus = "Error"
            return false
        }

        let sessionId = "agent-cell-\(cell.id.uuidString)"
        let workspaceRoot = appState.workspaceFolder?.path ?? workingDirectory.path
        let notebookContext = CellAgentCoordinator.shared.buildNotebookContextSnapshot(viewModel: self)

        cell.agentStatusText = cell.agentExecutionMode ? "Agent inspecting notebook…" : "Generating…"
        cell.agentThought = ""
        cell.agentToolSteps = []
        let t0 = CFAbsoluteTimeGetCurrent()

        return await withCheckedContinuation { continuation in
            var resumed = false
            CellAgentCoordinator.shared.startExecution(
                sessionId: sessionId,
                prompt: prompt,
                selection: cell.aiSelection,
                isAgentMode: cell.agentExecutionMode,
                appState: appState,
                notebookContext: notebookContext,
                workspaceRoot: workspaceRoot,
                onStatus: { status in
                    cell.agentStatusText = status
                },
                onThought: { thought in
                    cell.agentThought = thought
                },
                onText: { liveText in
                    cell.output = liveText
                },
                onToolSteps: { steps in
                    cell.agentToolSteps = steps
                },
                onComplete: { finalText in
                    guard !resumed else { return }
                    resumed = true
                    if cell.output.isEmpty && !finalText.isEmpty {
                        cell.output = finalText
                    } else if cell.output.isEmpty && !cell.agentToolSteps.isEmpty {
                        cell.output = "ดำเนินการเสร็จเรียบร้อย (\(cell.agentToolSteps.count) tool steps)"
                    }
                    cell.agentStatusText = ""
                    cell.telemetry = CellExecutionTelemetry(
                        durationMs: (CFAbsoluteTimeGetCurrent() - t0) * 1000.0,
                        memoryDeltaBytes: 0,
                        peakRSSBytes: 0,
                        metalAllocatedBytes: 0,
                        isCachedBinary: false
                    )
                    cell.isExecuting = false
                    self.kernelStatus = "Idle"
                    self.totalExecutions += 1
                    cell.executionCount = self.totalExecutions
                    self.globalExecutionEpoch += 1
                    cell.lastRunEpoch = self.globalExecutionEpoch
                    self.scheduleAutoSave()
                    continuation.resume(returning: true)
                },
                onError: { error in
                    guard !resumed else { return }
                    resumed = true
                    let prefix = cell.output.isEmpty ? "" : cell.output + "\n\n"
                    cell.output = prefix + "⚠️ \(error)"
                    cell.agentStatusText = ""
                    cell.isExecuting = false
                    self.kernelStatus = "Error"
                    continuation.resume(returning: false)
                }
            )
        }
    }

    private func executeRemoteKernelCellAsync(_ cell: NotebookCellModel, effectiveTarget: ComputeTarget) async -> Bool {
        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            if effectiveTarget == .customHPC {
                try await CloudGPUService.shared.ensureManagedSession()
            }
            if effectiveTarget == .googleColab {
                if !GoogleColabService.shared.status.isConnected {
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

            let streamBuf = TerminalStreamBuffer()
            let result = try await kernel.execute(code: cell.content, language: cell.language.rawValue) { chunk in
                let snap = streamBuf.appendChunk(chunk)
                DispatchQueue.main.async {
                    cell.output = snap
                }
            }
            let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            let combined = cell.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? result : cell.output
            let hadErr = combined.contains("Traceback") || combined.contains("Error:")
            return finalizeCellExecution(
                cell: cell,
                outputText: combined,
                telemetry: CellExecutionTelemetry(durationMs: dtMs, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false),
                hadError: hadErr
            )
        } catch {
            if effectiveTarget == .googleColab {
                NotificationCenter.default.post(name: NSNotification.Name("MicroCodeOpenColabSheet"), object: nil)
            }
            let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            return finalizeCellExecution(
                cell: cell,
                outputText: cell.output + "\n❌ Kernel Error: \(error.localizedDescription)",
                telemetry: CellExecutionTelemetry(durationMs: dtMs, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false),
                hadError: true
            )
        }
    }

    private func executeLocalPythonOrProcedureCellAsync(_ cell: NotebookCellModel) async -> Bool {
        let userCode = cell.type == .procedure ? cell.generatedCode : cell.content
        let nbId = activeNotebook?.id ?? UUID()
        let rawPython = PythonEnvManager.shared.activeEnvironment?.pythonPath ?? selectedPythonPath
        let resolvedPython = PythonEnvManager.shared.resolveExecutablePath(rawPython)

        let kernel = LocalPersistentPythonKernelPool.shared.kernel(
            for: nbId,
            pythonPath: resolvedPython,
            workingDirectory: workingDirectory
        )

        let outcome = await kernel.executeCell(
            cellId: cell.id,
            executionIndex: totalExecutions + 1,
            code: userCode
        ) { liveStream in
            cell.output = liveStream
        }

        return finalizeCellExecution(
            cell: cell,
            outputText: outcome.stdoutText,
            images: outcome.imageURLs,
            inlineDF: outcome.inlineDataFrame,
            telemetry: outcome.telemetry,
            hadError: outcome.hadError
        )
    }

    private func executeLocalRustCellAsync(_ cell: NotebookCellModel) async -> Bool {
        _ = await RuntimeManager.shared.ensureRuntime(forLanguage: "rust") { msg in
            DispatchQueue.main.async { cell.appendOutput(msg + "\n") }
        }
        let rustcPath = RuntimeManager.shared.selectedExecutable(for: .rust) ?? "rustc"
        let env = buildCellProcessEnvironment()

        let res = await PolyglotStreamingAndCacheEngine.shared.runCompiledCellWithCache(
            cellId: cell.id,
            languageTag: "rust",
            sourceExtension: "rs",
            sourceCode: cell.content,
            compilerExecutable: rustcPath,
            compilerArgsBuilder: { src, bin in ["-O", src, "-o", bin] },
            workingDirectory: workingDirectory,
            environment: env,
            onStream: { live in cell.output = live }
        )
        return finalizeCellExecution(cell: cell, outputText: res.output, telemetry: res.telemetry, hadError: res.hadError)
    }

    private func executeLocalCppCellAsync(_ cell: NotebookCellModel) async -> Bool {
        _ = await RuntimeManager.shared.ensureRuntime(forLanguage: "cpp") { msg in
            DispatchQueue.main.async { cell.appendOutput(msg + "\n") }
        }
        let clangppPath = RuntimeManager.shared.selectedExecutable(for: .cpp) ?? "clang++"
        let env = buildCellProcessEnvironment()

        let res = await PolyglotStreamingAndCacheEngine.shared.runCompiledCellWithCache(
            cellId: cell.id,
            languageTag: "cpp20",
            sourceExtension: "cpp",
            sourceCode: cell.content,
            compilerExecutable: clangppPath,
            compilerArgsBuilder: { src, bin in ["-std=c++20", "-O2", src, "-o", bin] },
            workingDirectory: workingDirectory,
            environment: env,
            onStream: { live in cell.output = live }
        )
        return finalizeCellExecution(cell: cell, outputText: res.output, telemetry: res.telemetry, hadError: res.hadError)
    }

    private func executeLocalObjcCellAsync(_ cell: NotebookCellModel) async -> Bool {
        let env = buildCellProcessEnvironment()
        let res = await PolyglotStreamingAndCacheEngine.shared.runCompiledCellWithCache(
            cellId: cell.id,
            languageTag: "objc",
            sourceExtension: "m",
            sourceCode: cell.content,
            compilerExecutable: "clang",
            compilerArgsBuilder: { src, bin in ["-O2", "-fobjc-arc", "-framework", "Foundation", src, "-o", bin] },
            workingDirectory: workingDirectory,
            environment: env,
            onStream: { live in cell.output = live }
        )
        return finalizeCellExecution(cell: cell, outputText: res.output, telemetry: res.telemetry, hadError: res.hadError)
    }

    private func executeLocalGoCellAsync(_ cell: NotebookCellModel) async -> Bool {
        _ = await RuntimeManager.shared.ensureRuntime(forLanguage: "go") { msg in
            DispatchQueue.main.async { cell.appendOutput(msg + "\n") }
        }
        let goPath = RuntimeManager.shared.selectedExecutable(for: .go) ?? "go"
        let env = buildCellProcessEnvironment()
        let tempGo = workingDirectory.appendingPathComponent("temp_\(UUID().uuidString.prefix(8)).go")
        defer { try? FileManager.default.removeItem(at: tempGo) }

        do {
            try cell.content.write(to: tempGo, atomically: true, encoding: .utf8)
            let execURL = goPath.contains("/") ? URL(fileURLWithPath: goPath) : URL(fileURLWithPath: "/usr/bin/env")
            let args = goPath.contains("/") ? ["run", tempGo.path] : ["go", "run", tempGo.path]
            let res = try await PolyglotStreamingAndCacheEngine.shared.runStreamingProcess(
                cellId: cell.id,
                executableURL: execURL,
                arguments: args,
                workingDirectory: workingDirectory,
                environment: env,
                onStream: { live in cell.output = live }
            )
            let tel = CellExecutionTelemetry(durationMs: res.durationMs, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false)
            return finalizeCellExecution(cell: cell, outputText: res.output, telemetry: tel, hadError: res.exitCode != 0)
        } catch {
            return finalizeCellExecution(cell: cell, outputText: "❌ Error: \(error.localizedDescription)", hadError: true)
        }
    }

    private func executeLocalArdiumCellAsync(_ cell: NotebookCellModel) async -> Bool {
        let t0 = CFAbsoluteTimeGetCurrent()
        var finalCode = cell.content
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
        let cleanPattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        let cleanOut = out.replacingOccurrences(of: cleanPattern, with: "", options: .regularExpression)
        let tel = CellExecutionTelemetry(
            durationMs: (CFAbsoluteTimeGetCurrent() - t0) * 1000.0,
            memoryDeltaBytes: 0,
            peakRSSBytes: 0,
            metalAllocatedBytes: 0,
            isCachedBinary: false
        )
        return finalizeCellExecution(cell: cell, outputText: cleanOut, telemetry: tel, hadError: res.exitCode != 0)
    }

    private func executeLocalManagedRuntimeCellAsync(_ cell: NotebookCellModel) async -> Bool {
        let langKey = (cell.language == .java) ? "java" : "csharp"
        let t0 = CFAbsoluteTimeGetCurrent()
        let ready = await RuntimeManager.shared.ensureRuntime(forLanguage: langKey) { msg in
            DispatchQueue.main.async { cell.appendOutput(msg + "\n") }
        }
        guard ready else {
            return finalizeCellExecution(
                cell: cell,
                outputText: "❌ \(cell.language.rawValue) runtime is not installed. Run `curl -fsSL https://microcode.dotmini.net/install.sh | bash` in Terminal.",
                hadError: true
            )
        }
        guard let appState = AppState.shared else {
            return finalizeCellExecution(cell: cell, outputText: "❌ AppState is not ready.", hadError: true)
        }
        let res = await appState.executeScript(code: cell.content, language: langKey)
        let combined = res.stdout + (res.stderr.isEmpty ? "" : (res.stdout.isEmpty ? "" : "\n") + res.stderr)
        let tel = CellExecutionTelemetry(
            durationMs: (CFAbsoluteTimeGetCurrent() - t0) * 1000.0,
            memoryDeltaBytes: 0,
            peakRSSBytes: 0,
            metalAllocatedBytes: 0,
            isCachedBinary: false
        )
        return finalizeCellExecution(cell: cell, outputText: combined, telemetry: tel, hadError: res.exitCode != 0)
    }

    private func executeLocalRCellAsync(_ cell: NotebookCellModel) async -> Bool {
        let rPaths = ["/opt/homebrew/bin/Rscript", "/usr/local/bin/Rscript", "/usr/bin/Rscript"]
        guard let rPath = RuntimeManager.shared.selectedExecutable(for: .r)
            ?? rPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return finalizeCellExecution(
                cell: cell,
                outputText: "❌ R is not installed. Please install R from https://cran.r-project.org/",
                hadError: true
            )
        }

        let artifactsDir = workingDirectory.appendingPathComponent("artifacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: artifactsDir, withIntermediateDirectories: true)
        let cellTag = "cell_\(cell.id.uuidString.prefix(8).lowercased())_run\(totalExecutions + 1)"

        let setupCode = """
        setwd("\(workingDirectory.path)")
        .plot_counter <- 0
        .save_plot <- function() {
            .plot_counter <<- .plot_counter + 1
            filename <- file.path("\(artifactsDir.path)", paste0("\(cellTag)_rplot_", .plot_counter, ".png"))
            dev.copy(png, filename, width = 1200, height = 840, res = 144)
            dev.off()
            cat(paste0("[IMAGE:", filename, "]\\n"))
        }

        """
        let saveCode = """

        tryCatch({
            if (dev.cur() > 1) { .save_plot() }
        }, error = function(e) {})
        """

        let tempFile = workingDirectory.appendingPathComponent("temp_script_\(UUID().uuidString.prefix(8)).R")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            try (setupCode + cell.content + saveCode).write(to: tempFile, atomically: true, encoding: .utf8)
            let isRscript = URL(fileURLWithPath: rPath).lastPathComponent.lowercased().contains("rscript")
            let args = isRscript ? ["--vanilla", tempFile.path] : ["--vanilla", "--slave", "-f", tempFile.path]
            let res = try await PolyglotStreamingAndCacheEngine.shared.runStreamingProcess(
                cellId: cell.id,
                executableURL: URL(fileURLWithPath: rPath),
                arguments: args,
                workingDirectory: workingDirectory,
                environment: buildCellProcessEnvironment(),
                onStream: { live in cell.output = live }
            )
            let tel = CellExecutionTelemetry(durationMs: res.durationMs, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false)
            return finalizeCellExecution(cell: cell, outputText: res.output, telemetry: tel, hadError: res.exitCode != 0)
        } catch {
            return finalizeCellExecution(cell: cell, outputText: "❌ Error: \(error.localizedDescription)", hadError: true)
        }
    }
    
    private func executeLocalRMarkdownCellAsync(_ cell: NotebookCellModel) async -> Bool {
        let rPaths = ["/opt/homebrew/bin/R", "/usr/local/bin/R", "/usr/bin/R"]
        guard let rPath = RuntimeManager.shared.selectedExecutable(for: .r)
            ?? rPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return finalizeCellExecution(
                cell: cell,
                outputText: "❌ R is not installed. Install R from https://cran.r-project.org/",
                hadError: true
            )
        }

        let shortId = UUID().uuidString.prefix(8)
        let tempRmd = workingDirectory.appendingPathComponent("temp_\(shortId).Rmd")
        let outputHtml = workingDirectory.appendingPathComponent("report_\(shortId).html")
        defer { try? FileManager.default.removeItem(at: tempRmd) }

        do {
            try cell.content.write(to: tempRmd, atomically: true, encoding: .utf8)
            let renderScript = "rmarkdown::render('\(tempRmd.path)', output_file = '\(outputHtml.path)', quiet = TRUE)"
            let isRscript = URL(fileURLWithPath: rPath).lastPathComponent.lowercased().contains("rscript")
            let args = isRscript ? ["-e", renderScript] : ["--slave", "-e", renderScript]
            let res = try await PolyglotStreamingAndCacheEngine.shared.runStreamingProcess(
                cellId: cell.id,
                executableURL: URL(fileURLWithPath: rPath),
                arguments: args,
                workingDirectory: workingDirectory,
                environment: buildCellProcessEnvironment(),
                onStream: { live in cell.output = live }
            )
            let tel = CellExecutionTelemetry(durationMs: res.durationMs, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false)
            if res.exitCode == 0 && FileManager.default.fileExists(atPath: outputHtml.path) {
                let htmlContent = try? String(contentsOf: outputHtml, encoding: .utf8)
                let summary = "✅ R Markdown rendered successfully!\n📄 Output: \(outputHtml.lastPathComponent)\n\nPreview:\n" + (htmlContent?.prefix(400).description ?? "")
                return finalizeCellExecution(cell: cell, outputText: summary, images: [outputHtml], telemetry: tel, hadError: false)
            }
            return finalizeCellExecution(cell: cell, outputText: "❌ R Markdown render failed:\n" + res.output, telemetry: tel, hadError: true)
        } catch {
            return finalizeCellExecution(cell: cell, outputText: "❌ Error: \(error.localizedDescription)", hadError: true)
        }
    }

    private func executeLocalLaTeXCellAsync(_ cell: NotebookCellModel) async -> Bool {
        let latexPaths = [
            "/Library/TeX/texbin/pdflatex",
            "/usr/local/texlive/2024/bin/universal-darwin/pdflatex",
            "/usr/local/texlive/2023/bin/universal-darwin/pdflatex",
            "/opt/homebrew/bin/pdflatex",
            "/usr/bin/pdflatex"
        ]
        guard let latexPath = latexPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return finalizeCellExecution(
                cell: cell,
                outputText: "❌ LaTeX is not installed. Install MacTeX from https://tug.org/mactex/",
                hadError: true
            )
        }

        let uuid = UUID().uuidString.prefix(8)
        let tempTex = workingDirectory.appendingPathComponent("temp_\(uuid).tex")
        let tempPdf = workingDirectory.appendingPathComponent("temp_\(uuid).pdf")
        defer {
            for ext in ["aux", "log", "out", "toc", "tex"] {
                try? FileManager.default.removeItem(at: workingDirectory.appendingPathComponent("temp_\(uuid).\(ext)"))
            }
        }

        do {
            try cell.content.write(to: tempTex, atomically: true, encoding: .utf8)
            let res = try await PolyglotStreamingAndCacheEngine.shared.runStreamingProcess(
                cellId: cell.id,
                executableURL: URL(fileURLWithPath: latexPath),
                arguments: ["-interaction=nonstopmode", "-output-directory=\(workingDirectory.path)", tempTex.path],
                workingDirectory: workingDirectory,
                environment: buildCellProcessEnvironment(),
                onStream: nil
            )
            let tel = CellExecutionTelemetry(durationMs: res.durationMs, memoryDeltaBytes: 0, peakRSSBytes: 0, metalAllocatedBytes: 0, isCachedBinary: false)
            if res.exitCode == 0 && FileManager.default.fileExists(atPath: tempPdf.path) {
                let summary = "✅ LaTeX compiled successfully!\n📄 PDF: \(tempPdf.lastPathComponent)"
                return finalizeCellExecution(cell: cell, outputText: summary, images: [tempPdf], telemetry: tel, hadError: false)
            }
            let logFile = workingDirectory.appendingPathComponent("temp_\(uuid).log")
            let logContent = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
            let errorLines = logContent.components(separatedBy: "\n").filter { $0.contains("!") || $0.contains("Error") }
            let errorSummary = errorLines.isEmpty ? res.output : errorLines.joined(separator: "\n")
            return finalizeCellExecution(cell: cell, outputText: "❌ LaTeX compilation failed:\n\(errorSummary)", telemetry: tel, hadError: true)
        } catch {
            return finalizeCellExecution(cell: cell, outputText: "❌ Error: \(error.localizedDescription)", hadError: true)
        }
    }

    private func executeLocalJuliaCellAsync(_ cell: NotebookCellModel) async -> Bool {
        let juliaPaths = [
            "/Applications/Julia-1.10.app/Contents/Resources/julia/bin/julia",
            "/Applications/Julia-1.9.app/Contents/Resources/julia/bin/julia",
            "/opt/homebrew/bin/julia",
            "/usr/local/bin/julia",
            "/usr/bin/julia"
        ]
        guard let juliaPath = RuntimeManager.shared.selectedExecutable(for: .julia)
            ?? juliaPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return finalizeCellExecution(
                cell: cell,
                outputText: "❌ Julia is not installed. Install from https://julialang.org/downloads/",
                hadError: true
            )
        }

        let nbId = activeNotebook?.id ?? UUID()
        let res = await LocalPersistentJuliaKernelPool.shared.execute(
            notebookId: nbId,
            cellId: cell.id,
            juliaPath: juliaPath,
            workingDirectory: workingDirectory,
            code: cell.content,
            onStream: { live in cell.output = live }
        )
        return finalizeCellExecution(cell: cell, outputText: res.output, telemetry: res.telemetry, hadError: res.hadError)
    }

    private func executeLocalSQLCellAsync(_ cell: NotebookCellModel) async -> Bool {
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

        let sqlStatements = lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("--") }
            .joined(separator: "\n")

        if !hasExplicitConnection && !SharedMemoryService.shared.sharedDataFrames.isEmpty {
            let session = activeNotebookId?.uuidString ?? "default_notebook"
            let t0 = CFAbsoluteTimeGetCurrent()
            if let result = try? await BackendService.shared.executeInMemorySQL(sessionId: session, query: sqlStatements),
               !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !result.contains("Error") {
                let tel = CellExecutionTelemetry(
                    durationMs: (CFAbsoluteTimeGetCurrent() - t0) * 1000.0,
                    memoryDeltaBytes: 0,
                    peakRSSBytes: 0,
                    metalAllocatedBytes: 0,
                    isCachedBinary: false
                )
                return finalizeCellExecution(cell: cell, outputText: result, telemetry: tel, hadError: false)
            }
        }

        // Execute in Warm Persistent Python Kernel: queries BOTH `notebook.db` AND live RAM DataFrames,
        // automatically rendering SELECT results in `NotebookInlineDataGridStudio` (`Table` | `Chart` | `Stats`)!
        let dbB64 = Data(dbPath.utf8).base64EncodedString()
        let sqlB64 = Data(sqlStatements.utf8).base64EncodedString()
        let pySQLScript = """
        import sqlite3 as _mc_sq3, base64 as _mc_sq_b64
        _mc_db_p = _mc_sq_b64.b64decode("\(dbB64)").decode("utf-8")
        _mc_sql_txt = _mc_sq_b64.b64decode("\(sqlB64)").decode("utf-8").strip()
        _mc_conn = _mc_sq3.connect(_mc_db_p)
        try:
            try:
                import pandas as _mc_pd
                _mc_existing_tbls = {r[0] for r in _mc_conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
                for _mc_vn, _mc_vv in list(globals().items()):
                    if not _mc_vn.startswith("_") and type(_mc_vv).__name__ == "DataFrame" and hasattr(_mc_vv, "to_sql") and _mc_vn not in _mc_existing_tbls:
                        try:
                            _mc_vv.to_sql(_mc_vn, _mc_conn, index=False, if_exists="replace")
                        except Exception:
                            pass
            except Exception:
                _mc_pd = None

            _mc_stmts = [s.strip() for s in _mc_sql_txt.split(";") if s.strip()]
            for _mc_idx, _mc_st in enumerate(_mc_stmts):
                _mc_upper = _mc_st.upper()
                _mc_is_query = _mc_upper.startswith("SELECT") or _mc_upper.startswith("WITH") or _mc_upper.startswith("PRAGMA")
                if _mc_is_query and _mc_idx == len(_mc_stmts) - 1 and _mc_pd is not None:
                    _mc_df_out = _mc_pd.read_sql_query(_mc_st, _mc_conn)
                    display(_mc_df_out)
                elif _mc_is_query:
                    _mc_cur = _mc_conn.execute(_mc_st)
                    _mc_rows = _mc_cur.fetchall()
                    _mc_cols = [d[0] for d in (_mc_cur.description or [])]
                    if _mc_cols:
                        print(" | ".join(_mc_cols))
                        print("-" * (len(" | ".join(_mc_cols)) + 6))
                        for _mc_r in _mc_rows[:200]:
                            print(" | ".join(str(x) for x in _mc_r))
                        print(f"\\n{len(_mc_rows)} rows returned")
                else:
                    _mc_cur = _mc_conn.execute(_mc_st)
                    _mc_conn.commit()
                    print(f"Query executed successfully. Rows affected: {_mc_cur.rowcount}")
        finally:
            _mc_conn.close()
        """

        let nbId = activeNotebook?.id ?? UUID()
        let rawPython = PythonEnvManager.shared.activeEnvironment?.pythonPath ?? selectedPythonPath
        let resolvedPython = PythonEnvManager.shared.resolveExecutablePath(rawPython)
        let kernel = LocalPersistentPythonKernelPool.shared.kernel(
            for: nbId,
            pythonPath: resolvedPython,
            workingDirectory: workingDirectory
        )
        let outcome = await kernel.executeCell(
            cellId: cell.id,
            executionIndex: totalExecutions + 1,
            code: pySQLScript
        ) { live in
            cell.output = live
        }
        return finalizeCellExecution(
            cell: cell,
            outputText: outcome.stdoutText,
            images: outcome.imageURLs,
            inlineDF: outcome.inlineDataFrame,
            telemetry: outcome.telemetry,
            hadError: outcome.hadError
        )
    }

    // MARK: - Sequential Batch Execution (Color, Tag, Downstream DAG, Run All & Kernel Lifecycle)

    func runCellsByColor(_ colorTheme: CellColorTheme, computeTarget: ComputeTarget = .localCPU) {
        guard let notebook = activeNotebook else { return }
        let cellsToRun = notebook.cells.filter {
            $0.colorTheme == colorTheme && ($0.type == .code || $0.type == .procedure)
        }
        enqueueCells(cellsToRun, computeTarget: computeTarget)
    }

    func getCellsByColor() -> [CellColorTheme: [NotebookCellModel]] {
        guard let notebook = activeNotebook else { return [:] }
        var grouped: [CellColorTheme: [NotebookCellModel]] = [:]
        for cell in notebook.cells where (cell.type == .code || cell.type == .procedure) {
            grouped[cell.colorTheme, default: []].append(cell)
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

    /// Sequentially run every runnable cell carrying the given name-tag, in deterministic order.
    func runCellsByTag(_ tag: String, computeTarget: ComputeTarget = .localCPU) {
        guard let notebook = activeNotebook else { return }
        let key = tag.trimmingCharacters(in: .whitespaces)
        let matching = notebook.cells.filter {
            ($0.type == .code || $0.type == .procedure || $0.type == .agent)
            && $0.tag.trimmingCharacters(in: .whitespaces) == key
        }
        enqueueCells(matching, computeTarget: computeTarget)
    }

    func runSelectedCell(computeTarget: ComputeTarget = .localCPU) {
        guard let notebook = activeNotebook,
              let id = selectedCellId,
              let cell = notebook.cells.first(where: { $0.id == id }) else { return }
        runCell(cell, computeTarget: computeTarget)
    }

    func runAllCells(computeTarget: ComputeTarget = .localCPU) {
        guard let notebook = activeNotebook else { return }
        let runnable = notebook.cells.filter { $0.type == .code || $0.type == .procedure }
        enqueueCells(runnable, computeTarget: computeTarget)
    }

    /// Runs `rootCell` followed by all transitive downstream cells in topological notebook order.
    func runDownstreamCells(from rootCell: NotebookCellModel, computeTarget: ComputeTarget = .localCPU) {
        guard let nb = activeNotebook else { return }
        let inputs = nb.cells.map {
            (
                id: $0.id,
                isRunnableCode: $0.type == .code || $0.type == .procedure,
                content: $0.type == .procedure ? $0.generatedCode : $0.content,
                lastRunEpoch: $0.lastRunEpoch
            )
        }
        let graph = CellLineageDAGAnalyzer.analyzeGraph(cells: inputs)
        let downstreamIds = CellLineageDAGAnalyzer.transitiveDownstreamIds(
            from: rootCell.id,
            graph: graph,
            orderedIds: nb.cells.map(\.id)
        )
        var batch: [NotebookCellModel] = [rootCell]
        for id in downstreamIds {
            if let c = nb.cells.first(where: { $0.id == id }) {
                batch.append(c)
            }
        }
        enqueueCells(batch, computeTarget: computeTarget)
    }

    func clearAllOutputs() {
        cancelExecutionQueue()
        guard let notebook = activeNotebook else { return }
        for cell in notebook.cells {
            cell.clearOutput()
            cell.executionCount = nil
            cell.lastRunEpoch = 0
        }
        scheduleAutoSave()
    }

    func restartKernel() {
        cancelExecutionQueue()
        if let nbId = activeNotebook?.id {
            LocalPersistentPythonKernelPool.shared.restart(notebookId: nbId)
            LocalPersistentJuliaKernelPool.shared.restart(notebookId: nbId)
        }
        clearAllOutputs()
        totalExecutions = 0
        globalExecutionEpoch = 0
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
        let micNotebook = MicNotebook(from: notebook)
        Task.detached(priority: .utility) {
            do {
                let encoder = JSONEncoder()
                let jsonData = try encoder.encode(micNotebook)
                let compressedData = try (jsonData as NSData).compressed(using: .lzfse)
                await NotebookPersistenceActor.shared.writeDataAtomically(compressedData as Data, to: url)
            } catch {
                print("❌ Failed to export .mic: \(error)")
            }
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
    
    // MARK: - Off-MainActor Atomic WAL Crash-Recovery Auto-Save
    
    func autoSave() {
        var allNotebooks: [[String: Any]] = []
        let iso = ISO8601DateFormatter()
        let nowStr = iso.string(from: Date())
        
        for notebook in notebooks {
            var cellsArray: [[String: Any]] = []
            for cell in notebook.cells {
                let cappedOutput = cell.output.count > 64_000
                    ? String(cell.output.suffix(64_000))
                    : cell.output
                var cellDict: [String: Any] = [
                    "type": cell.type.rawValue,
                    "language": cell.language.rawValue,
                    "content": cell.content,
                    "output": cappedOutput,
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
                "created_at": iso.string(from: notebook.createdAt),
                "modified_at": nowStr
            ])
        }
        
        let payload: [String: Any] = [
            "notebooks": allNotebooks,
            "active_id": activeNotebookId?.uuidString ?? ""
        ]
        Task {
            await NotebookPersistenceActor.shared.writeWALSnapshot(payload: payload)
        }
    }
    
    func loadAutoSave() {
        let walData = NotebookPersistenceActor.shared.loadWALSnapshotSync()
            ?? UserDefaults.standard.data(forKey: "microcode_notebooks_autosave")
        guard let data = walData,
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
    @ObservedObject private var viewModel = NotebookViewModel.shared
    @ObservedObject private var pythonEnvManager = PythonEnvManager.shared
    @ObservedObject private var cloudGPU = CloudGPUService.shared
    @ObservedObject private var sharedMemory = SharedMemoryService.shared
    @ObservedObject private var colabService = GoogleColabService.shared
    @State private var isReady = false
    @AppStorage("notebook.showAIPanel") private var showAIPanel = false
    @AppStorage("notebook.sidebarWidth") private var sidebarWidth: Double = 232
    @AppStorage("notebook.aiPanelWidth") private var aiPanelWidth: Double = 356
    @State private var sidebarDragStartWidth: CGFloat? = nil
    @State private var aiPanelDragStartWidth: CGFloat? = nil
    @State private var showingHPCSettings = false
    @State private var showingColabSettings = false
    @State private var showingExportPopover = false
    @State private var hoveredToolbarItem: String? = nil
    private let notebookHeaderHeight: CGFloat = 28
    
    private var panelBackground: Color {
        appState.appTheme.isGlass ? Color.white.opacity(0.05) : Color(nsColor: appState.appTheme.panelBackground)
    }
    
    private var controlBackground: Color {
        appState.appTheme.isGlass ? Color.white.opacity(0.08) : Color(nsColor: appState.appTheme.elevatedBackground)
    }
    
    var body: some View {
        GeometryReader { geo in
            let totalWidth = max(640, geo.size.width)
            let maxSidebarAllowed = min(320, max(180, totalWidth * 0.25))
            let effectiveSidebarW: CGFloat = viewModel.showingSidebar
                ? min(max(180, CGFloat(sidebarWidth)), maxSidebarAllowed)
                : 0
            let minCenterRequired: CGFloat = 430
            let maxAIPanelAllowed = min(560, max(280, totalWidth - effectiveSidebarW - minCenterRequired))
            let effectiveAIPanelW: CGFloat = showAIPanel
                ? min(max(280, CGFloat(aiPanelWidth)), maxAIPanelAllowed)
                : 0
            let centerWidth = max(320, totalWidth - effectiveSidebarW - effectiveAIPanelW)

            HStack(spacing: 0) {
                // Sidebar (Resizable & Responsively Clamped)
                if viewModel.showingSidebar {
                    notebookSidebar
                        .frame(width: effectiveSidebarW)

                    NotebookVerticalResizeHandle { translationX, isEnded in
                        let start = sidebarDragStartWidth ?? effectiveSidebarW
                        if sidebarDragStartWidth == nil { sidebarDragStartWidth = start }
                        let proposed = min(max(180, start + translationX), maxSidebarAllowed)
                        sidebarWidth = Double(proposed)
                        if isEnded { sidebarDragStartWidth = nil }
                    }
                }
                
                // Main Content
                VStack(spacing: 0) {
                    notebookToolbar(availableWidth: centerWidth)
                    
                    Divider()

                    if viewModel.showVariableInspector {
                        let activeVars = sharedMemory.activeVariables(for: viewModel.activeNotebookId)
                        let memPair = viewModel.activeNotebookId.flatMap { sharedMemory.kernelMemoryByNotebook[$0] } ?? (0, 0)
                        NotebookVariableInspectorBar(
                            variables: activeVars,
                            rssBytes: memPair.rssBytes,
                            metalBytes: memPair.metalBytes,
                            isDark: appState.appTheme.isDark,
                            onInspectVariable: { v in
                                viewModel.addCell(type: .code, language: .python)
                                if let lastCell = viewModel.activeNotebook?.cells.last {
                                    lastCell.content = v.name
                                    viewModel.runCell(lastCell, computeTarget: appState.currentComputeTarget)
                                }
                            },
                            onPinToSHM: { v in
                                viewModel.addCell(type: .code, language: .python)
                                if let lastCell = viewModel.activeNotebook?.cells.last {
                                    lastCell.content = "shm.set(\"\(v.name)\", \(v.name))\nprint(\"Pinned \(v.name) to Zero-Copy POSIX SHM:\", shm.list())"
                                    viewModel.runCell(lastCell, computeTarget: appState.currentComputeTarget)
                                }
                                let sid = viewModel.activeNotebookId?.uuidString ?? "default_notebook"
                                Task {
                                    try? await Task.sleep(nanoseconds: 650_000_000)
                                    await SharedMemoryService.shared.refreshList(sessionId: sid)
                                }
                            },
                            onSendToAgent: { v in
                                if !showAIPanel {
                                    withAnimation(.easeInOut(duration: 0.16)) { showAIPanel = true }
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    NotificationCenter.default.post(
                                        name: Notification.Name("InsertNotebookAgentMention"),
                                        object: nil,
                                        userInfo: ["mention": "@\(v.name)"]
                                    )
                                }
                            },
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    viewModel.showVariableInspector = false
                                }
                            }
                        )
                        Divider()
                    }
                    
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
                .frame(minWidth: 320, maxWidth: .infinity)
                
                // AI Agent Panel (Right Side — Draggable & Responsively Clamped)
                if showAIPanel {
                    NotebookVerticalResizeHandle { translationX, isEnded in
                        let start = aiPanelDragStartWidth ?? effectiveAIPanelW
                        if aiPanelDragStartWidth == nil { aiPanelDragStartWidth = start }
                        // Dragging left (negative translationX) widens the right panel
                        let proposed = min(max(280, start - translationX), maxAIPanelAllowed)
                        aiPanelWidth = Double(proposed)
                        if isEnded { aiPanelDragStartWidth = nil }
                    }

                    NotebookAIPanel(
                        viewModel: viewModel,
                        isShowing: $showAIPanel
                    )
                    .frame(width: effectiveAIPanelW)
                    .transition(.move(edge: .trailing))
                }
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
            if appState.editorMode == .science, let workspace = appState.workspaceFolder {
                viewModel.configureScientificProject(workspace)
                viewModel.syncScientificFiles(from: workspace)
            }
            Task {
                await SharedMemoryService.shared.refreshList(sessionId: viewModel.activeNotebookId?.uuidString ?? "default_notebook")
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

            let langStr = notification.userInfo?["language"] as? String ?? ""
            let mode = notification.userInfo?["mode"] as? String ?? "insert"
            let autoRun = notification.userInfo?["autoRun"] as? Bool ?? false
            let language = CellLanguage.from(fenceTag: langStr)
                ?? viewModel.activeNotebook?.cells.first(where: { $0.id == viewModel.selectedCellId })?.language
                ?? viewModel.activeNotebook?.cells.last?.language
                ?? .python

            if mode == "replace_selected",
               let selId = viewModel.selectedCellId,
               let selectedCell = viewModel.activeNotebook?.cells.first(where: { $0.id == selId }),
               selectedCell.type == .code {
                selectedCell.recordAgentEditBaseline(previousContent: selectedCell.content, source: "Notebook Agent")
                selectedCell.language = language
                selectedCell.content = code
                viewModel.scheduleAutoSave()
                if autoRun {
                    viewModel.runCell(selectedCell)
                }
            } else {
                viewModel.addCell(type: .code, language: language)
                if let newId = viewModel.selectedCellId,
                   let newCell = viewModel.activeNotebook?.cells.first(where: { $0.id == newId }) {
                    newCell.content = code
                    viewModel.scheduleAutoSave()
                    if autoRun {
                        viewModel.runCell(newCell)
                    }
                }
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
            // Header — aligned 28pt executive top bar matching Notebook Toolbar & Agent Panel
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text("Cell Sheets")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.92))
                Spacer()
                
                Button(action: { viewModel.createNotebook() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(hoveredToolbarItem == "new_sheet" ? .primary : .secondary)
                        .frame(width: 22, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4.5)
                                .fill(hoveredToolbarItem == "new_sheet" ? Color.primary.opacity(appState.appTheme.isDark ? 0.09 : 0.06) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in hoveredToolbarItem = h ? "new_sheet" : (hoveredToolbarItem == "new_sheet" ? nil : hoveredToolbarItem) }
                .help("New Cell Sheet")
            }
            .padding(.horizontal, 10)
            .frame(height: notebookHeaderHeight)
            .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))
            
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
    
    // MARK: - Toolbar (100% Bezel-Free Native Executive Header)
    
    private var isDarkToolbar: Bool {
        appState.appTheme.isDark
    }
    
    private func toolbarPillFill(id: String, active: Bool = false) -> Color {
        if active {
            return Color.primary.opacity(isDarkToolbar ? 0.115 : 0.08)
        }
        if hoveredToolbarItem == id {
            return Color.primary.opacity(isDarkToolbar ? 0.085 : 0.058)
        }
        return Color.primary.opacity(isDarkToolbar ? 0.045 : 0.03)
    }
    
    private func toolbarPillStroke(id: String, active: Bool = false) -> Color {
        if active {
            return Color.primary.opacity(isDarkToolbar ? 0.22 : 0.16)
        }
        if hoveredToolbarItem == id {
            return Color.primary.opacity(isDarkToolbar ? 0.16 : 0.12)
        }
        return Color.primary.opacity(isDarkToolbar ? 0.10 : 0.07)
    }
    
    @ViewBuilder
    private func toolbarIconButton(
        id: String,
        icon: String,
        tooltip: String,
        tint: Color? = nil,
        active: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredToolbarItem == id && !disabled
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(
                    disabled
                        ? .secondary.opacity(0.32)
                        : (tint ?? (active || isHovered ? .primary : .secondary))
                )
                .frame(width: 22, height: 21)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            active
                                ? Color.primary.opacity(isDarkToolbar ? 0.11 : 0.08)
                                : (isHovered ? Color.primary.opacity(isDarkToolbar ? 0.085 : 0.055) : Color.clear)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(
                            active
                                ? Color.primary.opacity(isDarkToolbar ? 0.20 : 0.14)
                                : Color.clear,
                            lineWidth: 0.8
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .fixedSize()
        .onHover { h in
            hoveredToolbarItem = h ? id : (hoveredToolbarItem == id ? nil : hoveredToolbarItem)
        }
        .help(tooltip)
    }
    
    private func notebookToolbar(availableWidth: CGFloat) -> some View {
        let isCompact = availableWidth < 760
        let isUltraCompact = availableWidth < 580
        let maxTitleWidth: CGFloat = availableWidth > 820 ? 200 : (availableWidth > 640 ? 132 : 92)

        return HStack(spacing: isCompact ? 4 : 5.5) {
            // Sidebar toggle
            toolbarIconButton(
                id: "toggle_sidebar",
                icon: "sidebar.left",
                tooltip: "Toggle Cell Sheets Sidebar",
                tint: viewModel.showingSidebar ? .primary.opacity(0.88) : nil
            ) {
                withAnimation(.easeInOut(duration: 0.16)) {
                    viewModel.showingSidebar.toggle()
                }
            }
            
            Divider().frame(height: 13).opacity(0.65)
            
            // Notebook Name (responsive width, never crushed prematurely)
            if let notebook = viewModel.activeNotebook {
                if viewModel.isEditingName {
                    TextField("Name", text: Binding(
                        get: { notebook.name },
                        set: { notebook.name = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 5)
                    .frame(height: 20)
                    .frame(maxWidth: maxTitleWidth)
                    .background(Color.primary.opacity(isDarkToolbar ? 0.08 : 0.05))
                    .cornerRadius(4)
                    .onSubmit { viewModel.isEditingName = false }
                } else {
                    HStack(spacing: 3) {
                        Text(notebook.name)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.93))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(minWidth: isUltraCompact ? 46 : 68, maxWidth: maxTitleWidth, alignment: .leading)
                            .layoutPriority(2)
                            .onTapGesture(count: 2) {
                                viewModel.isEditingName = true
                            }
                        
                        Button(action: { viewModel.isEditingName.toggle() }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(hoveredToolbarItem == "rename_nb" ? .primary : .secondary.opacity(0.75))
                                .frame(width: 17, height: 19)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(hoveredToolbarItem == "rename_nb" ? Color.primary.opacity(isDarkToolbar ? 0.08 : 0.05) : Color.clear)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .onHover { h in
                            hoveredToolbarItem = h ? "rename_nb" : (hoveredToolbarItem == "rename_nb" ? nil : hoveredToolbarItem)
                        }
                        .help("Rename Cell Sheet")
                    }
                }
            }
            
            Divider().frame(height: 13).opacity(0.65)
            
            // Python Kernel / Virtual Environment Selector Pill (compact, zero AppKit bezel)
            pythonVersionPill(isCompact: isCompact, isUltraCompact: isUltraCompact)
            
            // Unified Segmented Action Capsule: [ + | ▶ | ▶▶ ▾ ]
            cellExecutionCapsule

            // Reactive DAG Mode Pill (⚡ Auto-runs downstream dependent cells)
            Button(action: { viewModel.isReactiveMode.toggle() }) {
                HStack(spacing: 3.5) {
                    Image(systemName: viewModel.isReactiveMode ? "bolt.fill" : "bolt")
                        .font(.system(size: 9.5, weight: .semibold))
                    if !isCompact {
                        Text("DAG")
                            .font(.system(size: 10, weight: viewModel.isReactiveMode ? .semibold : .medium))
                            .lineLimit(1)
                    }
                }
                .foregroundColor(viewModel.isReactiveMode ? .orange : (hoveredToolbarItem == "reactive_dag" ? .primary : .secondary))
                .padding(.horizontal, isCompact ? 5.5 : 6.5)
                .frame(height: 21)
                .background(
                    viewModel.isReactiveMode
                        ? Color.orange.opacity(isDarkToolbar ? 0.16 : 0.11)
                        : toolbarPillFill(id: "reactive_dag")
                )
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(
                            viewModel.isReactiveMode
                                ? Color.orange.opacity(0.45)
                                : toolbarPillStroke(id: "reactive_dag"),
                            lineWidth: 0.8
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .onHover { h in
                hoveredToolbarItem = h ? "reactive_dag" : (hoveredToolbarItem == "reactive_dag" ? nil : hoveredToolbarItem)
            }
            .help("Reactive DAG Mode: Automatically re-run downstream dependent cells when an upstream variable changes")
            
            Spacer(minLength: 4)
            
            // --- Right side: compute, open, export, count, AI ---
            
            computeEnginePill(isCompact: isCompact, isUltraCompact: isUltraCompact)
            
            // Google Colab Cloud GPU Status & Settings
            if appState.currentComputeTarget == .googleColab {
                Button(action: { showingColabSettings = true }) {
                    HStack(spacing: 4.5) {
                        Circle()
                            .fill(colabService.status.statusColor)
                            .frame(width: 6, height: 6)
                        
                        if !isUltraCompact {
                            Text(colabService.status.isConnected ? colabService.detectedGPU : "Colab")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundColor(colabService.status.isConnected ? .green : .primary.opacity(0.9))
                                .lineLimit(1)
                        }
                        
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6.5)
                    .frame(height: 21)
                    .background(toolbarPillFill(id: "colab_cfg"))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(toolbarPillStroke(id: "colab_cfg"), lineWidth: 0.8)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .onHover { h in
                    hoveredToolbarItem = h ? "colab_cfg" : (hoveredToolbarItem == "colab_cfg" ? nil : hoveredToolbarItem)
                }
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
                let activeServer = appState.selectedSSHComputeServer ?? RemoteConnectionManager.shared.currentConnection ?? RemoteConnectionManager.shared.servers.first
                Button(action: presentSSHServerMenu) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(activeServer != nil ? Color.green : Color.secondary)
                            .frame(width: 5.5, height: 5.5)
                        Text(activeServer?.name ?? "Auto SSH")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.9))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6.5)
                    .frame(height: 21)
                    .background(toolbarPillFill(id: "ssh_srv"))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(toolbarPillStroke(id: "ssh_srv"), lineWidth: 0.8)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .onHover { h in
                    hoveredToolbarItem = h ? "ssh_srv" : (hoveredToolbarItem == "ssh_srv" ? nil : hoveredToolbarItem)
                }
                .help("Active SSH Compute Server (Auto-synced with Remote Explorer)")
                
                if !isCompact {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text("Auto ENV")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 5.5)
                    .frame(height: 21)
                    .background(Color.green.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                    .help("Remote Python Environment: Auto venv (~/.microcode/venv) with on-demand package installation")
                }
            }
            
            if appState.currentComputeTarget == .customHPC {
                toolbarIconButton(
                    id: "hpc_cfg",
                    icon: "gearshape.fill",
                    tooltip: "MicroCode Cloud — advanced settings",
                    tint: .blue
                ) {
                    showingHPCSettings = true
                }
                .popover(isPresented: $showingHPCSettings, arrowEdge: .bottom) {
                    HPCSettingsView()
                        .environmentObject(appState)
                }
            }
            
            // GPU Wallet — deliberately separate from AI-token balance.
            if appState.currentComputeTarget.isPremium {
                HStack(spacing: 2.5) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text(cloudGPU.balanceText)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 5.5)
                .frame(height: 21)
                .background(Color.yellow.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                .help("Cloud GPU Wallet: \(cloudGPU.balanceText). This is separate from AI tokens.")
            }
            
            // Live Kernel Variable & Unified/Metal Memory Inspector Toggle
            let liveVarCount = sharedMemory.activeVariables(for: viewModel.activeNotebookId).count
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.showVariableInspector.toggle()
                }
            }) {
                HStack(spacing: 3.5) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 10, weight: .medium))
                    if liveVarCount > 0 {
                        Text("\(liveVarCount)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    } else if !isCompact {
                        Text("Vars")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .foregroundColor(
                    viewModel.showVariableInspector
                        ? .green
                        : (hoveredToolbarItem == "vars_inspector" ? .primary : (liveVarCount > 0 ? .green.opacity(0.9) : .secondary))
                )
                .padding(.horizontal, 6)
                .frame(height: 21)
                .background(
                    viewModel.showVariableInspector
                        ? Color.green.opacity(isDarkToolbar ? 0.15 : 0.11)
                        : toolbarPillFill(id: "vars_inspector")
                )
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(
                            viewModel.showVariableInspector
                                ? Color.green.opacity(0.42)
                                : toolbarPillStroke(id: "vars_inspector"),
                            lineWidth: 0.8
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .onHover { h in
                hoveredToolbarItem = h ? "vars_inspector" : (hoveredToolbarItem == "vars_inspector" ? nil : hoveredToolbarItem)
            }
            .help("Toggle Live Kernel Variable & Apple Silicon Unified/Metal Memory Inspector")

            // 1-Click Executive App / Dashboard Presentation Mode Toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.16)) {
                    viewModel.isAppPresentationMode.toggle()
                }
            }) {
                HStack(spacing: 3.5) {
                    Image(systemName: viewModel.isAppPresentationMode ? "sparkles.tv.fill" : "sparkles.tv")
                        .font(.system(size: 10, weight: .medium))
                    if !isCompact {
                        Text("App")
                            .font(.system(size: 10, weight: viewModel.isAppPresentationMode ? .semibold : .medium))
                            .lineLimit(1)
                    }
                }
                .foregroundColor(
                    viewModel.isAppPresentationMode
                        ? .accentColor
                        : (hoveredToolbarItem == "app_mode" ? .primary : .secondary)
                )
                .padding(.horizontal, isCompact ? 5.5 : 6)
                .frame(height: 21)
                .background(toolbarPillFill(id: "app_mode", active: viewModel.isAppPresentationMode))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(toolbarPillStroke(id: "app_mode", active: viewModel.isAppPresentationMode), lineWidth: 0.8)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .onHover { h in
                hoveredToolbarItem = h ? "app_mode" : (hoveredToolbarItem == "app_mode" ? nil : hoveredToolbarItem)
            }
            .help("Toggle Executive App / Dashboard Presentation Mode (hides raw code, shows Markdown, @param widgets, DataGrids & plots)")

            // Open Notebook
            toolbarIconButton(
                id: "open_nb",
                icon: "folder",
                tooltip: "Open Notebook (.mic / .ipynb)"
            ) {
                openNotebookFile()
            }
            
            // Export Notebook (persistent popover with clean theme-matched rows)
            toolbarIconButton(
                id: "export_nb",
                icon: "square.and.arrow.down",
                tooltip: "Export Notebook (.mic / .ipynb)",
                active: showingExportPopover
            ) {
                showingExportPopover.toggle()
            }
            .popover(isPresented: $showingExportPopover, arrowEdge: .bottom) {
                exportNotebookPopover
            }
            
            Divider().frame(height: 13).opacity(0.65)
            
            // Execution count (compact 21pt badge)
            if !isUltraCompact {
                Text("\(viewModel.totalExecutions)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 5.5)
                    .frame(height: 21)
                    .background(Color.primary.opacity(isDarkToolbar ? 0.05 : 0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .stroke(Color.primary.opacity(isDarkToolbar ? 0.09 : 0.06), lineWidth: 0.7)
                    )
                    .help("Total Executions: \(viewModel.totalExecutions)")
            }
            
            // Show compact AI Model Selector in toolbar only when the right Agent Panel is closed
            if !showAIPanel && !isCompact {
                CellAIModelSelectorPill(
                    selection: nil,
                    showRoleSelector: false,
                    maxWidth: min(165, availableWidth * 0.24),
                    compact: true,
                    minimalChrome: true
                )
            }

            // Formal AI Agent Panel Toggle
            Button(action: { withAnimation(.easeInOut(duration: 0.16)) { showAIPanel.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 10.5, weight: .medium))
                    if !isUltraCompact {
                        Text("Agent")
                            .font(.system(size: 10.5, weight: showAIPanel ? .semibold : .medium))
                            .lineLimit(1)
                    }
                }
                .foregroundColor(showAIPanel || hoveredToolbarItem == "toggle_agent" ? .primary : .secondary)
                .padding(.horizontal, isUltraCompact ? 6 : 7.5)
                .frame(height: 21)
                .background(toolbarPillFill(id: "toggle_agent", active: showAIPanel))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(toolbarPillStroke(id: "toggle_agent", active: showAIPanel), lineWidth: 0.8)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .onHover { h in
                hoveredToolbarItem = h ? "toggle_agent" : (hoveredToolbarItem == "toggle_agent" ? nil : hoveredToolbarItem)
            }
            .help("Toggle Notebook Agent Panel")
        }
        .padding(.horizontal, 10)
        .frame(height: notebookHeaderHeight)
        .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground))
    }
    
    // MARK: - Unified Cell & Execution Action Capsule ([ + | ▶ | ▶▶ ▾ ])
    
    private var cellExecutionCapsule: some View {
        let canRunSelected = viewModel.selectedCellId != nil
        let dividerColor = Color.primary.opacity(isDarkToolbar ? 0.11 : 0.08)
        
        return HStack(spacing: 0) {
            // 1. Add Cell (+)
            Button(action: presentAddCellMenu) {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(hoveredToolbarItem == "add_cell" ? .primary : .primary.opacity(0.82))
                    .frame(width: 24, height: 21)
                    .background(
                        hoveredToolbarItem == "add_cell"
                            ? Color.primary.opacity(isDarkToolbar ? 0.10 : 0.07)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { h in
                hoveredToolbarItem = h ? "add_cell" : (hoveredToolbarItem == "add_cell" ? nil : hoveredToolbarItem)
            }
            .help("Add Cell")
            
            Rectangle().fill(dividerColor).frame(width: 0.8, height: 13)
            
            // 2. Run Selected Cell (▶)
            Button(action: { viewModel.runSelectedCell(computeTarget: appState.currentComputeTarget) }) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(
                        canRunSelected
                            ? (hoveredToolbarItem == "run_sel" ? .green : .green.opacity(0.88))
                            : .secondary.opacity(0.32)
                    )
                    .frame(width: 24, height: 21)
                    .background(
                        canRunSelected && hoveredToolbarItem == "run_sel"
                            ? Color.green.opacity(isDarkToolbar ? 0.14 : 0.10)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canRunSelected)
            .onHover { h in
                hoveredToolbarItem = h ? "run_sel" : (hoveredToolbarItem == "run_sel" ? nil : hoveredToolbarItem)
            }
            .help("Run Selected Cell")
            
            Rectangle().fill(dividerColor).frame(width: 0.8, height: 13)
            
            // 3. Run All Cells (▶▶)
            Button(action: { viewModel.runAllCells(computeTarget: appState.currentComputeTarget) }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(hoveredToolbarItem == "run_all" ? .green : .primary.opacity(0.85))
                    .frame(width: 25, height: 21)
                    .background(
                        hoveredToolbarItem == "run_all"
                            ? Color.green.opacity(isDarkToolbar ? 0.14 : 0.10)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { h in
                hoveredToolbarItem = h ? "run_all" : (hoveredToolbarItem == "run_all" ? nil : hoveredToolbarItem)
            }
            .help("Run All Cells")
            
            // 4. Run Filtered / Kernel Options Chevron (▾)
            Button(action: presentRunOptionsMenu) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundColor(hoveredToolbarItem == "run_opts" ? .primary : .secondary.opacity(0.8))
                    .frame(width: 15, height: 21)
                    .background(
                        hoveredToolbarItem == "run_opts"
                            ? Color.primary.opacity(isDarkToolbar ? 0.10 : 0.07)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { h in
                hoveredToolbarItem = h ? "run_opts" : (hoveredToolbarItem == "run_opts" ? nil : hoveredToolbarItem)
            }
            .help("Run by Color / Tag & Kernel Actions")
        }
        .frame(height: 21)
        .background(Color.primary.opacity(isDarkToolbar ? 0.048 : 0.032))
        .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .stroke(Color.primary.opacity(isDarkToolbar ? 0.12 : 0.085), lineWidth: 0.8)
        )
        .fixedSize()
    }
    
    // MARK: - Python Environment & Compute Engine Pills
    
    private func pythonVersionPill(isCompact: Bool, isUltraCompact: Bool) -> some View {
        let maxW: CGFloat = isUltraCompact ? 96 : (isCompact ? 126 : 158)
        return Button(action: presentPythonVersionMenu) {
            HStack(spacing: 4.5) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.green)
                Text(currentPythonDisplay)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.primary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: maxW)
            .frame(height: 21)
            .background(toolbarPillFill(id: "py_env"))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(toolbarPillStroke(id: "py_env"), lineWidth: 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .onHover { h in
            hoveredToolbarItem = h ? "py_env" : (hoveredToolbarItem == "py_env" ? nil : hoveredToolbarItem)
        }
        .help("Select Python Interpreter or Virtual Environment (\(currentPythonDisplay))")
    }
    
    private func computeEnginePill(isCompact: Bool, isUltraCompact: Bool) -> some View {
        let target = appState.currentComputeTarget
        let isRemoteCompute = (target == .yourCloud || target == .googleColab || target.isPremium)
        let iconTint: Color = target == .yourCloud ? .green : (target.isPremium ? .orange : .secondary)
        return Button(action: presentComputeEngineMenu) {
            HStack(spacing: 4) {
                Image(systemName: target.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(hoveredToolbarItem == "compute_target" && !isRemoteCompute ? .primary : iconTint)
                if !isUltraCompact {
                    if target == .yourCloud {
                        Text("Your Cloud")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.primary.opacity(0.9))
                            .lineLimit(1)
                    } else if target == .googleColab {
                        Text("Colab")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.primary.opacity(0.9))
                            .lineLimit(1)
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 6.5)
            .frame(height: 21)
            .background(toolbarPillFill(id: "compute_target", active: isRemoteCompute))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(toolbarPillStroke(id: "compute_target", active: isRemoteCompute), lineWidth: 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { h in
            hoveredToolbarItem = h ? "compute_target" : (hoveredToolbarItem == "compute_target" ? nil : hoveredToolbarItem)
        }
        .help("Select Compute Engine: \(target.displayName)")
    }
    
    private var exportNotebookPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Notebook")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Save .mic, Jupyter .ipynb, or clean Python script")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button { showingExportPopover = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            Divider()
            exportActionRow(id: "exp_quick", title: "Quick Save (.mic)", shortcutHint: "⌘S", icon: "bolt.fill") {
                viewModel.quickSave()
                showingExportPopover = false
            }
            .keyboardShortcut("s", modifiers: .command)
            
            exportActionRow(id: "exp_saveas", title: "Save As… (.mic)", shortcutHint: "⇧⌘S", icon: "square.and.arrow.down") {
                showingExportPopover = false
                viewModel.saveAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            
            exportActionRow(id: "exp_ipynb", title: "Export as Jupyter (.ipynb)", shortcutHint: nil, icon: "arrow.up.forward.square") {
                showingExportPopover = false
                viewModel.exportIpynb()
            }
            
            exportActionRow(id: "exp_py", title: "Export as Git-Clean Script (.py # %%)", shortcutHint: nil, icon: "doc.text.fill") {
                showingExportPopover = false
                viewModel.exportPlainPythonScript()
            }
            
            exportActionRow(id: "exp_colab", title: "Open in Google Colab", shortcutHint: nil, icon: "sparkles.rectangle.stack") {
                showingExportPopover = false
                if let nb = viewModel.activeNotebook {
                    colabService.openColabInBrowser(notebook: nb)
                }
            }
            Divider()
            Text(viewModel.lastAutoSave.map { "Autosaved \($0.formatted(date: .omitted, time: .standard))" } ?? "Autosave active")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(width: 288)
    }
    
    @ViewBuilder
    private func exportActionRow(
        id: String,
        title: String,
        shortcutHint: String?,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        let hovered = hoveredToolbarItem == id
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(hovered ? .accentColor : .secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                if let shortcutHint {
                    Text(shortcutHint)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovered ? Color.primary.opacity(isDarkToolbar ? 0.09 : 0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            hoveredToolbarItem = h ? id : (hoveredToolbarItem == id ? nil : hoveredToolbarItem)
        }
    }
    
    // MARK: - Native NSMenu Popups (Zero AppKit Bezel Bleed)
    
    private func makeMenuHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
    
    private func makeMenuActionItem(
        _ title: String,
        icon: String? = nil,
        checked: Bool = false,
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(ClosureMenuActionHandler.performMenuAction(_:)),
            keyEquivalent: ""
        )
        item.target = ClosureMenuActionHandler.shared
        item.representedObject = action
        item.state = checked ? .on : .off
        if let icon, let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            item.image = img
        }
        return item
    }
    
    private func presentAddCellMenu() {
        let menu = NSMenu(title: "Add Cell")
        menu.autoenablesItems = false
        
        menu.addItem(makeMenuHeader("Code Cells"))
        menu.addItem(makeMenuActionItem("Python", icon: "p.circle.fill") { viewModel.addCell(type: .code, language: .python) })
        menu.addItem(makeMenuActionItem("R", icon: "r.circle.fill") { viewModel.addCell(type: .code, language: .r) })
        menu.addItem(makeMenuActionItem("Julia", icon: "j.circle.fill") { viewModel.addCell(type: .code, language: .julia) })
        menu.addItem(makeMenuActionItem("SQL", icon: "cylinder.fill") { viewModel.addCell(type: .code, language: .sql) })
        
        menu.addItem(.separator())
        menu.addItem(makeMenuHeader("Compiled"))
        menu.addItem(makeMenuActionItem("Ardium", icon: "sparkles") { viewModel.addCell(type: .code, language: .ardium) })
        menu.addItem(makeMenuActionItem("Rust", icon: "gearshape.fill") { viewModel.addCell(type: .code, language: .rust) })
        menu.addItem(makeMenuActionItem("Go", icon: "g.circle.fill") { viewModel.addCell(type: .code, language: .go) })
        menu.addItem(makeMenuActionItem("C++", icon: "c.circle.fill") { viewModel.addCell(type: .code, language: .cpp) })
        menu.addItem(makeMenuActionItem("Objective-C", icon: "apple.logo") { viewModel.addCell(type: .code, language: .objc) })
        
        menu.addItem(.separator())
        menu.addItem(makeMenuHeader("Documents"))
        menu.addItem(makeMenuActionItem("Markdown", icon: "text.alignleft") { viewModel.addCell(type: .markdown) })
        menu.addItem(makeMenuActionItem("R Markdown", icon: "doc.richtext.fill") { viewModel.addCell(type: .code, language: .rmarkdown) })
        menu.addItem(makeMenuActionItem("LaTeX", icon: "function") { viewModel.addCell(type: .code, language: .latex) })
        menu.addItem(makeMenuActionItem("Raw Text", icon: "doc.plaintext") { viewModel.addCell(type: .raw) })
        
        menu.addItem(.separator())
        menu.addItem(makeMenuHeader("Autonomous & Analytics"))
        menu.addItem(makeMenuActionItem("AI Agent Cell", icon: "brain.head.profile") { viewModel.addCell(type: .agent) })
        menu.addItem(makeMenuActionItem("SAS Procedure", icon: "tablecells.fill") { viewModel.addCell(type: .procedure) })
        
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    private func presentRunOptionsMenu() {
        let menu = NSMenu(title: "Run Options")
        menu.autoenablesItems = false
        
        menu.addItem(makeMenuActionItem("Run All Cells", icon: "forward.fill") {
            viewModel.runAllCells(computeTarget: appState.currentComputeTarget)
        })
        if let selId = viewModel.selectedCellId,
           let selCell = viewModel.activeNotebook?.cells.first(where: { $0.id == selId }) {
            menu.addItem(makeMenuActionItem("Run Selected Cell", icon: "play.fill") {
                viewModel.runSelectedCell(computeTarget: appState.currentComputeTarget)
            })
            menu.addItem(makeMenuActionItem("Run Selected + Downstream Cells (DAG)", icon: "arrow.turn.right.down") {
                viewModel.runDownstreamCells(from: selCell, computeTarget: appState.currentComputeTarget)
            })
        }
        menu.addItem(makeMenuActionItem("Reactive DAG Auto-Run Mode", icon: "bolt.fill", checked: viewModel.isReactiveMode) {
            viewModel.isReactiveMode.toggle()
        })
        
        let usedColors = viewModel.getUsedColors().filter { $0 != .none }
        if !usedColors.isEmpty {
            let colorSub = NSMenu(title: "Run by Color")
            colorSub.autoenablesItems = false
            for theme in usedColors {
                colorSub.addItem(makeMenuActionItem(theme.rawValue.capitalized, icon: "circle.fill") {
                    viewModel.runCellsByColor(theme, computeTarget: appState.currentComputeTarget)
                })
            }
            let parent = NSMenuItem(title: "Run by Color", action: nil, keyEquivalent: "")
            parent.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
            parent.submenu = colorSub
            menu.addItem(parent)
        }
        
        let usedTags = viewModel.getUsedTags()
        if !usedTags.isEmpty {
            let tagSub = NSMenu(title: "Run by Tag")
            tagSub.autoenablesItems = false
            for tag in usedTags {
                tagSub.addItem(makeMenuActionItem(tag, icon: "tag.fill") {
                    viewModel.runCellsByTag(tag, computeTarget: appState.currentComputeTarget)
                })
            }
            let parent = NSMenuItem(title: "Run by Tag", action: nil, keyEquivalent: "")
            parent.image = NSImage(systemSymbolName: "tag", accessibilityDescription: nil)
            parent.submenu = tagSub
            menu.addItem(parent)
        }
        
        menu.addItem(.separator())
        menu.addItem(makeMenuActionItem("Clear All Outputs", icon: "trash") {
            viewModel.clearAllOutputs()
        })
        menu.addItem(makeMenuActionItem("Restart Kernel", icon: "arrow.clockwise") {
            viewModel.restartKernel()
        })
        
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    private func presentPythonVersionMenu() {
        let menu = NSMenu(title: "Python Environment")
        menu.autoenablesItems = false
        
        menu.addItem(makeMenuHeader("Python Interpreter"))
        if appState.availablePythonVersions.isEmpty {
            let isSys = pythonEnvManager.activeEnvironment == nil
            menu.addItem(makeMenuActionItem("python3 (System Default)", icon: "terminal", checked: isSys) {
                appState.selectedPythonVersion = "python3"
                viewModel.selectedPythonPath = PythonEnvManager.shared.systemPythonExecutable
                pythonEnvManager.activeEnvironment = nil
            })
        } else {
            for version in appState.availablePythonVersions {
                let isChecked = pythonEnvManager.activeEnvironment == nil && appState.selectedPythonVersion == version.path
                menu.addItem(makeMenuActionItem(version.displayName, icon: "cpu", checked: isChecked) {
                    appState.selectedPythonVersion = version.path
                    viewModel.selectedPythonPath = version.path
                    pythonEnvManager.activeEnvironment = nil
                })
            }
        }
        
        if !pythonEnvManager.environments.isEmpty {
            menu.addItem(.separator())
            menu.addItem(makeMenuHeader("Virtual Environments"))
            for env in pythonEnvManager.environments {
                let isChecked = pythonEnvManager.activeEnvironment?.id == env.id
                menu.addItem(makeMenuActionItem("venv: \(env.name)", icon: "shippingbox.fill", checked: isChecked) {
                    pythonEnvManager.activateEnvironment(env)
                    viewModel.selectedPythonPath = env.pythonPath
                })
            }
        }
        
        menu.addItem(.separator())
        menu.addItem(makeMenuActionItem("Manage Python Environments…", icon: "slider.horizontal.3") {
            let allCode = (viewModel.activeNotebook?.cells ?? [])
                .filter { $0.type == .code }
                .map { $0.content }
                .joined(separator: "\n")
            _ = pythonEnvManager.detectImportsFromCode(allCode)
            appState.showingPythonEnv = true
        })
        
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    private func presentComputeEngineMenu() {
        let menu = NSMenu(title: "Compute Engine")
        menu.autoenablesItems = false
        menu.addItem(makeMenuHeader("Compute Engine"))
        
        for target in ComputeTarget.userSelectable {
            let title = target.isPremium ? "\(target.displayName)  ★" : target.displayName
            let isChecked = appState.currentComputeTarget == target
            menu.addItem(makeMenuActionItem(title, icon: target.icon, checked: isChecked) {
                appState.currentComputeTarget = target
            })
        }
        
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    private func presentSSHServerMenu() {
        let menu = NSMenu(title: "Synced SSH Servers")
        menu.autoenablesItems = false
        menu.addItem(makeMenuHeader("Synced SSH Servers"))
        
        let servers = RemoteConnectionManager.shared.servers
        if servers.isEmpty {
            menu.addItem(makeMenuHeader("No SSH servers configured"))
        } else {
            for s in servers {
                let isSel = (appState.selectedSSHComputeServer?.id ?? RemoteConnectionManager.shared.currentConnection?.id ?? servers.first?.id) == s.id
                menu.addItem(makeMenuActionItem("\(s.name) (\(s.username)@\(s.host))", icon: "server.rack", checked: isSel) {
                    appState.selectedSSHComputeServer = s
                    RemoteConnectionManager.shared.currentConnection = s
                })
            }
        }
        
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
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
    @ObservedObject private var sharedMemory = SharedMemoryService.shared
    @EnvironmentObject var appState: AppState

    private var controlBackground: Color {
        appState.appTheme.isGlass ? Color.white.opacity(0.08) : Color(nsColor: appState.appTheme.elevatedBackground)
    }

    var body: some View {
        let dagGraph = CellLineageDAGAnalyzer.analyzeGraph(
            cells: notebook.cells.map { c in
                (
                    id: c.id,
                    isRunnableCode: c.type == .code || c.type == .procedure,
                    content: c.type == .procedure ? c.generatedCode : c.content,
                    lastRunEpoch: c.lastRunEpoch
                )
            }
        )
        let liveVars = sharedMemory.activeVariables(for: notebook.id)

        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(notebook.cells) { cell in
                    NotebookCellView(
                        cell: cell,
                        isSelected: viewModel.selectedCellId == cell.id,
                        dagInfo: dagGraph[cell.id],
                        liveVariables: liveVars,
                        isAppMode: viewModel.isAppPresentationMode,
                        onSelect: { viewModel.selectedCellId = cell.id },
                        onRun: { viewModel.runCell(cell, computeTarget: appState.currentComputeTarget) },
                        onRunDownstream: { viewModel.runDownstreamCells(from: cell, computeTarget: appState.currentComputeTarget) },
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

                if !viewModel.isAppPresentationMode {
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
                        Button(action: { viewModel.addCell(type: .agent) }) {
                            HStack(spacing: 6) {
                                Image(systemName: "brain.head.profile")
                                    .foregroundColor(.accentColor)
                                Text("AI Agent")
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(controlBackground)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 20)
                }
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
    var dagInfo: CellDAGNodeInfo? = nil
    var liveVariables: [KernelVariableInfo] = []
    var isAppMode: Bool = false
    let onSelect: () -> Void
    let onRun: () -> Void
    var onRunDownstream: (() -> Void)? = nil
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
        Group {
            if isAppMode {
                executiveAppModeCellCard
            } else if cell.type == .agent {
                inlineAgentCellCard
            } else {
                standardNotebookCellCard
            }
        }
    }

    // MARK: - 1-Click Executive App / Dashboard Presentation Mode Card

    @ViewBuilder
    private var executiveAppModeCellCard: some View {
        let paramSpecs = (cell.type == .code) ? CellParameterEngine.parseParameters(from: cell.content) : []
        let trimmedOutput = cell.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasVisualOutput = !paramSpecs.isEmpty
            || cell.inlineDataFrame != nil
            || cell.isDataFrame
            || !cell.outputImages.isEmpty
            || !trimmedOutput.isEmpty

        if cell.type == .markdown {
            RichMarkdownCellView(
                text: Binding(get: { cell.content }, set: { cell.content = $0 }),
                liveVariables: liveVariables,
                isDark: appState.appTheme.isDark,
                forceRenderedOnly: true
            )
            .padding(.vertical, 4)
            .background(cellCardBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(cellBorderColor, lineWidth: 0.8)
            )
            .padding(.horizontal, 16)
        } else if hasVisualOutput {
            VStack(alignment: .leading, spacing: 8) {
                if !paramSpecs.isEmpty {
                    CellParamWidgetsBar(
                        specs: paramSpecs,
                        language: cell.language.rawValue,
                        isDark: appState.appTheme.isDark
                    ) { spec, newLiteral, shouldAutoRun in
                        cell.content = CellParameterEngine.updateParameterValue(
                            in: cell.content,
                            spec: spec,
                            newFormattedLiteral: newLiteral,
                            language: cell.language.rawValue
                        )
                        if shouldAutoRun { onRun() }
                    }
                    .padding(.top, 8)
                }

                cellRichOutputsContent
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(cellCardBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(cellBorderColor, lineWidth: 0.8)
            )
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Dedicated Formal Inline Agent Cell (Clean Composer + Instant Enter/Click Send)

    private var inlineAgentCellCard: some View {
        let isDark = appState.appTheme.isDark
        let canSend = !cell.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAgentActivity = cell.isExecuting
            || !cell.agentThought.isEmpty
            || !cell.agentToolSteps.isEmpty
            || !cell.agentStatusText.isEmpty
            || !cell.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: 0) {
            // Prompt Input (when expanded)
            if !cell.isCollapsed {
                CellPromptInputView(
                    text: Binding(
                        get: { cell.content },
                        set: { cell.content = $0 }
                    ),
                    placeholder: cell.agentExecutionMode
                        ? "สั่ง Agent ให้สร้าง แก้ไข หรือรัน Cell… (กด Enter เพื่อส่ง, Shift+Enter ขึ้นบรรทัดใหม่)"
                        : "พิมพ์คำถามหรือให้ AI สร้างโค้ด… (กด Enter เพื่อส่ง)",
                    isDark: isDark,
                    minHeight: 36,
                    maxHeight: 160,
                    fontSize: 12.5,
                    onFocus: { focused in
                        if focused { onSelect() }
                    },
                    onSubmit: {
                        onSelect()
                        if !cell.isExecuting && !cell.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onRun()
                        }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }

            // Consolidated Single-Row Action Bar (No duplicate badges, no Tag/Color clutter)
            HStack(spacing: 6) {
                CellModeTogglePill(
                    isAgentMode: Binding(
                        get: { cell.agentExecutionMode },
                        set: { cell.agentExecutionMode = $0 }
                    ),
                    compact: true
                )
                .fixedSize()

                CellAIModelSelectorPill(
                    selection: Binding(
                        get: { cell.aiSelection },
                        set: { cell.aiSelection = $0 }
                    ),
                    showRoleSelector: cell.agentExecutionMode,
                    maxWidth: 230,
                    compact: true,
                    minimalChrome: true,
                    roleIconOnly: true
                )

                if cell.isCollapsed && canSend {
                    Text(cell.content.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 6)

                if isHovering || isSelected {
                    HStack(spacing: 5) {
                        Button(action: onMoveUp) {
                            Image(systemName: "arrow.up")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Move Cell Up")

                        Button(action: onMoveDown) {
                            Image(systemName: "arrow.down")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Move Cell Down")

                        Button(action: { cell.isCollapsed.toggle() }) {
                            Image(systemName: cell.isCollapsed ? "chevron.down" : "chevron.up")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help(cell.isCollapsed ? "Expand Cell" : "Collapse Cell")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Delete Cell")
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                }

                // Always-visible Send / Stop button
                if cell.isExecuting {
                    Button(action: {
                        onSelect()
                        onRun()
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 25, height: 25)
                            .background(Color.red.opacity(0.85))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Stop Agent")
                } else {
                    Button(action: {
                        onSelect()
                        onRun()
                    }) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(canSend ? .white : .secondary.opacity(0.55))
                            .frame(width: 25, height: 25)
                            .background(canSend ? Color.accentColor : Color.primary.opacity(0.07))
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .fixedSize()
                    .help(cell.agentExecutionMode ? "Run Agent (Enter)" : "Send (Enter)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, cell.isCollapsed ? 8 : 7)

            // Agent Reasoning, Tool Timeline & Response Output
            if !cell.isCollapsed && hasAgentActivity {
                Divider()
                    .opacity(0.55)
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 8) {
                    if cell.isExecuting {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.75)
                            Text(cell.agentStatusText.isEmpty ? "Working…" : cell.agentStatusText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                        }
                    }
                    if !cell.agentThought.isEmpty {
                        AntigravityThoughtBlockView(content: cell.agentThought, durationSeconds: nil)
                    }
                    if !cell.agentToolSteps.isEmpty {
                        CellAgentToolStepsTimeline(steps: cell.agentToolSteps)
                    }
                    if !cell.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        CellAIRichContentView(content: cell.output)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(cellCardBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected
                        ? Color.accentColor.opacity(0.85)
                        : Color.primary.opacity(isDark ? 0.12 : 0.09),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }

    private var standardNotebookCellCard: some View {
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
                    if let oldCode = cell.pendingDiffOldContent, oldCode != cell.content {
                        CellInlineDiffBanner(
                            oldCode: oldCode,
                            newCode: cell.content,
                            sourceLabel: cell.pendingDiffSource,
                            isDark: appState.appTheme.isDark,
                            onAccept: {
                                cell.pendingDiffOldContent = nil
                            },
                            onRevert: {
                                cell.content = oldCode
                                cell.pendingDiffOldContent = nil
                            }
                        )
                    }

                    if cell.type == .code {
                        let paramSpecs = CellParameterEngine.parseParameters(from: cell.content)
                        if !paramSpecs.isEmpty {
                            CellParamWidgetsBar(
                                specs: paramSpecs,
                                language: cell.language.rawValue,
                                isDark: appState.appTheme.isDark
                            ) { spec, newLiteral, shouldAutoRun in
                                cell.content = CellParameterEngine.updateParameterValue(
                                    in: cell.content,
                                    spec: spec,
                                    newFormattedLiteral: newLiteral,
                                    language: cell.language.rawValue
                                )
                                if shouldAutoRun { onRun() }
                            }
                        }
                    }

                    if cell.type == .procedure {
                        SASProcedureView(cell: cell, onRun: onRun)
                    } else if cell.type == .markdown {
                        RichMarkdownCellView(
                            text: Binding(
                                get: { cell.content },
                                set: { cell.content = $0 }
                            ),
                            liveVariables: liveVariables,
                            isDark: appState.appTheme.isDark,
                            forceRenderedOnly: false
                        )
                    } else if cell.type == .agent {
                        // Theme-Native Inline Agent Prompt Composer
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack(alignment: .topLeading) {
                                if cell.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(cell.agentExecutionMode
                                         ? "สั่ง Agent ให้สร้าง/แก้ไข/รัน Cell วิเคราะห์ข้อมูล หรือเรียกใช้เครื่องมือใน Workspace และ MCP…"
                                         : "พิมพ์คำถามหรือให้ AI สร้างโค้ด…")
                                        .font(.system(size: 12.5))
                                        .foregroundColor(.secondary.opacity(0.65))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: Binding(
                                    get: { cell.content },
                                    set: { cell.content = $0 }
                                ))
                                .font(.system(size: 12.5))
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .frame(minHeight: 54, maxHeight: 220)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                            .background(
                                appState.appTheme.isGlass
                                    ? Color.primary.opacity(0.04)
                                    : Color(nsColor: appState.appTheme.panelBackground).opacity(0.75)
                            )
                            .cornerRadius(7)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color.primary.opacity(appState.appTheme.isDark ? 0.10 : 0.08), lineWidth: 1)
                            )
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
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
                    let hasAgentActivity = cell.type == .agent && (cell.isExecuting || !cell.agentThought.isEmpty || !cell.agentToolSteps.isEmpty || !cell.agentStatusText.isEmpty)
                    if !cell.output.isEmpty || !cell.outputImages.isEmpty || cell.isDataFrame || cell.inlineDataFrame != nil || hasAgentActivity {
                        Divider()
                            .padding(.horizontal, 8)
                        
                        cellRichOutputsContent
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

    @ViewBuilder
    private var cellRichOutputsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Auto-Rendered Native Inline DataFrame Grid & Retina Chart Studio (Python & SQL)
            if let inlineDF = cell.inlineDataFrame {
                NotebookInlineDataGridStudio(
                    payload: inlineDF,
                    isDark: appState.appTheme.isDark,
                    onCreateSQLQueryCell: onGenerateCode
                )
            }

            // Legacy file-backed DataFrame Output
            if let dfPath = cell.dataFramePath, cell.isDataFrame, cell.inlineDataFrame == nil {
                DataFrameView(rawPath: dfPath, onGenerateCode: onGenerateCode)
                    .frame(height: 300)
            }

            if cell.type == .agent {
                if cell.isExecuting {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.75)
                        Text(cell.agentStatusText.isEmpty ? "Working…" : cell.agentStatusText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Button(action: onRun) {
                            HStack(spacing: 3) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 8))
                                Text("Stop")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.primary.opacity(0.85))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }
                }
                if !cell.agentThought.isEmpty {
                    AntigravityThoughtBlockView(content: cell.agentThought, durationSeconds: nil)
                }
                if !cell.agentToolSteps.isEmpty {
                    CellAgentToolStepsTimeline(steps: cell.agentToolSteps)
                }
                if !cell.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    CellAIRichContentView(content: cell.output)
                }
            } else if !cell.output.isEmpty {
                let hasError = cell.output.contains("Error")
                    || cell.output.contains("Traceback")
                    || cell.output.contains("Exception")
                    || cell.output.contains("CUDA out of memory")
                if hasError && !isAppMode {
                    CellSelfHealingBanner(cell: cell, onRun: onRun)
                }

                VirtualizedCellOutputLogView(
                    output: cell.output,
                    hasError: hasError
                )
            }

            // Image Output (Retina matplotlib, PIL, PDF, HTML — cached via NotebookImageCache)
            if !cell.outputImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(cell.outputImages, id: \.self) { imageURL in
                            if imageURL.pathExtension.lowercased() == "pdf" {
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
                            } else if let nsImage = NotebookImageCache.shared.image(for: imageURL) {
                                VStack(spacing: 4) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: 320)
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
    }
    
    private var cellHeader: some View {
        HStack(spacing: 6) {
            // Cell Type Badge
            Text(cell.type.rawValue)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(cellTypeColor.opacity(0.16))
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
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(cell.language.color.opacity(0.2))
                    .foregroundColor(cell.language.color)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .fixedSize()
                
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
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(cell.computeTargetOverride != nil ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    .foregroundColor(cell.computeTargetOverride != nil ? .accentColor : .secondary)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Per-Cell Compute Engine (Overrides default target for this cell)")
            } else if cell.type == .agent {
                CellModeTogglePill(
                    isAgentMode: Binding(
                        get: { cell.agentExecutionMode },
                        set: { cell.agentExecutionMode = $0 }
                    ),
                    compact: true
                )
                .fixedSize()

                CellAIModelSelectorPill(
                    selection: Binding(
                        get: { cell.aiSelection },
                        set: { cell.aiSelection = $0 }
                    ),
                    showRoleSelector: cell.agentExecutionMode,
                    maxWidth: 215,
                    compact: true,
                    minimalChrome: true
                )
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
                        Button(action: { cell.tag = ""; tagDraft = ""; showTagEditor = false }) {
                            Text("Clear")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.07))
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(action: {
                            cell.tag = tagDraft.trimmingCharacters(in: .whitespaces)
                            showTagEditor = false
                        }) {
                            Text("Set")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.accentColor)
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
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

            // DAG Lineage: Stale Upstream Indicator & 1-Click Run Downstream
            if let dag = dagInfo {
                if dag.isStaleFromUpstream {
                    Button(action: onRun) {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text("Stale")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Upstream cell (\(dag.upstreamCellNumbers.map { "#\($0)" }.joined(separator: ", "))) updated \(dag.referencedUpstreamSymbols.joined(separator: ", ")). Click to re-run.")
                }

                if !dag.downstreamCellIds.isEmpty {
                    Button(action: { onRunDownstream?() ?? onRun() }) {
                        HStack(spacing: 2.5) {
                            Image(systemName: "arrow.turn.right.down")
                                .font(.system(size: 8, weight: .semibold))
                            Text("\(dag.downstreamCellIds.count)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Run this cell + \(dag.downstreamCellIds.count) downstream dependent cell(s)")
                }
            }

            // Per-Cell Execution Telemetry Pill (Duration, RAM Delta, Metal GPU, Binary Cache)
            if let tel = cell.telemetry {
                HStack(spacing: 4) {
                    Image(systemName: tel.isCachedBinary ? "bolt.fill" : "timer")
                        .font(.system(size: 8))
                        .foregroundColor(tel.isCachedBinary ? .green : .secondary)
                    if tel.isCachedBinary {
                        Text("Cached")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    Text(tel.formattedDuration)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(tel.isCachedBinary ? .green : .secondary)
                    if let memDelta = tel.formattedMemoryDelta {
                        Text("· \(memDelta)")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.85))
                    }
                    if let metal = tel.formattedMetal {
                        Text("· \(metal)")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.purple)
                    }
                }
                .padding(.horizontal, 5.5)
                .padding(.vertical, 2)
                .background((tel.isCachedBinary ? Color.green : Color.primary).opacity(0.065))
                .cornerRadius(4)
                .fixedSize()
            }

            // Per-Cell Time-Travel Snapshot History
            CellVersionHistoryButton(snapshots: cell.versionSnapshots) { snap in
                cell.content = snap.content
                cell.pendingDiffOldContent = nil
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
        if cell.isQueued { return "[⏳]" }
        if let count = cell.executionCount { return "[\(count)]" }
        return "[ ]"
    }
    
    private var cellTypeColor: Color {
        switch cell.type {
        case .code: return .blue
        case .markdown: return .green
        case .raw: return .gray
        case .procedure: return .orange
        case .agent: return .accentColor
        }
    }
}

// MARK: - Cell Self-Healing Banner

struct CellSelfHealingBanner: View {
    @EnvironmentObject var appState: AppState
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
                    HStack(spacing: 3.5) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 9))
                        Text("Run on Local Mac")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color.accentColor)
                    .cornerRadius(4.5)
                }
                .buttonStyle(.plain)
                .help("Execute this cell immediately on your local Mac processor")
                
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("MicroCodeOpenColabSheet"), object: nil)
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                        Text("Connect Colab")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 7.5)
                    .padding(.vertical, 3.5)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(4.5)
                }
                .buttonStyle(.plain)
            }
            
            // 1. AI Agent Auto-Fix Button (Monochrome / Theme-matching, zero AppKit bezel)
            Button {
                triggerAgentAutoFix()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.badge.automatic.fill")
                        .font(.system(size: 10))
                    Text("Agent Auto-Fix")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.09))
                .cornerRadius(4.5)
                .overlay(
                    RoundedRectangle(cornerRadius: 4.5)
                        .stroke(Color.primary.opacity(0.14), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .disabled(isFixing)
            .help("MicroCode AI Agent repairs and re-runs this cell automatically")
            
            // 2. Open in Full AI Agent Chat
            Button {
                openInAgentChat()
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 9))
                    Text("Ask Agent")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4.5)
            }
            .buttonStyle(.plain)
            .disabled(isFixing)
            .help("Switch to MicroCode AI Agent to interactively debug and fix this error")
            
            // 3. Copy Traceback Button
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cell.output, forType: .string)
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCopied = false }
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                    Text(showCopied ? "Copied" : "Copy")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(showCopied ? .green : .secondary)
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4.5)
            }
            .buttonStyle(.plain)
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
        
        var healSelection = CellAISelection.inherit
        healSelection.subAgentRole = CellSubAgentRole.bugHunter.rawValue
        let sessionId = "self-heal-\(cell.id.uuidString)"
        let workspaceRoot = appState.workspaceFolder?.path ?? NotebookViewModel.shared.workingDirectory.path

        CellAgentCoordinator.shared.startExecution(
            sessionId: sessionId,
            prompt: prompt,
            selection: healSelection,
            isAgentMode: false,
            appState: appState,
            notebookContext: "",
            workspaceRoot: workspaceRoot,
            onStatus: { status in
                if !status.isEmpty { self.fixStatus = status }
            },
            onThought: { _ in },
            onText: { _ in },
            onToolSteps: { _ in },
            onComplete: { response in
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
                    self.cell.recordAgentEditBaseline(previousContent: self.cell.content, source: "Agent Auto-Fix")
                    self.cell.content = fixed
                    self.cell.appendOutput("\n⚡ [Agent Self-Healing] Code patched. Re-executing now...\n")
                    self.onRun()
                }
            },
            onError: { err in
                self.isFixing = false
                self.cell.appendOutput("\n⚠️ [Agent Self-Healing] Repair error: \(err)\n")
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

// MARK: - Responsive Draggable Vertical Split Handle

struct NotebookVerticalResizeHandle: View {
    let onDrag: (_ translationX: CGFloat, _ isEnded: Bool) -> Void
    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    (isHovering || isDragging)
                        ? Color.primary.opacity(0.28)
                        : Color(nsColor: .separatorColor)
                )
                .frame(width: 1)
        }
        .frame(width: 6)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else if !isDragging {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging { isDragging = true }
                    onDrag(value.translation.width, false)
                }
                .onEnded { value in
                    isDragging = false
                    if !isHovering { NSCursor.pop() }
                    onDrag(value.translation.width, true)
                }
        )
    }
}
