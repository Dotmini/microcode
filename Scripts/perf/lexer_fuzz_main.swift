// Differential fuzz: IncrementalLexer/SyntaxCache vs from-scratch StateMachineLexer.tokenize.
//
// Usage: lexfuzz [--edits N] [--seed S] [--batch B] [--kinds all|simple] [--stop-on-fail]
//   --edits  random edits per language (default 2000, 3 languages => >= 6000 total)
//   --batch  max number of edits applied between two retokenize calls (default 3; 1 = retokenize after each edit)
//   --kinds  simple = no multi-line same-line-count replacement (used to validate the harness against the ORIGINAL code)
//
// The harness replicates SyntaxHighlightingEngine.processEdit's line bookkeeping (start line, removed/added line
// counts, cachedLineOffsets maintenance) verbatim, then drives the cache exactly as the engine does.
import Foundation

struct SplitMix64 {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
    mutating func chance(_ percent: Int) -> Bool { int(100) < percent }
    mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
}

var args = Array(CommandLine.arguments.dropFirst())
func opt(_ name: String, _ def: String) -> String {
    if let i = args.firstIndex(of: name), i + 1 < args.count { return args[i + 1] }
    return def
}
let editsPerLang = Int(opt("--edits", "2000"))!
let seed = UInt64(opt("--seed", "20260211"))!
let maxBatch = Int(opt("--batch", "3"))!
let simpleKinds = opt("--kinds", "all") == "simple"
let stopOnFail = args.contains("--stop-on-fail")

// MARK: - Language fixtures

struct Lang {
    let name: String
    let make: () -> StateMachineLexer
    let snippets: [String]
    let blockOpen: String
    let blockClose: String
}

let langs: [Lang] = [
    Lang(name: "swift", make: createSwiftLexer, snippets: [
        "let x = 42", "var name: String = \"hello \\(world)\"", "func foo(_ a: Int) -> Int { return a * 2 }",
        "// line comment with /* inside", "/// doc comment", "struct Point { var x: Double }", "    if x > 3 && y < 4 {",
        "}", "import Foundation", "let s = \"\"\"", "multiline string text", "\"\"\"", "@MainActor final class Foo: Bar {",
        "case .a(let v): print(v)", "let thai = \"สวัสดีชาวโลก 😀\"", "#if DEBUG", "#endif", "x += 1 // trailing", "",
        "    guard let y = z else { return }", "let r = /abc/", "let f = 3.14e-2 + 0xFF",
    ], blockOpen: "/*", blockClose: "*/"),
    Lang(name: "javascript", make: createJavaScriptLexer, snippets: [
        "const x = 42;", "let s = `template ${value} text`;", "function foo(a, b) { return a + b; }",
        "// comment /* not block", "/* block start", "block end */", "class A extends B { constructor() { super(); } }",
        "const re = /ab+c/gi;", "import { a } from 'mod';", "export default async () => await fetch(\"/api\");",
        "`multi", "line template`", "if (x === null) { console.log('hi'); }", "var ก = 'ภาษาไทย 😀';", "", "}", "});",
        "obj.prop.method(1, 2, 3);", "x = y ? 1 : 2;",
    ], blockOpen: "/*", blockClose: "*/"),
    Lang(name: "python", make: createPythonLexer, snippets: [
        "def foo(a, b=2):", "    return a + b", "class A(B):", "    \"\"\"docstring start", "    docstring end\"\"\"",
        "x = '''multi", "line''' + 'z'", "# comment with \"quote", "import os, sys", "print(f\"value {x}\")", "if x is None:",
        "    pass", "s = 'it\\'s'", "lst = [1, 2.5, 0x1F, 1e3]", "@decorator", "async def f(): await g()", "", "ชื่อ = \"ไทย\"",
        "while True: break",
    ], blockOpen: "\"\"\"", blockClose: "\"\"\""),
]

