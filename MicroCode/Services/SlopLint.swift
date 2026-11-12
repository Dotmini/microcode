//
//  SlopLint.swift
//  MicroCode
//
//  Deterministic "AI slop" linter. Foundation-only so it can be tested stand-alone.
//  Rules are deliberately narrow: a noisy linter is slop of its own, so each rule matches a
//  specific, well-known tell and nothing broader. Severity guides what to fix first.
//

import Foundation

public enum SlopSeverity: Int, Comparable {
    case low = 0, medium = 1, high = 2
    public static func < (a: SlopSeverity, b: SlopSeverity) -> Bool { a.rawValue < b.rawValue }
    public var label: String { ["low", "medium", "high"][rawValue] }
}

public enum SlopDomain: String { case prose, code, ui, security }

public struct SlopFinding {
    public let rule: String
    public let severity: SlopSeverity
    public let domain: SlopDomain
    public let line: Int          // 1-based; 0 = whole document
    public let excerpt: String
    public let message: String
}

public enum SlopLint {

    // MARK: - File classification

    static let codeExtensions: Set<String> = [
        "swift", "m", "mm", "h", "c", "cc", "cpp", "rs", "go", "java", "kt", "kts", "py", "rb", "php",
        "js", "mjs", "cjs", "ts", "tsx", "jsx", "sh", "zsh", "bash", "dart", "cs", "scala", "ar"
    ]
    static let uiExtensions: Set<String> = ["html", "htm", "css", "scss", "sass", "less", "vue", "svelte", "tsx", "jsx", "astro"]
    static let proseExtensions: Set<String> = ["md", "markdown", "txt", "rst", "adoc", "text", ""]

    // MARK: - Rule model

    private struct LineRule {
        let id: String
        let severity: SlopSeverity
        let domain: SlopDomain
        let message: String
        let regex: NSRegularExpression
        /// Skip when the line also matches this (e.g. a justified exception).
        let unless: NSRegularExpression?
    }

