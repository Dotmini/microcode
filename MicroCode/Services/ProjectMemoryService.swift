import Foundation
import Combine

class ProjectMemoryService: ObservableObject {
    static let shared = ProjectMemoryService()
    
    @Published private(set) var projectMemoryContent: String?
    @Published private(set) var isLoaded: Bool = false
    
    private var currentWorkspace: String?
    private var fileWatcher: DispatchSourceFileSystemObject?
    
    private let memoryFileNames: [String] = [
        ".microcode/project.md",
        "MICROCODE.md",
        ".microcode/rules.md"
    ]
    
    private init() {}
    
    @discardableResult
    func loadProjectMemory(workspace: String) -> String? {
        self.currentWorkspace = workspace
        self.setupFileWatcher(workspace: workspace)
        return self.readMemoryFile()
    }
    
    private func readMemoryFile() -> String? {
        guard let workspace = currentWorkspace else { return nil }
        let fm = FileManager.default
        
        for fileName in memoryFileNames {
            let fileURL = URL(fileURLWithPath: workspace).appendingPathComponent(fileName)
            if fm.fileExists(atPath: fileURL.path) {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.projectMemoryContent = content
                        self.isLoaded = true
                    }
                    return content
                }
            }
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