let charAlphabet: [String] = [
    "a", "b", "z", "X", "7", "0", " ", " ", "\t", "/", "*", "\"", "'", "`", "#", "\\", "{", "}", "(", ")", ".", "_", "@",
    "=", "+", "-", ";", ",", "ก", "ไ", "😀", "$", "<", ">", "!", "\n",
]

func makeDocument(lang: Lang, lines: Int, rng: inout SplitMix64) -> String {
    var out: [String] = []
    for _ in 0..<lines { out.append(rng.pick(lang.snippets)) }
    return out.joined(separator: "\n") + (rng.chance(50) ? "\n" : "")
}

// MARK: - Engine bookkeeping replica (SyntaxHighlightingEngine.processEdit / setDocument)

func engineLineOffsets(_ content: String) -> [Int] {
    var newOffsets: [Int] = [0]
    let nsString = content as NSString
    var index = 0
    let length = nsString.length
    while index < length {
        var lineEnd = 0
        var contentEnd = 0
        nsString.getLineStart(nil, end: &lineEnd, contentsEnd: &contentEnd, for: NSRange(location: index, length: 0))
        if lineEnd > index {
            index = lineEnd
            let hasSeparator = contentEnd < lineEnd
            if index < length || hasSeparator { newOffsets.append(index) }
        } else { break }
    }
    return newOffsets
}

struct EngineReplica {
    var content: String
    var offsets: [Int]
    let lexer: IncrementalLexer
    
    init(content: String, lexer: IncrementalLexer) {
        self.content = content
        self.offsets = engineLineOffsets(content)
        self.lexer = lexer
        lexer.initialize(with: content)
    }
    
    /// Mirrors processEdit(range:changeInLength:newContent:)
    mutating func processEdit(location: Int, oldLength: Int, newText: String) {
        let nsOld = content as NSString
        let nsNewText = newText as NSString
        let newContent = nsOld.replacingCharacters(in: NSRange(location: location, length: oldLength), with: newText)
        let range = NSRange(location: location, length: nsNewText.length)
        let changeInLength = nsNewText.length - oldLength
        
        let originalLength = max(0, range.length - changeInLength)
        let oldRange = NSRange(location: range.location, length: min(originalLength, nsOld.length - range.location))
        
        var startLine = 0
        var lower = 0
        var upper = offsets.count
        while lower < upper {
            let mid = lower + (upper - lower) / 2
            if offsets[mid] <= oldRange.location { lower = mid + 1 } else { upper = mid }
        }
        startLine = max(0, lower - 1)
        
        let removedText = nsOld.substring(with: oldRange)
        let removedLinesCount = removedText.components(separatedBy: "\n").count - 1
        let nsNew = newContent as NSString
        let safeAddedLocation = max(0, min(range.location, nsNew.length))
        let safeAddedLength = max(0, min(range.length, nsNew.length - safeAddedLocation))
        let addedText = nsNew.substring(with: NSRange(location: safeAddedLocation, length: safeAddedLength))
        let addedLinesCount = addedText.components(separatedBy: "\n").count - 1
        
        do {
            let removeStart = startLine + 1
            let removeEnd = startLine + 1 + removedLinesCount
            if removeStart < offsets.count {
                let safeEnd = min(removeEnd, offsets.count)
                offsets.removeSubrange(removeStart..<safeEnd)
            }
            var addedOffsets: [Int] = []
            let currentAddedOffset = range.location
            let nsAdded = addedText as NSString
            var index = 0
            let length = nsAdded.length
            while index < length {
                var lineEnd = 0
                var contentEnd = 0
                nsAdded.getLineStart(nil, end: &lineEnd, contentsEnd: &contentEnd, for: NSRange(location: index, length: 0))
                if lineEnd > index {
                    index = lineEnd
                    let hasSeparator = contentEnd < lineEnd
                    if index < length || hasSeparator { addedOffsets.append(currentAddedOffset + index) }
                } else { break }
            }
            if !addedOffsets.isEmpty { offsets.insert(contentsOf: addedOffsets, at: startLine + 1) }
            let shiftStart = startLine + 1 + addedOffsets.count
            if shiftStart < offsets.count {
                for i in shiftStart..<offsets.count { offsets[i] += changeInLength }
            }
        }
        
        content = newContent
        lexer.cache.handleDocumentChange(changeStart: startLine, linesRemoved: removedLinesCount, linesAdded: addedLinesCount, charDelta: changeInLength)
        lexer.cache.markDirty(line: startLine)
    }
}

