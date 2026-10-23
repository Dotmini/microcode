import Foundation
import Combine

class ProjectMemoryService: ObservableObject {
    static let shared = ProjectMemoryService()
    
    @Published private(set) var projectMemoryContent: String?
    @Published private(set) var isLoaded: Bool = false
    
    private var currentWorkspace: String?
    private var fileWatcher: DispatchSourceFileSystemObject?
    
    private let memoryFileNames: [String] = [
        "AGENTS.md",
        "CLAUDE.md",
        ".cursorrules",
        ".microcode/rules.md",
        ".microcode/project.md",
        "MICROCODE.md"
    ]
    
    private init() {}
    
    @discardableResult
    func loadProjectMemory(workspace: String) -> String? {
        self.currentWorkspace = workspace
        self.setupFileWatcher(workspace: workspace)
        return self.readMemoryFile()
    }
    
    @discardableResult
    func appendLearnedRule(_ rule: String, workspace: String? = nil) -> String {
        let targetWorkspace = workspace ?? currentWorkspace ?? UserDefaults.standard.string(forKey: "MicroCode.WorkspacePath") ?? FileManager.default.currentDirectoryPath
        guard !targetWorkspace.isEmpty else { return "" }
        self.currentWorkspace = targetWorkspace
        let microcodeDir = URL(fileURLWithPath: targetWorkspace).appendingPathComponent(".microcode")
        try? FileManager.default.createDirectory(at: microcodeDir, withIntermediateDirectories: true)
        let rulesURL = microcodeDir.appendingPathComponent("rules.md")
        let cleanRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanRule.isEmpty else { return rulesURL.path }
        let existing = (try? String(contentsOf: rulesURL, encoding: .utf8)) ?? "# Project Rules (.microcode/rules.md)\n\n"
        let updated = existing.hasSuffix("\n") ? "\(existing)- \(cleanRule)\n" : "\(existing)\n- \(cleanRule)\n"
        try? updated.write(to: rulesURL, atomically: true, encoding: .utf8)
        readMemoryFile()
        return rulesURL.path
    }
    
    @discardableResult
    private func readMemoryFile() -> String? {
        guard let workspace = currentWorkspace else { return nil }
        let fm = FileManager.default
        var combinedSections: [String] = []
        
        for fileName in memoryFileNames {
            let fileURL = URL(fileURLWithPath: workspace).appendingPathComponent(fileName)
            if fm.fileExists(atPath: fileURL.path),
               let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let capped = String(trimmed.prefix(8000))
                    combinedSections.append("### \(fileName)\n\(capped)")
                }
            }
        }
        
        if !combinedSections.isEmpty {
            let merged = combinedSections.joined(separator: "\n\n")
            DispatchQueue.main.async {
                self.projectMemoryContent = merged
                self.isLoaded = true
            }
            return merged
        }
        
        DispatchQueue.main.async {
            self.projectMemoryContent = nil
            self.isLoaded = false
        }
        return nil
    }
    
    private func setupFileWatcher(workspace: String) {
        fileWatcher?.cancel()
        fileWatcher = nil
        
        let fm = FileManager.default
        var watchedFile: String? = nil
        
        for fileName in memoryFileNames {
            let fileURL = URL(fileURLWithPath: workspace).appendingPathComponent(fileName)
            if fm.fileExists(atPath: fileURL.path) {
                watchedFile = fileURL.path
                break
            }
        }
        
        // If none of the specific files exist, we could watch the directory, 
        // but for simplicity we'll just watch the file if it exists.
        guard let fileToWatch = watchedFile else { return }
        
        let fd = open(fileToWatch, O_EVTONLY)
        if fd != -1 {
            let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
            watcher.setEventHandler { [weak self] in
                self?.readMemoryFile()
                self?.setupFileWatcher(workspace: workspace)
            }
            watcher.setCancelHandler {
                close(fd)
            }
            watcher.resume()
            self.fileWatcher = watcher
        }
    }
    
    func getSystemPromptAddendum() -> String {
        guard let content = projectMemoryContent, !content.isEmpty else { return "" }
        return "\n\n## Project Context (from MICROCODE.md)\n\(content)"
    }
}
