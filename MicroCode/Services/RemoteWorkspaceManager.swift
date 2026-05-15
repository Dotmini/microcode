//
//  RemoteWorkspaceManager.swift
//  MicroCode
//
//  Remote Workspace Management Service
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
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
        
        // Create local cache directory for this project
        let projectName = URL(fileURLWithPath: remotePath).lastPathComponent
        let localCachePath = cacheRootURL.appendingPathComponent("\(server.id.uuidString)_\(projectName)")
        
        // Clean existing cache
        try? FileManager.default.removeItem(at: localCachePath)
        try FileManager.default.createDirectory(at: localCachePath, withIntermediateDirectories: true)
        
        // Download project structure
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
    
    // MARK: - Download Project Structure
    
    private func downloadProjectStructure(serverId: String, remotePath: String, localPath: URL) async throws {
        // List all files recursively
        let files = try await BackendService.shared.listRemoteFiles(id: serverId, path: remotePath)
        
        // Download each file
        for file in files {
            if file.isDirectory {
                // Create directory locally
                let localDir = localPath.appendingPathComponent(file.name)
                try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
                
                // Recursively download subdirectory
                try await downloadProjectStructure(serverId: serverId, remotePath: file.path, localPath: localDir)
            } else {
                // Download file
                let fileData = try await BackendService.shared.downloadRemoteFile(id: serverId, path: file.path)
                let localFile = localPath.appendingPathComponent(file.name)
                try fileData.write(to: localFile)
            }
        }
    }
    
    // MARK: - File Synchronization
    
    func syncFile(localURL: URL) async {
        guard let workspace = currentWorkspace else { return }
        
        await MainActor.run {
            syncStatus = .syncing
        }
        
        do {
            // Calculate remote path
            let relativePath = localURL.path.replacingOccurrences(of: workspace.localCachePath.path, with: "")
            let remotePath = workspace.remotePath + relativePath
            
            // Read file content
            let data = try Data(contentsOf: localURL)
            
            // Upload to server
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
