import Foundation

/// Real-time co-editing protocol "ot1": operational transformation over plain text, wire-compatible with ot.js
/// `TextOperation` so the web portal, macOS and Windows clients share one algorithm.
///
/// * Offsets and lengths are UTF-16 code units (JavaScript and C# strings are UTF-16; Swift uses `utf16`).
/// * JSON form is an array: a positive integer retains n units, a negative integer deletes n units, and a string
///   inserts that text. Example: `[4, -2, "ab", 10]`.
/// * The host is authoritative: it orders operations into revisions, transforms late operations against everything
///   committed since the client's base revision, and broadcasts the result. Clients keep at most one operation in
///   flight (plus a composed buffer), exactly like ot.js `Client`.
struct CollabTextOperation: Equatable {
    enum Component: Equatable {
        case retain(Int)
        case insert(String)
        case delete(Int)
    }

    enum OTError: Error, Equatable {
        case baseLengthMismatch(expected: Int, actual: Int)
        case operationTooShort
        case operationTooLong
        case invalidJSON
    }

    private(set) var components: [Component] = []
    /// Length of the document this operation applies to.
    private(set) var baseLength = 0
    /// Length of the document after applying it.
    private(set) var targetLength = 0

    init() {}

    var isNoop: Bool {
        if components.isEmpty { return true }
        if components.count == 1, case .retain = components[0] { return true }
        return false
    }

    // MARK: Builders (canonical form: adjacent components merged, insert before delete)

    @discardableResult
    mutating func retain(_ n: Int) -> CollabTextOperation {
        guard n > 0 else { return self }
        baseLength += n
        targetLength += n
        if case .retain(let m)? = components.last {
            components[components.count - 1] = .retain(m + n)
        } else {
            components.append(.retain(n))
        }
        return self
    }

    @discardableResult
    mutating func insert(_ text: String) -> CollabTextOperation {
        guard !text.isEmpty else { return self }
        targetLength += text.utf16.count
        let count = components.count
        if case .insert(let existing)? = components.last {
            components[count - 1] = .insert(existing + text)
        } else if case .delete? = components.last {
            if count >= 2, case .insert(let existing) = components[count - 2] {
                components[count - 2] = .insert(existing + text)
            } else {
                components.insert(.insert(text), at: count - 1)
            }
        } else {
            components.append(.insert(text))
        }
        return self
    }

    @discardableResult
    mutating func delete(_ n: Int) -> CollabTextOperation {
        guard n > 0 else { return self }
        baseLength += n
        if case .delete(let m)? = components.last {
            components[components.count - 1] = .delete(m + n)
        } else {
            components.append(.delete(n))
        }
        return self
    }

    // MARK: Apply

    func apply(to document: String) throws -> String {
        let source = Array(document.utf16)
        guard source.count == baseLength else {
            throw OTError.baseLengthMismatch(expected: baseLength, actual: source.count)
        }
        var output: [UInt16] = []
        output.reserveCapacity(targetLength)
        var index = 0
        for component in components {
            switch component {
            case .retain(let n):
                output.append(contentsOf: source[index..<(index + n)])
                index += n
            case .insert(let text):
                output.append(contentsOf: text.utf16)
            case .delete(let n):
                index += n
            }
        }
        return String(decoding: output, as: UTF16.self)
    }

    /// Maps a caret/selection offset in the base document to the target document. Text inserted exactly at the
    /// offset leaves it in place (remote typing appears after your caret) unless `stickToInsertEnd` is true.
    func transformIndex(_ index: Int, stickToInsertEnd: Bool = false) -> Int {
        var newIndex = index
        var position = 0
        for component in components {
            if position > index { break }
            switch component {
            case .retain(let n):
                position += n
            case .insert(let text):
                if position < index || stickToInsertEnd {
                    newIndex += text.utf16.count
                }
            case .delete(let n):
                if position < index { newIndex -= min(n, index - position) }
                position += n
            }
        }
        return max(0, newIndex)
    }

    // MARK: Compose / transform (ot.js algorithms)

