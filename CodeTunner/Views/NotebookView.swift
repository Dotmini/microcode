//
//  NotebookView.swift (Enhanced Multi-Notebook)
//  CodeTunner
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
        case .python, .r, .julia, .sql, .rust, .go, .cpp, .objc: return true
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
        case .rmarkdown: return "Rmd"
        case .latex: return "tex"
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
    }
    
    init(type: CellType = .code, language: CellLanguage = .python, content: String = "") {
        self.type = type
        self.language = language
        self.content = content.isEmpty && type == .code ? language.defaultContent : content
    }
    
    func clearOutput() {
        output = ""
        output = ""
        outputImages = []
        dataFramePath = nil
        isDataFrame = false
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
    
    var activeNotebook: NotebookModel? {
        notebooks.first { $0.id == activeNotebookId }
    }
    
    init() {
        print("📝 NotebookViewModel: Initializing...")
        // Create working directory with read/write permissions
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let workDir = appSupport.appendingPathComponent("CodeTunner/notebooks_workspace")
        self.workingDirectory = workDir
        
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            print("📝 NotebookViewModel: Created workspace at \(workDir.path)")
        } catch {
            print("❌ NotebookViewModel: Failed to create directory: \(error)")
        }
        
        // Create initial notebook
        let notebook = NotebookModel(name: "Notebook 1")
        notebooks = [notebook]
        activeNotebookId = notebook.id
        if let firstCell = notebook.cells.first {
            selectedCellId = firstCell.id
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
    }
    
    func deleteCell(_ cell: NotebookCellModel) {
        guard let notebook = activeNotebook else { return }
        guard notebook.cells.count > 1 else { return }
        notebook.cells.removeAll { $0.id == cell.id }
        if selectedCellId == cell.id {
            selectedCellId = notebook.cells.first?.id
        }
        notebook.modifiedAt = Date()
    }
    
    func moveCell(_ cell: NotebookCellModel, direction: Int) {
        guard let notebook = activeNotebook else { return }
        guard let index = notebook.cells.firstIndex(where: { $0.id == cell.id }) else { return }
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < notebook.cells.count else { return }
        notebook.cells.swapAt(index, newIndex)
        notebook.modifiedAt = Date()
    }
    
    func runCell(_ cell: NotebookCellModel) {
        guard cell.type == .code || cell.type == .procedure else { return }
        
        cell.isExecuting = true
        cell.clearOutput()
        kernelStatus = "Running"
        
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
        }
    }
    
    private func runProcedureCell(_ cell: NotebookCellModel) {
        // Procedure cells always run as Python with generated code
        runPythonCell(cell)
    }
    
    private func runRustCell(_ cell: NotebookCellModel) {
        // Find rustc
        var rustcPath = "rustc"
        if let runtime = RuntimeManager.shared.runtimes.first(where: { $0.type == .rust }), let path = runtime.path {
             rustcPath = path
        }
        
        let uuid = UUID().uuidString.prefix(8)
        let tempRs = workingDirectory.appendingPathComponent("temp_\(uuid).rs")
        let tempBin = workingDirectory.appendingPathComponent("temp_\(uuid)")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try cell.content.write(to: tempRs, atomically: true, encoding: .utf8)
                
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
                
                compileProcess.currentDirectoryURL = self.workingDirectory
                
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
                    runProcess.currentDirectoryURL = self.workingDirectory
                    
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
                    self.handleCellOutput(cell: cell, result: result)
                    
                } else {
                    // Compile failed
                    let result = "❌ Compilation Failed:\n" + compileError
                    self.handleCellOutput(cell: cell, result: result)
                }
                
                // Cleanup source
                try? FileManager.default.removeItem(at: tempRs)
                
            } catch {
                let result = "❌ Error: \(error.localizedDescription)"
                self.handleCellOutput(cell: cell, result: result)
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
        let tempGo = workingDirectory.appendingPathComponent("temp_\(uuid).go")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try cell.content.write(to: tempGo, atomically: true, encoding: .utf8)
                
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
                
                process.currentDirectoryURL = self.workingDirectory
                
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
                self.handleCellOutput(cell: cell, result: result)
                
            } catch {
                let result = "❌ Error: \(error.localizedDescription)"
                self.handleCellOutput(cell: cell, result: result)
            }
        }
    }
    
    private func runCppCell(_ cell: NotebookCellModel) {
        let uuid = UUID().uuidString.prefix(8)
        let tempCpp = workingDirectory.appendingPathComponent("temp_\(uuid).cpp")
        let tempBin = workingDirectory.appendingPathComponent("temp_\(uuid)")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try cell.content.write(to: tempCpp, atomically: true, encoding: .utf8)
                
                // 1. Compile: clang++ -o tempBin tempCpp
                let compileProcess = Process()
                compileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                compileProcess.arguments = ["clang++", tempCpp.path, "-o", tempBin.path]
                compileProcess.currentDirectoryURL = self.workingDirectory
                
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
                    runProcess.currentDirectoryURL = self.workingDirectory
                    
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
                    self.handleCellOutput(cell: cell, result: result)
                    
                } else {
                    // Compile failed
                    let result = "❌ Compilation Failed:\n" + compileError
                    self.handleCellOutput(cell: cell, result: result)
                }
                
                // Cleanup source
                try? FileManager.default.removeItem(at: tempCpp)
                
            } catch {
                let result = "❌ Error: \(error.localizedDescription)"
                self.handleCellOutput(cell: cell, result: result)
            }
        }
    }
    
    private func runObjcCell(_ cell: NotebookCellModel) {
        let uuid = UUID().uuidString.prefix(8)
        let tempObjc = workingDirectory.appendingPathComponent("temp_\(uuid).m")
        let tempBin = workingDirectory.appendingPathComponent("temp_\(uuid)")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try cell.content.write(to: tempObjc, atomically: true, encoding: .utf8)
                
                // 1. Compile: clang -framework Foundation -o tempBin tempObjc
                let compileProcess = Process()
                compileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                compileProcess.arguments = ["clang", "-framework", "Foundation", tempObjc.path, "-o", tempBin.path]
                compileProcess.currentDirectoryURL = self.workingDirectory
                
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
                    runProcess.currentDirectoryURL = self.workingDirectory
                    
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
                    self.handleCellOutput(cell: cell, result: result)
                    
                } else {
                    // Compile failed
                    let result = "❌ Compilation Failed:\n" + compileError
                    self.handleCellOutput(cell: cell, result: result)
                }
                
                // Cleanup source
                try? FileManager.default.removeItem(at: tempObjc)
                
            } catch {
                let result = "❌ Error: \(error.localizedDescription)"
                self.handleCellOutput(cell: cell, result: result)
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
        PythonEnvManager.shared.executeCode(fullCode, pythonPath: pythonPath) { [weak self] result, success in
            self?.handleCellOutput(cell: cell, result: result)
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
        
        // Write to temp file and execute
        let tempFile = workingDirectory.appendingPathComponent("temp_script_\(UUID().uuidString).R")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try fullCode.write(to: tempFile, atomically: true, encoding: .utf8)
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: rPath)
                process.arguments = ["--vanilla", tempFile.path]
                process.currentDirectoryURL = self.workingDirectory
                
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
                
                self.handleCellOutput(cell: cell, result: result)
            } catch {
                DispatchQueue.main.async {
                    cell.output = "❌ Error: \(error.localizedDescription)"
                    cell.isExecuting = false
                    self.kernelStatus = "Idle"
                }
            }
        }
    }
    
    private func handleCellOutput(cell: NotebookCellModel, result: String) {
        // Check for DataFrame metadata
        if let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let isDF = json["__codetunner_dataframe__"] as? Bool, isDF,
           let path = json["path"] as? String {
            DispatchQueue.main.async {
                cell.output = "" // Clear text output
                cell.dataFramePath = path
                cell.isDataFrame = true
                cell.executionCount = (self.totalExecutions + 1)
                cell.isExecuting = false
                self.totalExecutions += 1
                self.kernelStatus = "Idle"
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
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
        
        let tempRmd = workingDirectory.appendingPathComponent("temp_\(UUID().uuidString).Rmd")
        let outputHtml = workingDirectory.appendingPathComponent("temp_\(UUID().uuidString).html")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try cell.content.write(to: tempRmd, atomically: true, encoding: .utf8)
                
                // Render R Markdown using rmarkdown::render()
                let renderScript = """
                rmarkdown::render('\(tempRmd.path)', output_file = '\(outputHtml.path)', quiet = TRUE)
                cat('[RMARKDOWN_OUTPUT:\(outputHtml.path)]')
                """
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: rPath)
                process.arguments = ["-e", renderScript]
                process.currentDirectoryURL = self.workingDirectory
                
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
                    
                    DispatchQueue.main.async {
                        cell.output = summary
                        cell.outputImages = [outputHtml]  // Store HTML path
                        cell.isExecuting = false
                        self.totalExecutions += 1
                        cell.executionCount = self.totalExecutions
                        self.kernelStatus = "Idle"
                    }
                } else {
                    let result = "❌ R Markdown render failed:\n" + error + "\n" + output
                    self.handleCellOutput(cell: cell, result: result)
                }
            } catch {
                DispatchQueue.main.async {
                    cell.output = "❌ Error: \(error.localizedDescription)"
                    cell.isExecuting = false
                    self.kernelStatus = "Idle"
                }
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
        let tempTex = workingDirectory.appendingPathComponent("temp_\(uuid).tex")
        let tempPdf = workingDirectory.appendingPathComponent("temp_\(uuid).pdf")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try cell.content.write(to: tempTex, atomically: true, encoding: .utf8)
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: latexPath)
                process.arguments = ["-interaction=nonstopmode", "-output-directory=\(self.workingDirectory.path)", tempTex.path]
                process.currentDirectoryURL = self.workingDirectory
                
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
                    let auxFile = self.workingDirectory.appendingPathComponent("temp_\(uuid).\(ext)")
                    try? FileManager.default.removeItem(at: auxFile)
                }
                
                if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: tempPdf.path) {
                    DispatchQueue.main.async {
                        cell.output = "✅ LaTeX compiled successfully!\n📄 PDF: \(tempPdf.lastPathComponent)\n\n💡 Tip: Click the PDF to open it."
                        cell.outputImages = [tempPdf]  // Store PDF path
                        cell.isExecuting = false
                        self.totalExecutions += 1
                        cell.executionCount = self.totalExecutions
                        self.kernelStatus = "Idle"
                    }
                } else {
                    // Extract errors from log
                    let logFile = self.workingDirectory.appendingPathComponent("temp_\(uuid).log")
                    let logContent = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
                    let errorLines = logContent.components(separatedBy: "\n").filter { $0.contains("!") || $0.contains("Error") }
                    
                    let errorSummary = errorLines.isEmpty ? error + output : errorLines.joined(separator: "\n")
                    let result = "❌ LaTeX compilation failed:\n\(errorSummary)"
                    self.handleCellOutput(cell: cell, result: result)
                }
            } catch {
                DispatchQueue.main.async {
                    cell.output = "❌ Error: \(error.localizedDescription)"
                    cell.isExecuting = false
                    self.kernelStatus = "Idle"
                }
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
        
        let tempFile = workingDirectory.appendingPathComponent("temp_\(UUID().uuidString).jl")
        
        // Setup code for plots
        let setupCode = """
        cd("\(workingDirectory.path)")
        
        """
        
        let fullCode = setupCode + cell.content
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try fullCode.write(to: tempFile, atomically: true, encoding: .utf8)
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: juliaPath)
                process.arguments = [tempFile.path]
                process.currentDirectoryURL = self.workingDirectory
                
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
                
                self.handleCellOutput(cell: cell, result: result)
            } catch {
                DispatchQueue.main.async {
                    cell.output = "❌ Error: \(error.localizedDescription)"
                    cell.isExecuting = false
                    self.kernelStatus = "Idle"
                }
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
        PythonEnvManager.shared.executeCode(pythonCode, pythonPath: pythonPath) { [weak self] result, success in
            self?.handleCellOutput(cell: cell, result: result)
        }
    }
    
    // MARK: - Run Cells by Color
    
    func runCellsByColor(_ colorTheme: CellColorTheme) {
        guard let notebook = activeNotebook else { return }
        let cellsToRun = notebook.cells.filter { $0.colorTheme == colorTheme && $0.type == .code }
        
        for cell in cellsToRun {
            runCell(cell)
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
    
    func runSelectedCell() {
        guard let notebook = activeNotebook,
              let id = selectedCellId,
              let cell = notebook.cells.first(where: { $0.id == id }) else { return }
        runCell(cell)
    }
    
    func runAllCells() {
        guard let notebook = activeNotebook else { return }
        for cell in notebook.cells where cell.type == .code {
            runCell(cell)
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
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(notebook.name).ipynb"
        panel.title = "Save Notebook"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            // Construct JSON
            var jsonCells: [[String: Any]] = []
            
            for cell in notebook.cells {
                var cellDict: [String: Any] = [
                    "cell_type": cell.type.rawValue.lowercased(),
                    "metadata": [:],
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
                        "codemirror_mode": [
                            "name": "ipython",
                            "version": 3
                        ],
                        "file_extension": ".py",
                        "mimetype": "text/x-python",
                        "name": "python",
                        "nbconvert_exporter": "python",
                        "pygments_lexer": "ipython3",
                        "version": "3.8.5"
                    ]
                ],
                "nbformat": 4,
                "nbformat_minor": 4
            ]
            
            do {
                let data = try JSONSerialization.data(withJSONObject: notebookDict, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: url)
            } catch {
                print("Failed to save notebook: \(error)")
            }
        }
    }
}

