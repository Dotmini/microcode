//
//  ScienceWorkspaceStore.swift
//  MicroCode
//
//  Keeps research workspaces and artifacts out of the Editor workspace.
//

import Foundation
import Combine

@MainActor
final class ScienceWorkspaceStore: ObservableObject {
    static let shared = ScienceWorkspaceStore()

    @Published private(set) var root: URL?
    @Published private(set) var selectedArtifact: URL?

    private let rootKey = "microcode_science_workspace_root"
    private let artifactKey = "microcode_science_selected_artifact"

    private init() {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: rootKey), FileManager.default.fileExists(atPath: path) {
            root = URL(fileURLWithPath: path).standardizedFileURL
        }
        if let path = defaults.string(forKey: artifactKey), FileManager.default.fileExists(atPath: path),
           isInsideRoot(URL(fileURLWithPath: path).standardizedFileURL) {
            selectedArtifact = URL(fileURLWithPath: path).standardizedFileURL
        }
    }

    func selectWorkspace(_ url: URL) {
        let normalized = url.standardizedFileURL
        root = normalized
        selectedArtifact = nil
        UserDefaults.standard.set(normalized.path, forKey: rootKey)
        UserDefaults.standard.removeObject(forKey: artifactKey)
    }

    func selectArtifact(_ url: URL) -> Bool {
        let normalized = url.standardizedFileURL
        guard isInsideRoot(normalized) else { return false }
        selectedArtifact = normalized
        UserDefaults.standard.set(normalized.path, forKey: artifactKey)
        return true
    }

    func clearWorkspace() {
        root = nil
        selectedArtifact = nil
        UserDefaults.standard.removeObject(forKey: rootKey)
        UserDefaults.standard.removeObject(forKey: artifactKey)
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        guard let root else { return false }
        let path = url.path
        return path == root.path || path.hasPrefix(root.path + "/")
    }
}
