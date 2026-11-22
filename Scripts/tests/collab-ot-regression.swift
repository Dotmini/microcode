import Foundation

// ot1 co-editing regression: real CollabTextOperation.swift (operation algebra, client state machine, host log).
var failures = 0
func check(_ cond: Bool, _ name: String) {
    if cond { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)") }
}

// --- Algebra -------------------------------------------------------------------------------------------------
do {
    var op = CollabTextOperation()
    op.retain(3); op.insert("XY"); op.delete(2); op.retain(1)
    check((try? op.apply(to: "abcdef")) == "abcXYf", "apply retain/insert/delete")
    check(op.json.count == 4, "json shape")
    let round = try? CollabTextOperation(json: op.json)
    check(round == op, "json round trip")
    check((try? CollabTextOperation(json: [1, 0])) == nil, "zero component rejected")
    check((try? CollabTextOperation(json: [true])) == nil, "bool component rejected")
    check((try? op.apply(to: "abc")) == nil, "base length mismatch rejected")
}

do {
    let thai = "สวัสดี 👋🏽 world"
    let edited = "สวัสดีครับ 👋 world!"
    let op = CollabTextOperation.fromDiff(old: thai, new: edited)
    check((try? op.apply(to: thai)) == edited, "diff Thai + emoji")
    let swap = CollabTextOperation.fromDiff(old: "a😀b", new: "a😃b")
    if let inserted = swap.components.compactMap({ c -> String? in if case .insert(let s) = c { return s }; return nil }).first {
        check(inserted == "😃", "diff never splits a surrogate pair")
    } else { check(false, "diff never splits a surrogate pair") }
    check((try? swap.apply(to: "a😀b")) == "a😃b", "surrogate swap applies")
}

do {
    // Regression for the old line merger: two inserts on the same new line must not duplicate.
    let base = "line1\nline2\n"
    let first = CollabTextOperation.fromDiff(old: base, new: "line1\nfoo\nline2\n")
    let second = CollabTextOperation.fromDiff(old: "line1\nfoo\nline2\n", new: "line1\nfoobar\nline2\n")
    var server = CollabOTServerDocument(content: base, revision: 1)
    _ = try? server.receive(first, baseRevision: 1, authorId: "web", opId: "a")
    _ = try? server.receive(second, baseRevision: 2, authorId: "web", opId: "b")
    check(server.content == "line1\nfoobar\nline2\n", "sequential typing never duplicates a line")
    _ = try? server.receive(second, baseRevision: 2, authorId: "web", opId: "b")
    check(server.content == "line1\nfoobar\nline2\n" && server.revision == 3, "retransmitted opId is idempotent")
}

do {
    var a = CollabTextOperation(); a.retain(2); a.insert("A"); a.retain(3)
    var b = CollabTextOperation(); b.retain(2); b.insert("B"); b.retain(3)
    let (a1, b1) = try! CollabTextOperation.transform(a, b)
    let viaA = try! b1.apply(to: try! a.apply(to: "hello"))
    let viaB = try! a1.apply(to: try! b.apply(to: "hello"))
    check(viaA == viaB && viaA == "heABllo", "concurrent same-offset inserts converge, client first")

    var c = CollabTextOperation(); c.retain(1); c.delete(3); c.retain(1)
    var d = CollabTextOperation(); d.retain(2); d.delete(2); d.insert("Z"); d.retain(1)
    let (c1, d1) = try! CollabTextOperation.transform(c, d)
    check((try! d1.apply(to: try! c.apply(to: "hello"))) == (try! c1.apply(to: try! d.apply(to: "hello"))), "overlapping deletes converge")

    var e = CollabTextOperation(); e.retain(5); e.insert("!")
    let composed = try! a.compose(CollabTextOperation.fromDiff(old: "heAllo", new: "heAllo!"))
    check((try! composed.apply(to: "hello")) == "heAllo!", "compose")
    _ = e
}

do {
    var op = CollabTextOperation(); op.retain(2); op.insert("XX"); op.retain(3)
    check(op.transformIndex(1) == 1, "caret before insert stays")
    check(op.transformIndex(4) == 6, "caret after insert shifts")
    check(op.transformIndex(2) == 2, "caret at insert point stays before remote text")
    check(op.transformIndex(2, stickToInsertEnd: true) == 4, "caret can stick to insert end")
    var del = CollabTextOperation(); del.retain(1); del.delete(3); del.retain(1)
    check(del.transformIndex(3) == 1, "caret inside deleted range collapses to start")
}

do {
    var server = CollabOTServerDocument(content: "x", revision: 1, maxHistory: 16)
    for i in 0..<40 { _ = server.replaceContent("x\(i)", authorId: "host") }
    var op = CollabTextOperation(); op.retain(1); op.insert("y")
    do {
        _ = try server.receive(op, baseRevision: 1, authorId: "web", opId: nil)
        check(false, "stale base asks for resync")
    } catch CollabOTServerDocument.ReceiveError.staleBase {
        check(true, "stale base asks for resync")
    } catch { check(false, "stale base asks for resync") }
}

