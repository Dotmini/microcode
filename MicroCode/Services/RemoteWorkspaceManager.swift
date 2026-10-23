//
//  RemoteWorkspaceManager.swift
//  MicroCode
//
//  Remote Workspace Management Service
//  Copyright © 2025 Dotmini Company Limited. All rights reserved.
//

import Foundation
import Combine

class RemoteWorkspaceManager: ObservableObject {
    static let shared = RemoteWorkspaceManager()
    
    @Published var currentWorkspace: RemoteWorkspaceConfig?
    @Published var syncStatus: SyncStatus = .idle
    @Published var isOpeningProject: Bool = false
    
    private let cacheRootURL: URL
    private var fileWatcher: DispatchSourceFileSystemObject?
    
    // Track individual files opened from FTP without full workspace
    private struct TempFileContext {
        let remotePath: String
        let serverId: UUID
    }
    private var tempFileMap: [URL: TempFileContext] = [:]
    
    private init() {
        // Create cache directory in user's app support folder
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheRootURL = appSupport.appendingPathComponent("com.dotmini.microcode/RemoteCache")
        try? FileManager.default.createDirectory(at: cacheRootURL, withIntermediateDirectories: true)
    }
    
    // MARK: - Open Remote Project
    
    func openRemoteProject(server: RemoteConnectionConfig, remotePath: String) async throws {
        await MainActor.run {
            isOpeningProject = true
            syncStatus = .syncing
        }
        
        defer {
            Task { @MainActor in
                isOpeningProject = false
            }
        }
        
        // Create or reuse incremental local cache directory for this project
        let projectName = URL(fileURLWithPath: remotePath).lastPathComponent
        let localCachePath = cacheRootURL.appendingPathComponent("\(server.id.uuidString)_\(projectName)")
        try FileManager.default.createDirectory(at: localCachePath, withIntermediateDirectories: true)
        
        // Download project structure (incremental + lazy file stubs)
        try await downloadProjectStructure(serverId: server.id.uuidString, remotePath: remotePath, localPath: localCachePath)
        
        // Create workspace config
        let workspace = RemoteWorkspaceConfig(
            serverId: server.id,
            serverName: server.name,
            remotePath: remotePath,
            localCachePath: localCachePath,
            connectionType: server.connectionType,
            executionMode: server.connectionType == .ssh ? .remote : .local
        )
        
        await MainActor.run {
            currentWorkspace = workspace
            syncStatus = .upToDate
        }
        
        // Start file watcher for auto-sync
        startFileWatcher(localPath: localCachePath)
    }
    
    private static let ignoredDirectories: Set<String> = [
        ".git", "node_modules", "target", ".venv", "venv", "__pycache__",
        ".build", "build", "dist", ".next", ".nuxt", ".codetuner-build",
        "Pods", "DerivedData", ".gradle", ".idea", ".cache", "checkpoints", "wandb"
    ]
    
    private static let maxAutoDownloadFileSize: UInt64 = 64 * 1024 // 64 KB cap for root config eager sync
    private static let maxInitialDepth: Int = 2

    // MARK: - Download Project Structure (Lazy Stub Sync)
    
    private func downloadProjectStructure(
        serverId: String,
        remotePath: String,
        localPath: URL,
        depth: Int = 0
    ) async throws {
        guard depth <= Self.maxInitialDepth else { return }
        let files = try await BackendService.shared.listRemoteFiles(id: serverId, path: remotePath)
        
        for file in files {
            if file.name == "." || file.name == ".." { continue }
            if file.isDirectory {
                if Self.ignoredDirectories.contains(file.name) {
                    continue
                }
                let localDir = localPath.appendingPathComponent(file.name)
                try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
                
                try await downloadProjectStructure(
                    serverId: serverId,
                    remotePath: file.path,
                    localPath: localDir,
                    depth: depth + 1
                )
            } else {
                let localFile = localPath.appendingPathComponent(file.name)
                let exists = FileManager.default.fileExists(atPath: localFile.path)
                if depth == 0 && file.size <= Self.maxAutoDownloadFileSize && !exists {
                    if let fileData = try? await BackendService.shared.downloadRemoteFile(id: serverId, path: file.path) {
                        try? fileData.write(to: localFile)
                        continue
                    }
                }
                // Create lightweight placeholder if not cached yet; full content is fetched lazily on open
                if !exists {
                    FileManager.default.createFile(atPath: localFile.path, contents: Data())
                }
            }
        }
    }