// MARK: - Edit generation

struct Edit { var location: Int; var oldLength: Int; var newText: String; var kind: String }

func randomEdit(text: String, lang: Lang, rng: inout SplitMix64) -> Edit {
    let ns = text as NSString
    let len = ns.length
    func clampLoc(_ l: Int) -> Int { max(0, min(l, len)) }
    // keep edits on composed-character boundaries so that we never split a surrogate pair
    func snap(_ l: Int) -> Int {
        let l = clampLoc(l)
        if l >= len { return len }
        let r = ns.rangeOfComposedCharacterSequence(at: l)
        return r.location
    }
    func lineBounds(_ l: Int) -> NSRange { ns.lineRange(for: NSRange(location: min(l, max(0, len - 1)), length: 0)) }
    
    let roll = rng.int(100)
    switch roll {
    case 0..<28: // single char insert
        return Edit(location: snap(rng.int(len + 1)), oldLength: 0, newText: rng.pick(charAlphabet), kind: "char")
    case 28..<40: // Enter
        return Edit(location: snap(rng.int(len + 1)), oldLength: 0, newText: "\n", kind: "enter")
    case 40..<52: // backspace
        if len == 0 { return Edit(location: 0, oldLength: 0, newText: "x", kind: "char") }
        let at = snap(rng.int(len))
        let r = ns.rangeOfComposedCharacterSequence(at: at)
        return Edit(location: r.location, oldLength: r.length, newText: "", kind: "backspace")
    case 52..<62: // multi-line paste
        let n = 2 + rng.int(7)
        var parts: [String] = []
        for _ in 0..<n { parts.append(rng.pick(lang.snippets)) }
        return Edit(location: snap(rng.int(len + 1)), oldLength: 0, newText: parts.joined(separator: "\n") + (rng.chance(50) ? "\n" : ""), kind: "paste")
    case 62..<70: // delete line
        if len == 0 { return Edit(location: 0, oldLength: 0, newText: "\n", kind: "enter") }
        let r = lineBounds(rng.int(len))
        return Edit(location: r.location, oldLength: r.length, newText: "", kind: "deleteLine")
    case 70..<80: // block comment / multiline string open or close
        let marker = rng.chance(50) ? lang.blockOpen : lang.blockClose
        return Edit(location: snap(rng.int(len + 1)), oldLength: 0, newText: marker, kind: "blockMarker")
    case 80..<86: // delete a block marker if present, else random small delete
        for marker in [lang.blockOpen, lang.blockClose] {
            var searchRange = NSRange(location: 0, length: len)
            var hits: [NSRange] = []
            var guardCount = 0
            while guardCount < 400 {
                let found = ns.range(of: marker, options: [], range: searchRange)
                if found.location == NSNotFound { break }
                hits.append(found)
                let next = found.location + found.length
                searchRange = NSRange(location: next, length: len - next)
                guardCount += 1
            }
            if !hits.isEmpty && rng.chance(70) {
                let h = rng.pick(hits)
                return Edit(location: h.location, oldLength: h.length, newText: "", kind: "deleteMarker")
            }
        }
        let a = snap(rng.int(len + 1))
        let b = snap(a + rng.int(40))
        return Edit(location: a, oldLength: b - a, newText: "", kind: "deleteRange")
    case 86..<93: // delete random (possibly multi-line) range
        let a = snap(rng.int(len + 1))
        let b = snap(min(len, a + rng.int(300)))
        return Edit(location: a, oldLength: b - a, newText: "", kind: "deleteRange")
    default: // multi-line replacement
        let a = snap(rng.int(len + 1))
        let b = snap(min(len, a + rng.int(300)))
        let selected = ns.substring(with: NSRange(location: a, length: b - a))
        let selectedNewlines = selected.components(separatedBy: "\n").count - 1
        var replacement: String
        if !simpleKinds && rng.chance(60) {
            // same number of lines, different content: the same-line-count multi-line case
            var parts: [String] = []
            for _ in 0..<(selectedNewlines + 1) { parts.append(rng.pick(lang.snippets)) }
            replacement = parts.joined(separator: "\n")
            return Edit(location: a, oldLength: b - a, newText: replacement, kind: "replaceSameLines")
        }
        let n = rng.int(5)
        var parts: [String] = []
        for _ in 0..<(n + 1) { parts.append(rng.pick(lang.snippets)) }
        replacement = parts.joined(separator: "\n")
        return Edit(location: a, oldLength: b - a, newText: replacement, kind: "replace")
    }
}