    private static func rx(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programmer error caught by the unit run.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func rule(_ id: String, _ sev: SlopSeverity, _ domain: SlopDomain, _ message: String,
                             _ pattern: String, _ options: NSRegularExpression.Options = [], unless: String? = nil) -> LineRule {
        LineRule(id: id, severity: sev, domain: domain, message: message, regex: rx(pattern, options),
                 unless: unless.map { rx($0, options) })
    }

    private static let emoji = "[\\x{1F300}-\\x{1FAFF}\\x{2600}-\\x{27BF}\\x{2B50}\\x{2B06}\\x{23E9}-\\x{23FA}]"

    // MARK: Prose

    private static let proseRules: [LineRule] = [
        rule("P01", .high, .prose, "Filler opener or closer; start with the result.",
             "^\\s*(certainly|absolutely|of course|sure thing)[!,.]|^\\s*(great|good|excellent|fantastic) question|\\bi['’]?d be happy to\\b|\\bi hope (this|that) helps\\b|\\bfeel free to (reach out|ask)\\b|\\blet me know if (you|there)\\b|^\\s*in conclusion\\b|^\\s*overall,\\s",
             [.caseInsensitive]),
        rule("P02", .medium, .prose, "Hype vocabulary; name the concrete fact instead.",
             "\\b(delv(e|es|ing) into|tapestry|game[- ]?changer|cutting[- ]edge|seamless(ly)?|supercharg(e|es|ing)|unlock(s|ing)? the (power|potential)|elevate your|empower(s|ing)? (you|your|teams?|users?)|robust solution|state[- ]of[- ]the[- ]art solution|in today['’]s (fast[- ]paced|digital) (world|landscape)|navigate the (complex )?landscape)\\b",
             [.caseInsensitive]),
        rule("P03", .low, .prose, "Throat-clearing phrase; delete it and say the thing.",
             "\\bit(['’]s| is) (worth|important to) not(e|ing) that\\b|\\bit should be noted that\\b",
             [.caseInsensitive]),
        rule("P04", .low, .prose, "\"Not just X but Y\" frame; state Y directly.",
             "\\bnot (just|only|merely)\\b[^.\\n]{1,70}\\bbut (also )?\\b", [.caseInsensitive]),
        rule("P05", .medium, .prose, "Emoji in a heading.",
             "^\\s{0,3}#{1,6}\\s.*\(emoji)"),
        rule("P06", .medium, .prose, "Announces what is about to be said instead of saying it.",
             "^\\s*(in this (section|article|guide|post|document|tutorial),? (we|i)( will|['’]ll)|here['’]?s a (quick )?(summary|overview|breakdown|recap)|let['’]s (dive|break (this|it) down|explore))",
             [.caseInsensitive]),
        rule("P07", .high, .prose, "Thai filler closer or opener; give the result and the evidence.",
             "หวังว่า(ข้อมูล|คำตอบ|สิ่งนี้)(นี้)?จะเป็นประโยชน์|หากมี(ข้อสงสัย|คำถาม)เพิ่มเติม|(ยินดี|เต็มใจ)(เป็นอย่างยิ่ง)?ที่จะ(ช่วย|ตอบ)|คำถามที่ยอดเยี่ยม|แน่นอนครับ!|แน่นอนค่ะ!")
    ]

    // MARK: Code

    private static let codeRules: [LineRule] = [
        rule("C01", .high, .code, "Placeholder instead of an implementation.",
             "\\b(todo|fixme)\\b[: ]+\\s*implement|\\.\\.\\.\\s*(rest of|existing|other|remaining)\\s+(the\\s+)?(code|implementation|file|logic)|^\\s*(//|#)\\s*\\.\\.\\.\\s*$|fatalError\\(\"(not implemented|todo|unimplemented)[^\"]*\"\\)|raise NotImplementedError\\(\\s*\\)",
             [.caseInsensitive]),
        rule("C02", .medium, .code, "Comment restates the next line; explain why or delete.",
             "^\\s*(//|#)\\s*(Initiali[sz]e|Create|Set|Get|Return|Loop through|Iterate over|Increment|Decrement|Import|Define|Declare|Call)\\s+(the\\s+|a\\s+|an\\s+)?[A-Za-z_]+(\\s+[A-Za-z_]+){0,2}\\s*\\.?\\s*$"),
        rule("C03", .medium, .code, "Debug output left in code.",
             "\\b(print|console\\.log|NSLog|println!|fmt\\.Println|System\\.out\\.println)\\(\\s*[\"'](here|test|debug|asdf|hello|foo|xxx|wtf|\\d+)[\"' :!]",
             [.caseInsensitive]),
        rule("C04", .low, .code, "Force cast or force try; handle the failure.",
             "\\bas!\\s|\\btry!\\s", unless: "(//|#)\\s*(safe|invariant|checked)"),
        rule("C05", .medium, .code, "Vague function name; name the intent.",
             "\\b(func|def|function|fn)\\s+(handleStuff|doStuff|doSomething|processData|handleData|handleThing|helper|utilFunction)\\b"),
        rule("C06", .medium, .code, "Swallowed error: an empty catch hides failures.",
             "\\bcatch\\s*(\\([^)]*\\))?\\s*\\{\\s*\\}|\\bexcept(\\s+\\w+)?\\s*:\\s*pass\\b|\\bcatch\\s*\\{\\s*(//[^\\n]*)?\\s*\\}")
    ]

    // MARK: UI

    private static let purple = "(purple|violet|indigo|fuchsia|#(7c3aed|8b5cf6|6366f1|a855f7|9333ea|667eea|764ba2|6d28d9|4f46e5))"
    private static let blueOrPink = "(blue|cyan|sky|pink|rose|#(3b82f6|06b6d4|ec4899|2563eb|4facfe|00f2fe|f472b6|0ea5e9))"

    private static let uiRules: [LineRule] = [
        rule("U01", .medium, .ui, "Default purple-to-blue/pink gradient; derive colour from the subject.",
             "(gradient\\(.*\(purple).*\(blueOrPink)|gradient\\(.*\(blueOrPink).*\(purple)|from-\(purple)-?\\d*.*to-\(blueOrPink)-?\\d*)",
             [.caseInsensitive]),
        rule("U02", .medium, .ui, "Gradient text is a generated-page tell.",
             "(background-clip:\\s*text|-webkit-background-clip:\\s*text|\\bbg-clip-text\\b.*\\btext-transparent\\b|\\btext-transparent\\b.*\\bbg-clip-text\\b)",
             [.caseInsensitive]),
        rule("U03", .high, .ui, "Placeholder copy (lorem ipsum); write real content.", "lorem ipsum|dolor sit amet", [.caseInsensitive]),
        rule("U04", .low, .ui, "Invented company or person in UI copy.",
             "\\b(acme (inc|corp|co)\\b|john doe|jane doe|your company name|company name here)", [.caseInsensitive]),
        rule("U05", .low, .ui, "Emoji used as an icon; use the platform icon set.",
             "<(h[1-6]|li|button|span|div)\\b[^>]*>\\s*\(emoji)"),
        rule("U06", .low, .ui, "Tracked ALL-CAPS label (eyebrow) tell.",
             "(text-transform:\\s*uppercase.*letter-spacing:\\s*0?\\.(0[89]|[12]\\d*)em|letter-spacing:\\s*0?\\.(0[89]|[12]\\d*)em.*text-transform:\\s*uppercase|\\buppercase\\b.*\\btracking-(wide|wider|widest)\\b|\\btracking-(wide|wider|widest)\\b.*\\buppercase\\b)",
             [.caseInsensitive]),
        rule("U07", .low, .ui, "Arrow glyph appended to a call to action.",
             "\\b(Get started|Learn more|Read more|Sign up|Try it (free|now)|Explore)\\s*(→|->|&rarr;)")
    ]

    // MARK: Security (every file type)

    private static let securityRules: [LineRule] = [
        rule("S01", .high, .security, "Possible hard-coded secret; move it to the Keychain or environment and revoke it.",
             "(\\bsk-[A-Za-z0-9_\\-]{24,}|\\bAIza[0-9A-Za-z_\\-]{32,}|\\bghp_[A-Za-z0-9]{30,}|\\bxox[bap]-[A-Za-z0-9-]{20,}|-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----|\\beyJ[A-Za-z0-9_\\-]{15,}\\.[A-Za-z0-9_\\-]{15,}\\.[A-Za-z0-9_\\-]{10,})")
    ]

    // MARK: - Scan

    /// Scans `text`. `fileExtension` (without dot) selects the rule families; pass nil for free text.
    public static func scan(text: String, fileExtension: String? = nil) -> [SlopFinding] {
        // Documents that quote banned phrases on purpose (style guides, this linter's own skill) opt out in their header.
        if text.prefix(800).contains("slop:ignore-file") { return [] }
        let ext = (fileExtension ?? "").lowercased()
        var families: [[LineRule]] = [securityRules]
        let isCode = codeExtensions.contains(ext)
        let isUI = uiExtensions.contains(ext)
        let isProse = proseExtensions.contains(ext) || (!isCode && !isUI)
        if isProse { families.append(proseRules) }
        if isCode { families.append(codeRules) }
        if isUI { families.append(uiRules) }

        var findings: [SlopFinding] = []
        var inFence = false
        let lines = text.components(separatedBy: "\n")
        for (idx, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if isProse, line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle(); continue }
            // In markdown, fenced blocks are code samples; prose rules would mis-fire inside them.
            let skipProse = isProse && inFence && (ext == "md" || ext == "markdown")
            if line.count > 2_000 { continue }
            let range = NSRange(line.startIndex..., in: line)
            for family in families {
                for r in family {
                    if r.domain == .prose && skipProse { continue }
                    guard r.regex.firstMatch(in: line, options: [], range: range) != nil else { continue }
                    if let u = r.unless, u.firstMatch(in: line, options: [], range: range) != nil { continue }
                    findings.append(SlopFinding(rule: r.id, severity: r.severity, domain: r.domain, line: idx + 1,
                                                excerpt: String(line.trimmingCharacters(in: .whitespaces).prefix(110)),
                                                message: r.message))
                }
            }
        }

        // Multi-line: commented-out code blocks (2+ consecutive lines).
        if isCode {
            findings += commentedOutCode(lines: lines)
        }
        // Document-level
        if isProse { findings += emDashDensity(text: text) }
        if isUI && (ext == "css" || ext == "scss" || ext == "html" || ext == "vue" || ext == "svelte") {
            let lower = text.lowercased()
            if lower.contains("outline: none") || lower.contains("outline:none") || lower.contains("outline: 0") {
                if !lower.contains("focus-visible") && !lower.contains(":focus") {
                    findings.append(SlopFinding(rule: "U08", severity: .medium, domain: .ui, line: 0,
                                                excerpt: "outline removed",
                                                message: "Focus outline removed with no :focus-visible replacement; keyboard users lose their place."))
                }
            }
        }
        return findings.sorted { ($0.severity, -$0.line) > ($1.severity, -$1.line) }
    }

