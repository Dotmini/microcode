import Foundation

/// Resolve the existing parent before appending a not-yet-created destination.
/// Foundation alone leaves symlinks unresolved when the leaf does not exist.
enum WorkspacePathPolicy {
    static func contains(_ path: String, in root: String) -> Bool {
        guard !path.isEmpty, !root.isEmpty,
              !(path as NSString).pathComponents.contains(".."),
              let base = canonical(root), let target = canonical(path) else { return false }
        return target.pathComponents.starts(with: base.pathComponents)
    }

    private static func canonical(_ path: String) -> URL? {
        var ancestor = URL(fileURLWithPath: path).standardizedFileURL
        var suffix: [String] = []
        let files = FileManager.default
        while !files.fileExists(atPath: ancestor.path) {
            // Do not treat a dangling symlink as a creatable plain directory.
            if (try? files.destinationOfSymbolicLink(atPath: ancestor.path)) != nil { return nil }
            guard ancestor.path != "/" else { return nil }
            suffix.insert(ancestor.lastPathComponent, at: 0)
            ancestor.deleteLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath()
        for component in suffix { resolved.appendPathComponent(component) }
        return resolved.standardizedFileURL
    }
}
