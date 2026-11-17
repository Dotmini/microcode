import Foundation

/// Size + modification time of a file as the agent last saw it.
struct FileStamp: Equatable {
    let modified: TimeInterval
    let size: Int64
}

/// Edit-time staleness guard. Remembers each file's stamp when an agent reads or writes it; an edit to a file
/// that changed on disk since then (user typing in the editor, another chat or agent, git checkout, a build)
/// is refused until the agent re-reads it — otherwise its edit, computed from old content, silently
/// overwrites those changes. Files the agent never read are not affected (no read-before-write requirement).
final class FileFreshnessRegistry: @unchecked Sendable {
    static let shared = FileFreshnessRegistry()

    private let lock = NSLock()
    private var stamps: [String: FileStamp] = [:]
    private let stat: (String) -> FileStamp?

    init(stat: @escaping (String) -> FileStamp? = FileFreshnessRegistry.diskStamp) {
        self.stat = stat
    }

    static func diskStamp(_ path: String) -> FileStamp? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 else { return nil }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? -1
        return FileStamp(modified: modified, size: size)
    }

    private static func key(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    /// Record the file's current stamp (after a successful read or the agent's own write).
    func noteObserved(_ path: String) {
        let key = Self.key(path)
        let current = stat(key)
        lock.lock()
        stamps[key] = current
        lock.unlock()
    }

    /// Non-nil when the file was seen before and has changed on disk since.
    func staleReason(forEditing path: String) -> String? {
        let key = Self.key(path)
        lock.lock()
        let recorded = stamps[key]
        lock.unlock()
        guard let recorded else { return nil }
        guard let current = stat(key) else { return nil } // deleted: let the tool report it
        if current == recorded { return nil }
        let name = (key as NSString).lastPathComponent
        return "`\(name)` changed on disk after you last read it (edited in the IDE, by another agent, or by a tool). Re-read it with file_read and apply your change to the current content — editing from the old copy would overwrite those changes."
    }

    func forget(_ path: String) {
        let key = Self.key(path)
        lock.lock()
        stamps.removeValue(forKey: key)
        lock.unlock()
    }
}