    private static let codeLikeComment = rx("^\\s*(//|#)\\s*(let|var|func|if|else|for|while|return|import|class|struct|const|def|print\\(|self\\.|await |try )\\b")

    private static func commentedOutCode(lines: [String]) -> [SlopFinding] {
        var out: [SlopFinding] = []
        var run: [Int] = []
        func flush() {
            if run.count >= 2, let first = run.first {
                out.append(SlopFinding(rule: "C07", severity: .medium, domain: .code, line: first + 1,
                                       excerpt: String(lines[first].trimmingCharacters(in: .whitespaces).prefix(110)),
                                       message: "\(run.count) lines of commented-out code; delete it (version control remembers)."))
            }
            run = []
        }
        for (i, l) in lines.enumerated() {
            if codeLikeComment.firstMatch(in: l, options: [], range: NSRange(l.startIndex..., in: l)) != nil {
                run.append(i)
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    private static func emDashDensity(text: String) -> [SlopFinding] {
        let dashes = text.filter { $0 == "—" }.count
        guard dashes >= 4, text.count > 0 else { return [] }
        let per1000 = Double(dashes) / Double(text.count) * 1000
        guard per1000 > 4 else { return [] }
        return [SlopFinding(rule: "P08", severity: .low, domain: .prose, line: 0,
                            excerpt: "\(dashes) em dashes in \(text.count) characters",
                            message: "Em-dash density is high; use full stops, commas or colons.")]
    }

    // MARK: - Report

    public static func report(_ findings: [SlopFinding], file: String? = nil, limit: Int = 60) -> String {
        guard !findings.isEmpty else { return "slop_check: clean" + (file.map { " (\($0))" } ?? "") }
        let high = findings.filter { $0.severity == .high }.count
        let med = findings.filter { $0.severity == .medium }.count
        let low = findings.filter { $0.severity == .low }.count
        var lines = ["slop_check: \(findings.count) finding(s) — \(high) high, \(med) medium, \(low) low" + (file.map { " in \($0)" } ?? "")]
        for f in findings.prefix(limit) {
            let loc = f.line > 0 ? ":\(f.line)" : ""
            lines.append("- [\(f.severity.label)] \(f.rule) \(file ?? "text")\(loc) — \(f.message)\n    \(f.excerpt)")
        }
        if findings.count > limit { lines.append("… \(findings.count - limit) more not shown") }
        return lines.joined(separator: "\n")
    }
}
