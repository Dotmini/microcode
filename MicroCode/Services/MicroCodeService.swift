import Foundation
import Combine

// Assuming MicroCore is available in the module scope (as file is added to target)
// import microcode_coreFFI // Not needed if modulemap defines it efficiently, but MicroCore.swift imports it.

@MainActor
class MicroCodeService: ObservableObject {
    private var core: MicroCore?
    private var terminalOutputCancellable: AnyCancellable?
    
    @Published var isInitialized = false
    @Published var lastError: String?
    @Published var terminalOutput: String = ""
    @Published var isIndexing = false
    
    // Config
    private let workspacePath: String
    
    init(workspacePath: String) {
        self.workspacePath = workspacePath
        setupCore()
    }
    
    func setupCore() {
        do {
            let config = AgentConfig(
                workspacePath: workspacePath,
                vectorDbPath: nil, // Use default
                shell: "/bin/zsh"
            )
            
            self.core = try MicroCore(config: config)
            self.isInitialized = true
            print("🧠 MicroCode Core Initialized for: \(workspacePath)")
            
        } catch {
            self.lastError = "Failed to init MicroCore: \(error)"
            print("❌ MicroCore Init Error: \(error)")
        }
    }
    
    // MARK: - Terminal (Synchronous for MVP)
    
    func executeCommand(_ cmd: String) async -> String {
        guard let core = core else { return "Error: Core not initialized" }
        
        return await Task.detached {
            do {
                return try core.executeCommand(cmd: cmd)
            } catch {
                return "Command Error: \(error)"
            }
        }.value
    }
    
    // MARK: - File Editing
    
    func applyEdit(filePath: String, search: String, replace: String) -> Bool {
        guard let core = core else { return false }
        
        do {
            let result = try core.applyEdit(filePath: filePath, searchBlock: search, replaceBlock: replace)
            return result.success
        } catch {
            self.lastError = "Edit Error: \(error)"
            return false
        }
    }
    
    func readFile(at path: String) -> String? {
        guard let core = core else { return nil }
        return try? core.readFile(filePath: path)
    }
    
    func writeFile(at path: String, content: String) -> Bool {
        guard let core = core else { return false }
        do {
            try core.writeFile(filePath: path, content: content)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - RAG (Knowledge)
    
    func indexProject() async {
        guard let core = core else { return }
        self.isIndexing = true
        
        await Task.detached {
            do {
                let count = try core.indexProject(path: self.workspacePath)
                await MainActor.run {
                    print("✅ Indexed \(count) chunks")
                    self.isIndexing = false
                }
            } catch {
                await MainActor.run {
                    self.lastError = "Indexing failed: \(error)"
                    self.isIndexing = false
                }
            }
        }.value
    }
    
    func search(query: String) async -> [SearchResult] {
        guard let core = core else { return [] }
        
        return await Task.detached {
            do {
                return try core.semanticSearch(query: query, limit: 10)
            } catch {
                print("Search Error: \(error)")
                return []
            }
        }.value
    }
}