// --- Randomized convergence: host + 3 clients, random edits, random delivery order -------------------------------
struct SimClient {
    var id: String
    var text: String
    var ot: CollabOTClient
    var inbox: [CollabOTServerDocument.Commit] = []
    var sent = 0
}

var rng = SystemRandomNumberGenerator()
let alphabet = Array("ab\nก่ข😀 ")
func randomEdit(_ text: String) -> String {
    var units = Array(text.utf16)
    let roll = Int.random(in: 0..<10, using: &rng)
    let pos = units.isEmpty ? 0 : Int.random(in: 0...units.count, using: &rng)
    if roll < 6 || units.isEmpty {
        let s = String((0..<Int.random(in: 1...3, using: &rng)).map { _ in alphabet.randomElement(using: &rng)! })
        units.insert(contentsOf: Array(s.utf16), at: pos)
    } else {
        let end = min(units.count, pos + Int.random(in: 1...4, using: &rng))
        if pos < end { units.removeSubrange(pos..<end) }
    }
    var candidate = String(decoding: units, as: UTF16.self)
    if candidate.utf16.contains(0xFFFD) { candidate = text + "q" }
    return candidate
}

var allConverged = true
for round in 0..<300 {
    let start = "fn main() {\n  สวัสดี\n}\n"
    var server = CollabOTServerDocument(content: start, revision: 1)
    var clients = (0..<3).map { SimClient(id: "c\($0)", text: start, ot: CollabOTClient(revision: 1)) }
    // in-flight queue to the host: (clientIndex, op, baseRevision, opId)
    var toHost: [(Int, CollabTextOperation, Int, String)] = []
    var hostEditEvery = Int.random(in: 3...7, using: &rng)

    func send(_ ci: Int, _ op: CollabTextOperation) {
        clients[ci].sent += 1
        toHost.append((ci, op, clients[ci].ot.revision, "\(clients[ci].id)-\(clients[ci].sent)"))
    }

    for step in 0..<60 {
        let action = Int.random(in: 0..<4, using: &rng)
        if action == 0 || toHost.isEmpty && clients.allSatisfy({ $0.inbox.isEmpty }) {
            let ci = Int.random(in: 0..<3, using: &rng)
            let next = randomEdit(clients[ci].text)
            let op = CollabTextOperation.fromDiff(old: clients[ci].text, new: next)
            clients[ci].text = next
            if let out = try! clients[ci].ot.applyLocal(op) { send(ci, out) }
        } else if action == 1, !toHost.isEmpty {
            let (ci, op, base, opId) = toHost.removeFirst()
            let commit = try! server.receive(op, baseRevision: base, authorId: clients[ci].id, opId: opId)
            for k in clients.indices { clients[k].inbox.append(commit) }
        } else {
            let ci = Int.random(in: 0..<3, using: &rng)
            if !clients[ci].inbox.isEmpty {
                let commit = clients[ci].inbox.removeFirst()
                if commit.authorId == clients[ci].id {
                    if let next = clients[ci].ot.acknowledge(revision: commit.revision) { send(ci, next) }
                } else {
                    let local = try! clients[ci].ot.applyRemote(commit.operation, revision: commit.revision)
                    clients[ci].text = try! local.apply(to: clients[ci].text)
                }
            }
        }
        if step % hostEditEvery == 0 {
            // Host-side local edit (Mac host editor) goes straight into the log.
            if let commit = server.replaceContent(randomEdit(server.content), authorId: "host") {
                for k in clients.indices { clients[k].inbox.append(commit) }
            }
            hostEditEvery = Int.random(in: 3...7, using: &rng)
        }
    }
    // Drain everything.
    var guardSteps = 0
    while (!toHost.isEmpty || clients.contains(where: { !$0.inbox.isEmpty })) && guardSteps < 10_000 {
        guardSteps += 1
        if !toHost.isEmpty {
            let (ci, op, base, opId) = toHost.removeFirst()
            let commit = try! server.receive(op, baseRevision: base, authorId: clients[ci].id, opId: opId)
            for k in clients.indices { clients[k].inbox.append(commit) }
        }
        for ci in clients.indices where !clients[ci].inbox.isEmpty {
            let commit = clients[ci].inbox.removeFirst()
            if commit.authorId == clients[ci].id {
                if let next = clients[ci].ot.acknowledge(revision: commit.revision) { send(ci, next) }
            } else {
                let local = try! clients[ci].ot.applyRemote(commit.operation, revision: commit.revision)
                clients[ci].text = try! local.apply(to: clients[ci].text)
            }
        }
    }
    if !clients.allSatisfy({ $0.text == server.content && $0.ot.isSynchronized }) {
        allConverged = false
        print("diverged in round \(round)")
        break
    }
}
check(allConverged, "300 random 3-client + host sessions converge")

if failures > 0 { print("\(failures) failure(s)"); exit(1) }
print("ALL PASS")