// MARK: - Comparison

struct Flat: Equatable, CustomStringConvertible {
    var type: SyntaxTokenType
    var start: Int
    var length: Int
    var line: Int
    var column: Int
    var description: String { "\(type)@\(start)+\(length) L\(line):\(column)" }
}

func flat(_ tokens: [SyntaxToken]) -> [Flat] {
    tokens.map { Flat(type: $0.type, start: $0.range.startOffset, length: $0.range.endOffset - $0.range.startOffset, line: $0.range.startLine, column: $0.range.startColumn) }
}

func firstDifference(_ a: [Flat], _ b: [Flat]) -> String {
    let n = min(a.count, b.count)
    for i in 0..<n where a[i] != b[i] { return "first diff at token #\(i): incremental=\(a[i]) reference=\(b[i]) (counts \(a.count) vs \(b.count))" }
    return "count mismatch incremental=\(a.count) reference=\(b.count)"
}

// MARK: - Main loop

#if NEWAPI
// Compact tag round trip
for t in SyntaxTokenType.allCases { precondition(SyntaxTokenType.compactTable[Int(t.compactIndex)] == t, "compact tag round trip failed for \(t)") }
precondition(Set(SyntaxTokenType.allCases.map { $0.compactIndex }).count == SyntaxTokenType.allCases.count, "compact tags not unique")
#endif

var totalEdits = 0
var totalChecks = 0
var totalFailures = 0
var kindCounts: [String: Int] = [:]
var perLang: [(String, Int, Int, Int)] = []
var incrementalSlices = 0, incrementalFull = 0, parallelColdOpens = 0
var rng = SplitMix64(s: seed)