    /// Returns an operation equivalent to applying `self` then `other`.
    func compose(_ other: CollabTextOperation) throws -> CollabTextOperation {
        guard targetLength == other.baseLength else {
            throw OTError.baseLengthMismatch(expected: targetLength, actual: other.baseLength)
        }
        var result = CollabTextOperation()
        var ia = 0, ib = 0
        var a: Component? = components.first
        var b: Component? = other.components.first
        func nextA() { ia += 1; a = ia < components.count ? components[ia] : nil }
        func nextB() { ib += 1; b = ib < other.components.count ? other.components[ib] : nil }

        while a != nil || b != nil {
            if case .delete(let n)? = a { result.delete(n); nextA(); continue }
            if case .insert(let text)? = b { result.insert(text); nextB(); continue }
            guard let ca = a, let cb = b else { throw OTError.operationTooShort }
            switch (ca, cb) {
            case (.retain(let x), .retain(let y)):
                let m = min(x, y)
                result.retain(m)
                if x > y { a = .retain(x - y); nextB() } else if x == y { nextA(); nextB() } else { b = .retain(y - x); nextA() }
            case (.retain(let x), .delete(let y)):
                let m = min(x, y)
                result.delete(m)
                if x > y { a = .retain(x - y); nextB() } else if x == y { nextA(); nextB() } else { b = .delete(y - x); nextA() }
            case (.insert(let text), .retain(let y)):
                let len = text.utf16.count
                if len > y {
                    result.insert(Self.utf16Slice(text, 0, y)); a = .insert(Self.utf16Slice(text, y, len)); nextB()
                } else if len == y {
                    result.insert(text); nextA(); nextB()
                } else {
                    result.insert(text); b = .retain(y - len); nextA()
                }
            case (.insert(let text), .delete(let y)):
                let len = text.utf16.count
                if len > y { a = .insert(Self.utf16Slice(text, y, len)); nextB() } else if len == y { nextA(); nextB() } else { b = .delete(y - len); nextA() }
            default:
                throw OTError.operationTooShort
            }
        }
        return result
    }

    /// ot.js `transform(a, b)`: returns `(a', b')` with `apply(apply(S, a), b') == apply(apply(S, b), a')`.
    /// When both insert at the same offset, `a`'s text goes first — callers must use the same argument order on
    /// every side (client operation first, host operation second).
    static func transform(_ lhs: CollabTextOperation, _ rhs: CollabTextOperation) throws -> (CollabTextOperation, CollabTextOperation) {
        guard lhs.baseLength == rhs.baseLength else {
            throw OTError.baseLengthMismatch(expected: lhs.baseLength, actual: rhs.baseLength)
        }
        var aPrime = CollabTextOperation()
        var bPrime = CollabTextOperation()
        var ia = 0, ib = 0
        var a: Component? = lhs.components.first
        var b: Component? = rhs.components.first
        func nextA() { ia += 1; a = ia < lhs.components.count ? lhs.components[ia] : nil }
        func nextB() { ib += 1; b = ib < rhs.components.count ? rhs.components[ib] : nil }

        while a != nil || b != nil {
            if case .insert(let text)? = a {
                aPrime.insert(text); bPrime.retain(text.utf16.count); nextA(); continue
            }
            if case .insert(let text)? = b {
                aPrime.retain(text.utf16.count); bPrime.insert(text); nextB(); continue
            }
            guard let ca = a, let cb = b else { throw OTError.operationTooShort }
            switch (ca, cb) {
            case (.retain(let x), .retain(let y)):
                let m = min(x, y)
                aPrime.retain(m); bPrime.retain(m)
                if x > y { a = .retain(x - y); nextB() } else if x == y { nextA(); nextB() } else { b = .retain(y - x); nextA() }
            case (.delete(let x), .delete(let y)):
                if x > y { a = .delete(x - y); nextB() } else if x == y { nextA(); nextB() } else { b = .delete(y - x); nextA() }
            case (.delete(let x), .retain(let y)):
                let m = min(x, y)
                aPrime.delete(m)
                if x > y { a = .delete(x - y); nextB() } else if x == y { nextA(); nextB() } else { b = .retain(y - x); nextA() }
            case (.retain(let x), .delete(let y)):
                let m = min(x, y)
                bPrime.delete(m)
                if x > y { a = .retain(x - y); nextB() } else if x == y { nextA(); nextB() } else { b = .delete(y - x); nextA() }
            default:
                throw OTError.operationTooShort
            }
        }
        return (aPrime, bPrime)
    }

    // MARK: Diff

    /// Single-splice operation turning `old` into `new` (common prefix + suffix). Never splits a surrogate pair,
    /// so every inserted string is valid Unicode on the wire.
    static func fromDiff(old: String, new: String) -> CollabTextOperation {
        let a = Array(old.utf16)
        let b = Array(new.utf16)
        var prefix = 0
        let maxPrefix = min(a.count, b.count)
        while prefix < maxPrefix && a[prefix] == b[prefix] { prefix += 1 }
        if prefix > 0 && UTF16.isLeadSurrogate(a[prefix - 1]) {
            prefix -= 1
        }
        var suffix = 0
        let maxSuffix = min(a.count, b.count) - prefix
        while suffix < maxSuffix && a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        if suffix > 0 && UTF16.isTrailSurrogate(a[a.count - suffix]) {
            suffix -= 1
        }
        var op = CollabTextOperation()
        op.retain(prefix)
        let deleted = a.count - prefix - suffix
        let inserted = String(decoding: b[prefix..<(b.count - suffix)], as: UTF16.self)
        op.insert(inserted)
        op.delete(deleted)
        op.retain(suffix)
        return op
    }

    // MARK: JSON

    var json: [Any] {
        components.map { component -> Any in
            switch component {
            case .retain(let n): return n
            case .insert(let text): return text
            case .delete(let n): return -n
            }
        }
    }