    /// Lazily downloads a remote workspace file when opened in the editor if the local cache file is a 0-byte placeholder.
    func ensureFileDownloadedIfNeeded(localURL: URL) async {
        guard let workspace = currentWorkspace else { return }
        let baseLocalPath = workspace.localCachePath.standardizedFileURL.path
        let fileLocalPath = localURL.standardizedFileURL.path
        guard fileLocalPath.hasPrefix(baseLocalPath) else { return }

        let size = (try? FileManager.default.attributesOfItem(atPath: fileLocalPath)[.size] as? UInt64) ?? 0
        guard size == 0 else { return }

        var relativePath = String(fileLocalPath.dropFirst(baseLocalPath.count))
        if !relativePath.hasPrefix("/") {
            relativePath = "/" + relativePath
        }
        let cleanRemoteRoot = workspace.remotePath.hasSuffix("/")
            ? String(workspace.remotePath.dropLast())
            : workspace.remotePath
        let remotePath = cleanRemoteRoot + relativePath

        if let data = try? await BackendService.shared.downloadRemoteFile(
            id: workspace.serverId.uuidString,
            path: remotePath
        ), !data.isEmpty {
            try? data.write(to: localURL, options: .atomic)
        }
    }
    
    // MARK: - File Synchronization
    
    func syncFile(localURL: URL) async {
        guard let workspace = currentWorkspace else { return }
        
        await MainActor.run {
            syncStatus = .syncing
        }
        
        do {
            let baseLocalPath = workspace.localCachePath.standardizedFileURL.path
            let fileLocalPath = localURL.standardizedFileURL.path
            var relativePath = fileLocalPath.replacingOccurrences(of: baseLocalPath, with: "")
            if !relativePath.hasPrefix("/") {
                relativePath = "/" + relativePath
            }
            let cleanRemoteRoot = workspace.remotePath.hasSuffix("/")
                ? String(workspace.remotePath.dropLast())
                : workspace.remotePath
            let remotePath = cleanRemoteRoot + relativePath
            
            let data = try Data(contentsOf: localURL)
            
            try await BackendService.shared.uploadRemoteFile(
                id: workspace.serverId.uuidString,
                path: remotePath,
                content: data
            )
            
            await MainActor.run {
                syncStatus = .upToDate
            }
        } catch {
            print("Sync error: \(error)")
            await MainActor.run {
                syncStatus = .conflict
            }
        }
    }
    
    // MARK: - Temp File Sync (Single File Mode)
    
    func registerTempFile(localURL: URL, remotePath: String, serverId: UUID) {
        tempFileMap[localURL] = TempFileContext(remotePath: remotePath, serverId: serverId)
    }
    
    func isTempFile(url: URL) -> Bool {
        return tempFileMap[url] != nil
    }
    
    func syncTempFile(localURL: URL) async {
        guard let context = tempFileMap[localURL] else { return }
        
        await MainActor.run { syncStatus = .syncing }
        
        do {
            let data = try Data(contentsOf: localURL)
            try await BackendService.shared.uploadRemoteFile(
                id: context.serverId.uuidString,
                path: context.remotePath,
                content: data
            )
            await MainActor.run { syncStatus = .upToDate }
            print("Successfully synced temp file: \(context.remotePath)")
        } catch {
            print("Temp Sync error: \(error)")
            await MainActor.run { syncStatus = .conflict }
        }
    }
    
    // MARK: - Close Remote Project
    
    func closeRemoteProject() {
        stopFileWatcher()
        currentWorkspace = nil
        syncStatus = .idle
    }
    
    // MARK: - File Watcher
    
    private func startFileWatcher(localPath: URL) {
        stopFileWatcher()
        
        let fileDescriptor = open(localPath.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global()
        )
        
        source.setEventHandler { [weak self] in
            // File changed, trigger sync
            print("File changed in remote workspace")
            // Note: Actual sync will happen on save via AppState
        }
        
        source.setCancelHandler {
            close(fileDescriptor)
        }
        
        source.resume()
        fileWatcher = source
    }
    
    private func stopFileWatcher() {
        fileWatcher?.cancel()
        fileWatcher = nil
    }
}

// MARK: - Models

struct RemoteWorkspaceConfig {
    let serverId: UUID
    let serverName: String
    let remotePath: String
    let localCachePath: URL
    let connectionType: RemoteConnectionConfig.ConnectionType
    var executionMode: ExecutionMode
}

enum ExecutionMode: String {
    case local = "Local"
    case remote = "Remote" // SSH only
}

enum SyncStatus {
    case idle
    case syncing
    case upToDate
    case conflict
    
    var description: String {
        switch self {
        case .idle: return "Not synced"
        case .syncing: return "Syncing..."
        case .upToDate: return "Up to date"
        case .conflict: return "Conflict"
        }
    }
    
    var icon: String {
        switch self {
        case .idle: return "circle"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .upToDate: return "checkmark.circle.fill"
        case .conflict: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .idle: return "gray"
        case .syncing: return "blue"
        case .upToDate: return "green"
        case .conflict: return "red"
        }
    }
}