for lang in langs {
    var langEdits = 0, langChecks = 0, langFailures = 0
    var sessionIndex = 0
    while langEdits < editsPerLang {
        sessionIndex += 1
        let docLines = rng.pick([30, 120, 450, 900])
        var text = makeDocument(lang: lang, lines: docLines, rng: &rng)
        let lexer = IncrementalLexer(lexer: lang.make())
        let reference = lang.make()
        var engine = EngineReplica(content: text, lexer: lexer)
        if docLines >= 450 { parallelColdOpens += 1 }
        
        func verify(label: String) -> Bool {
            let useIncremental = rng.chance(50)
            let expected = flat(reference.tokenize(engine.content).tokens)
            var got: [Flat] = []
            var sliceCheck: String? = nil
            #if NEWAPI
            if useIncremental {
                let update = lexer.retokenizeDirtyRegionsIncremental(in: engine.content, lineStarts: engine.offsets)
                if update.isFullDocument {
                    incrementalFull += 1
                    got = flat(update.tokens)
                } else {
                    incrementalSlices += 1
                    // the slice must be exactly the reference tokens that live inside dirtyCharRange
                    if let r = update.dirtyCharRange {
                        let want = expected.filter { $0.start >= r.location && $0.start + $0.length <= r.location + r.length }
                        if flat(update.tokens) != want { sliceCheck = "slice mismatch in range \(r): \(firstDifference(flat(update.tokens), want))" }
                    }
                    got = flat(lexer.cache.allSyntaxTokens(lineStarts: engine.offsets))
                }
            } else {
                got = flat(lexer.retokenizeDirtyRegions(in: engine.content, lineStarts: engine.offsets))
            }
            #else
            if useIncremental {
                let update = lexer.retokenizeDirtyRegionsIncremental(in: engine.content)
                if update.isFullDocument {
                    incrementalFull += 1
                    got = flat(update.tokens)
                } else {
                    incrementalSlices += 1
                    if let r = update.dirtyCharRange {
                        let want = expected.filter { $0.start >= r.location && $0.start + $0.length <= r.location + r.length }
                        if flat(update.tokens) != want { sliceCheck = "slice mismatch in range \(r): \(firstDifference(flat(update.tokens), want))" }
                    }
                    got = flat(lexer.cache.allSyntaxTokens())
                }
            } else {
                got = flat(lexer.retokenizeDirtyRegions(in: engine.content))
            }
            #endif
            totalChecks += 1; langChecks += 1
            if got != expected || sliceCheck != nil {
                totalFailures += 1; langFailures += 1
                if langFailures <= 5 {
                    print("FAIL [\(lang.name)] \(label): \(sliceCheck ?? firstDifference(got, expected))")
                }
                return false
            }
            return true
        }
        
        // cold-open verification (first retokenize, parallel for >= 400 lines)
        let coldOK = verify(label: "cold open (\(docLines) lines)")
        if !coldOK && stopOnFail { break }
        
        var sessionEdits = 0
        var sessionOK = coldOK
        while sessionEdits < 150 && langEdits < editsPerLang && sessionOK {
            let batch = 1 + rng.int(maxBatch)
            var desc: [String] = []
            for _ in 0..<batch {
                let e = randomEdit(text: engine.content, lang: lang, rng: &rng)
                engine.processEdit(location: e.location, oldLength: e.oldLength, newText: e.newText)
                kindCounts[e.kind, default: 0] += 1
                desc.append("\(e.kind)@\(e.location)-\(e.oldLength)->\(e.newText.debugDescription.prefix(40))")
                totalEdits += 1; langEdits += 1; sessionEdits += 1
            }
            // sanity: replica offsets agree with a fresh scan
            if engine.offsets != engineLineOffsets(engine.content) {
                print("HARNESS NOTE: replica line offsets drifted after \(desc) (engine bookkeeping)")
                engine.offsets = engineLineOffsets(engine.content)
            }
            sessionOK = verify(label: "after edits \(desc)")
            if !sessionOK && stopOnFail { break }
        }
        if !sessionOK && stopOnFail { break }
        text = engine.content
    }
    perLang.append((lang.name, langEdits, langChecks, langFailures))
}

print("---- differential fuzz summary (seed \(seed), batch<=\(maxBatch), kinds=\(simpleKinds ? "simple" : "all")) ----")
for (n, e, c, f) in perLang { print("\(n): edits=\(e) comparisons=\(c) failures=\(f)") }
print("TOTAL edits=\(totalEdits) comparisons=\(totalChecks) failures=\(totalFailures)")
print("edit kinds:", kindCounts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
print("incremental slice results=\(incrementalSlices) full-document results=\(incrementalFull) cold opens >=450 lines (parallel path)=\(parallelColdOpens)")
print(totalFailures == 0 ? "RESULT: PASS (100%)" : "RESULT: FAIL")
exit(totalFailures == 0 ? 0 : 1)