    init(json raw: Any?) throws {
        guard let array = raw as? [Any] else { throw OTError.invalidJSON }
        for item in array {
            if let text = item as? String {
                insert(text)
            } else if let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                let value = number.intValue
                guard Double(value) == number.doubleValue, value != 0 else { throw OTError.invalidJSON }
                if value > 0 { retain(value) } else { delete(-value) }
            } else {
                throw OTError.invalidJSON
            }
        }
    }

    private static func utf16Slice(_ text: String, _ from: Int, _ to: Int) -> String {
        let units = Array(text.utf16)
        return String(decoding: units[from..<to], as: UTF16.self)
    }
}

/// Client half of ot1 (ot.js `Client` state machine): at most one operation awaits the host's ack; later local
/// edits compose into `buffer`. Remote operations are transformed against both before they touch the local text.
struct CollabOTClient: Equatable {
    private(set) var revision: Int
    private(set) var outstanding: CollabTextOperation?
    private(set) var buffer: CollabTextOperation?

    init(revision: Int) { self.revision = revision }

    var isSynchronized: Bool { outstanding == nil }

    /// A local edit. Returns the operation to send now (nil while another one is in flight).
    mutating func applyLocal(_ op: CollabTextOperation) throws -> CollabTextOperation? {
        guard !op.isNoop else { return nil }
        if outstanding == nil {
            outstanding = op
            return op
        }
        if let pending = buffer {
            buffer = try pending.compose(op)
        } else {
            buffer = op
        }
        return nil
    }

    /// Host acknowledged our outstanding operation as `revision`. Returns the buffered operation to send next.
    mutating func acknowledge(revision newRevision: Int) -> CollabTextOperation? {
        revision = newRevision
        outstanding = buffer
        buffer = nil
        return outstanding
    }

    /// Another participant's operation committed as `revision`. Returns it transformed for the local text.
    mutating func applyRemote(_ op: CollabTextOperation, revision newRevision: Int) throws -> CollabTextOperation {
        revision = newRevision
        var remote = op
        if let pending = outstanding {
            let (pendingPrime, remotePrime) = try CollabTextOperation.transform(pending, remote)
            outstanding = pendingPrime
            remote = remotePrime
        }
        if let pending = buffer {
            let (bufferPrime, remotePrime) = try CollabTextOperation.transform(pending, remote)
            buffer = bufferPrime
            remote = remotePrime
        }
        return remote
    }

    /// Drops all local state after the host sent a full snapshot (resync).
    mutating func reset(revision newRevision: Int) {
        revision = newRevision
        outstanding = nil
        buffer = nil
    }
}

/// Host half of ot1: the authoritative document and the operation log late clients are transformed against.
struct CollabOTServerDocument {
    struct Commit {
        let revision: Int
        let operation: CollabTextOperation
        let authorId: String
        let opId: String?
    }

    enum ReceiveError: Error, Equatable {
        /// The client's base revision fell out of the retained history — it must reload the file.
        case staleBase(current: Int)
        case invalid
    }

    private(set) var content: String
    private(set) var revision: Int
    private(set) var history: [Commit] = []
    let maxHistory: Int

    init(content: String, revision: Int, maxHistory: Int = 1_000) {
        self.content = content
        self.revision = revision
        self.maxHistory = max(16, maxHistory)
    }

    /// Commits a client operation made against `baseRevision`. A retransmitted `opId` returns the original commit.
    mutating func receive(_ op: CollabTextOperation, baseRevision: Int, authorId: String, opId: String?) throws -> Commit {
        if let opId, !opId.isEmpty, let existing = history.last(where: { $0.opId == opId && $0.authorId == authorId }) {
            return existing
        }
        guard baseRevision <= revision else { throw ReceiveError.invalid }
        let oldest = revision - history.count
        guard baseRevision >= oldest else { throw ReceiveError.staleBase(current: revision) }
        var transformed = op
        for commit in history where commit.revision > baseRevision {
            do {
                transformed = try CollabTextOperation.transform(transformed, commit.operation).0
            } catch {
                throw ReceiveError.invalid
            }
        }
        guard let next = try? transformed.apply(to: content) else { throw ReceiveError.invalid }
        return commit(transformed, resulting: next, authorId: authorId, opId: opId)
    }

    /// Records a change that did not arrive as an operation (host editor, disk write, legacy full-text edit).
    /// Returns nil when the text is unchanged.
    mutating func replaceContent(_ newContent: String, authorId: String) -> Commit? {
        guard newContent != content else { return nil }
        let op = CollabTextOperation.fromDiff(old: content, new: newContent)
        return commit(op, resulting: newContent, authorId: authorId, opId: nil)
    }

    /// Operations committed after `revision`, or nil if they are no longer retained.
    func operations(since baseRevision: Int) -> [Commit]? {
        guard baseRevision <= revision, baseRevision >= revision - history.count else { return nil }
        return history.filter { $0.revision > baseRevision }
    }

    private mutating func commit(_ op: CollabTextOperation, resulting next: String, authorId: String, opId: String?) -> Commit {
        revision += 1
        content = next
        let entry = Commit(revision: revision, operation: op, authorId: authorId, opId: opId)
        history.append(entry)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
        return entry
    }
}