// MARK: - Main Notebook View

struct NotebookView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = NotebookViewModel()
    @ObservedObject private var pythonEnvManager = PythonEnvManager.shared
    @ObservedObject private var shmService = SharedMemoryService.shared
    @State private var isReady = false
    
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
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(notebook.cells) { cell in
                                NotebookCellView(
                                    cell: cell,
                                    isSelected: viewModel.selectedCellId == cell.id,
                                    onSelect: { viewModel.selectedCellId = cell.id },
                                    onRun: { viewModel.runCell(cell) },
                                    onDelete: { viewModel.deleteCell(cell) },
                                    onMoveUp: { viewModel.moveCell(cell, direction: -1) },
                                    onMoveDown: { viewModel.moveCell(cell, direction: 1) },
                                    onGenerateCode: { code in
                                        viewModel.addCell(type: .code, language: .python)
                                        // Set content of the newly added cell (it's the active one now)
                                        if let lastCell = viewModel.activeNotebook?.cells.last {
                                            lastCell.content = code
                                            viewModel.runCell(lastCell)
                                        }
                                    }
                                )
                            }
                            
                            addCellButton
                                .padding(.vertical, 20)
                        }
                        .padding()
                    }
                    .background(appState.appTheme == .transparent ? Color.clear : Color(nsColor: .textBackgroundColor).opacity(0.3))
                } else {
                    // Loading or empty state
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
            isReady = true
            // Ensure notebook is active
            if viewModel.activeNotebookId == nil && !viewModel.notebooks.isEmpty {
                viewModel.activeNotebookId = viewModel.notebooks.first?.id
            }
            // Sync Python version with appState
            viewModel.selectedPythonPath = appState.selectedPythonVersion
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
                            Button(action: { viewModel.runAllCells() }) {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Run All")
                                    Spacer()
                                }
                            }
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
        HStack(spacing: 12) {
            Button(action: { viewModel.showingSidebar.toggle() }) {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.borderless)
            
            // Editable Notebook Name
            if let notebook = viewModel.activeNotebook {
                HStack(spacing: 4) {
                    Text("📓")
                    
                    if viewModel.isEditingName {
                        TextField("Name", text: Binding(
                            get: { notebook.name },
                            set: { notebook.name = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .frame(width: 200)
                        .onSubmit { viewModel.isEditingName = false }
                    } else {
                        Text(notebook.name)
                            .font(.headline)
                            .onTapGesture(count: 2) {
                                viewModel.isEditingName = true
                            }
                    }
                    
                    Button(action: { viewModel.isEditingName.toggle() }) {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
            
            // Python Version Selector
            pythonVersionMenu
            
            Menu {
                Text("Code Cells")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button {
                    viewModel.addCell(type: .code, language: .python)
                } label: {
                    Label("Python Cell", systemImage: "p.circle.fill")
                }
                
                Button {
                    viewModel.addCell(type: .code, language: .r)
                } label: {
                    Label("R Cell", systemImage: "r.circle.fill")
                }
                
                Divider()
                
                Button {
                    viewModel.addCell(type: .code, language: .julia)
                } label: {
                    Label("Julia Cell", systemImage: "j.circle.fill")
                }
                
                Button {
                    viewModel.addCell(type: .code, language: .sql)
                } label: {
                    Label("SQL Cell", systemImage: "cylinder.fill")
                }
                
                Divider()
                
                Text("Documents")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button {
                    viewModel.addCell(type: .code, language: .rmarkdown)
                } label: {
                    Label("R Markdown (Rmd)", systemImage: "doc.richtext.fill")
                }
                
                Button {
                    viewModel.addCell(type: .code, language: .latex)
                } label: {
                    Label("LaTeX", systemImage: "function")
                }
                
                Divider()
                
                Text("Other")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Markdown Cell") { viewModel.addCell(type: .markdown) }
                Button("Raw Cell") { viewModel.addCell(type: .raw) }
                
                Divider()
                
                Button {
                    viewModel.addCell(type: .procedure)
                } label: {
                    Label("SAS Procedure", systemImage: "tablecells.fill")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            
            Divider().frame(height: 16)
            
            Button(action: { viewModel.runSelectedCell() }) {
                Label("Run", systemImage: "play.fill")
            }
            .disabled(viewModel.selectedCellId == nil)
            
            Menu {
                Button(action: { viewModel.runAllCells() }) {
                    Label("Run All Cells", systemImage: "forward.fill")
                }
                
                Divider()
                
                Text("Run by Color")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(viewModel.getUsedColors()) { theme in
                    Button {
                        viewModel.runCellsByColor(theme)
                    } label: {
                        HStack {
                            Circle().fill(theme.iconColor).frame(width: 8, height: 8)
                            Text("Run \(theme.rawValue) Cells")
                        }
                    }
                }
            } label: {
                Label("Run All", systemImage: "forward.fill")
            } primaryAction: {
                viewModel.runAllCells()
            }
            
            Divider().frame(height: 16)
            
            Button(action: { viewModel.saveNotebook() }) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            
            Divider().frame(height: 16)
            
            Text("Executions: \(viewModel.totalExecutions)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            appState.detectPythonVersions()
        }
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
                appState.detectPythonVersions()
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
    
    // MARK: - Add Cell Button
    
    private var addCellButton: some View {
        HStack(spacing: 16) {
            Button(action: { viewModel.addCell(type: .code) }) {
                HStack {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                    Text("Code")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(controlBackground)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            Button(action: { viewModel.addCell(type: .markdown) }) {
                HStack {
                    Image(systemName: "text.alignleft")
                    Text("Text")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(controlBackground)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            Button(action: { viewModel.addCell(type: .procedure) }) {
                HStack {
                    Image(systemName: "tablecells.fill")
                    Text("Procedure")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(controlBackground)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
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
                .disabled(cell.type != .code)
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
                            fontWeight: appState.cellFontWeight
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
        }
    }
}
