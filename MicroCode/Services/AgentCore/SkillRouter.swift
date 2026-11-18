import Foundation
import NaturalLanguage

// Skill routing (Agent Skills progressive disclosure, agentskills.io "How to add skills support").
//
// The model decides which skill applies, from a stable catalog of skill names + descriptions. The harness no
// longer guesses from keywords: the old router gave every enabled skill free points, matched descriptions by
// substring with no stopwords, treated short names like "uv" as mentions inside "uvicorn", ignored the project's
// stack, and could not read Thai — so unrelated skills were listed as "MUST read" or injected outright.
// Full instructions are injected up front only when the user invokes a skill (`/skill-id` or `$skill-id`).
// `skill_engine match` searches the long tail with BM25 over whole words (Thai segmented), gated by platform.

/// Where a skill came from; decides its place in the always-listed catalog (lower tiers are listed first).
enum SkillCatalogTier: Int, Comparable {
    case builtin = 0
    case user = 1
    case ecosystem = 2
    case pluginCache = 3

    static func < (lhs: SkillCatalogTier, rhs: SkillCatalogTier) -> Bool { lhs.rawValue < rhs.rawValue }

    static func classify(path: String, isBuiltin: Bool, isProjectSkill: Bool, home: String = NSHomeDirectory()) -> SkillCatalogTier {
        if isBuiltin { return .builtin }
        if isProjectSkill { return .user }
        if path.contains("/plugins/") { return .pluginCache }
        let userRoots = [".microcode/", ".agents/skills/", ".claude/skills/", ".codex/skills/"].map { "\(home)/\($0)" }
        if userRoots.contains(where: { path.hasPrefix($0) }) { return .user }
        return .ecosystem
    }
}

/// A skill as the router sees it (no UI types).
struct SkillRouteRecord: Equatable {
    let id: String
    let name: String
    let description: String
    var isEnabled: Bool = true
    var tier: SkillCatalogTier = .user
    var isScience: Bool = false

    var family: String { SkillText.family(of: id) }
}

// MARK: - Text normalization

enum SkillText {
    /// First segment of the id (`dart-add-unit-test` → `dart`), used for platform gating and the hidden summary.
    static func family(of id: String) -> String {
        String(id.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." || $0 == ":" }).first ?? "")
    }

    /// Light, symmetric stemmer: the same word forms collapse in queries and descriptions (test/tests/testing,
    /// debug/debugging, create/created, image/images, library/libraries).
    static func stem(_ word: String) -> String {
        var w = word
        if w.count > 4 && w.hasSuffix("ies") {
            w = String(w.dropLast(3)) + "y"
        } else if w.count > 5 && w.hasSuffix("ing") {
            w = String(w.dropLast(3))
        } else if w.count > 4 && w.hasSuffix("ed") {
            w = String(w.dropLast(2))
        } else if w.count > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") {
            w = String(w.dropLast())
        }
        if w.count > 4 && w.hasSuffix("e") { w = String(w.dropLast()) }
        if w.count > 3, let last = w.last, let previous = w.dropLast().last, last == previous, !"aeiou".contains(last) {
            w = String(w.dropLast())
        }
        return w
    }

    /// Words that carry no intent on their own; matching them is what made unrelated skills rank.
    static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "if", "then", "else", "for", "to", "of", "in", "on", "at", "by", "with",
        "from", "into", "onto", "about", "this", "that", "these", "those", "it", "its", "is", "are", "was", "were",
        "be", "been", "being", "do", "does", "did", "done", "have", "has", "had", "can", "could", "should", "would",
        "will", "shall", "may", "might", "must", "not", "no", "yes", "you", "your", "we", "our", "us", "me", "my",
        "they", "them", "their", "he", "she", "what", "which", "who", "whom", "whose", "when", "where", "why", "how",
        "all", "any", "both", "each", "few", "more", "most", "other", "some", "such", "only", "own", "same", "so",
        "than", "too", "very", "just", "also", "here", "there", "now", "one", "way", "thing", "things", "etc", "via",
        "use", "used", "using", "uses", "user", "users", "help", "please", "make", "makes", "made", "want", "need",
        "needs", "get", "gets", "got", "let", "lets", "like", "task", "tasks", "work", "working", "file", "files",
        "code", "new", "add", "adds", "added", "run", "runs", "fix", "fixes", "whenever", "including", "include",
        "includes", "provide", "provides", "support", "supports", "based", "across", "within", "without", "over",
        "under", "after", "before", "while", "during", "should", "explain", "show", "see", "look", "check", "ok",
        "okay", "hello", "hi", "thanks", "thank", "continue", "again", "still", "really", "maybe", "something"
    ]

    /// Thai words → the English terms skill descriptions use (descriptions are almost always English).
    static let thaiLexicon: [String: [String]] = [
        "ทดสอบ": ["test"], "เทส": ["test"], "เทสต์": ["test"],
        "รายงาน": ["report"], "เอกสาร": ["document"], "พีดีเอฟ": ["pdf"],
        "สไลด์": ["slide", "presentation"], "นำเสนอ": ["presentation"], "พรีเซนต์": ["presentation"],
        "ตาราง": ["table", "spreadsheet"], "สเปรดชีต": ["spreadsheet"], "เอ็กเซล": ["excel", "spreadsheet"],
        "ออกแบบ": ["design"], "ดีไซน์": ["design"], "เว็บ": ["web"], "เว็บไซต์": ["website", "web"],
        "แอป": ["app"], "แอปพลิเคชัน": ["application", "app"], "มือถือ": ["mobile"],
        "ฐานข้อมูล": ["database"], "ข้อมูล": ["data"], "วิเคราะห์": ["analysis", "analyze"],
        "กราฟ": ["chart", "graph"], "แผนภูมิ": ["chart"],
        "ความปลอดภัย": ["security"], "ช่องโหว่": ["vulnerability", "security"], "รหัสผ่าน": ["password"],
        "บั๊ก": ["bug"], "บัก": ["bug"], "ดีบัก": ["debug"], "ดีบั๊ก": ["debug"], "ค้าง": ["hang", "freeze"],
        "ภาษาไทย": ["thai"], "ไทย": ["thai"], "ฟอนต์": ["font", "typography"], "ตัวอักษร": ["typography", "font"],
        "แปล": ["translate", "localization"], "ธีม": ["theme"], "โทนสี": ["color", "palette"], "ชุดสี": ["palette", "color"],
        "รูป": ["image"], "รูปภาพ": ["image"], "ภาพ": ["image"], "วิดีโอ": ["video"], "เสียง": ["audio"],
        "อีเมล": ["email"], "สัญญา": ["contract"], "กฎหมาย": ["legal"], "การเงิน": ["finance"],
        "งบประมาณ": ["budget"], "ยอดขาย": ["sales"], "การขาย": ["sales"], "การตลาด": ["marketing"],
        "บทความ": ["article", "writing"], "สคริปต์": ["script"], "ติดตั้ง": ["install"],
        "แอนดรอยด์": ["android"], "ไอโอเอส": ["ios"], "ประสิทธิภาพ": ["performance"], "หน่วยความจำ": ["memory"],
        "โปรตีน": ["protein"], "ยีน": ["gene"], "โมเลกุล": ["molecule"], "เคมี": ["chemistry"],
        "หน้าจอ": ["screen"], "ภาพหน้าจอ": ["screenshot"], "ปุ่ม": ["button"], "ฟอร์ม": ["form"],
        "ข้อความ": ["text"], "เซิร์ฟเวอร์": ["server"], "ดีพลอย": ["deploy"], "รีวิว": ["review"],
        "แผนที่": ["map"], "อัตโนมัติ": ["automation"], "ทักษะ": ["skill"], "สกิล": ["skill"]
    ]
    private static let thaiKeysLongestFirst: [String] = thaiLexicon.keys.filter { $0.count >= 3 }.sorted { $0.count > $1.count }

    /// Intent-bearing terms of `text`: lowercased whole words (stemmed, stopwords removed) plus Thai words mapped
    /// to English through `thaiLexicon` (Thai has no spaces, so it is segmented with NLTokenizer first).
    static func terms(_ text: String) -> [String] {
        var out: [String] = []
        var latin = String.UnicodeScalarView()
        var thai = String.UnicodeScalarView()

        func flushLatin() {
            guard !latin.isEmpty else { return }
            let word = String(latin)
            latin.removeAll()
            guard word.count >= 2, !stopwords.contains(word) else { return }
            let stemmed = stem(word)
            guard !stopwords.contains(stemmed) else { return }
            out.append(stemmed)
        }
        func flushThai() {
            guard !thai.isEmpty else { return }
            out.append(contentsOf: thaiTerms(String(thai)))
            thai.removeAll()
        }

        for scalar in text.lowercased().unicodeScalars {
            if (0x0E00...0x0E7F).contains(scalar.value) {
                flushLatin()
                thai.append(scalar)
            } else if CharacterSet.alphanumerics.contains(scalar) {
                flushThai()
                latin.append(scalar)
            } else {
                flushLatin()
                flushThai()
            }
        }
        flushLatin()
        flushThai()
        return out
    }

    private static func thaiTerms(_ run: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.thai)
        tokenizer.string = run
        var words: [String] = []
        tokenizer.enumerateTokens(in: run.startIndex..<run.endIndex) { range, _ in
            words.append(String(run[range]))
            return true
        }
        var out: [String] = []
        for word in words {
            if let mapped = thaiLexicon[word] {
                out.append(contentsOf: mapped.map(stem))
                continue
            }
            // A compound the segmenter kept whole (e.g. a phrase with no break): use known words inside it.
            for key in thaiKeysLongestFirst where word.contains(key) {
                out.append(contentsOf: (thaiLexicon[key] ?? []).map(stem))
            }
        }
        return out
    }
}

// MARK: - Search (skill_engine match)

struct SkillSearchIndex {
    struct Hit: Equatable {
        let id: String
        let score: Double
        let matchedTerms: [String]
    }

    /// What the router knows about the project, beyond the query text.
    struct Context: Equatable {
        var openFileExtensions: Set<String> = []
        /// Names of `markerFiles` present at the workspace root.
        var workspaceMarkers: Set<String> = []
    }

    static let markerFiles = ["package.json", "pubspec.yaml", "firebase.json", ".firebaserc", "build.gradle", "build.gradle.kts"]

    /// Platform-specific skill families (first id segment): searchable only when that platform is in play —
    /// named in the query, or detected from the workspace / open files. Otherwise e.g. 15 Dart skills compete in
    /// a TypeScript project ("add a unit test" → `dart-add-unit-test`).
    static let platformFamilies: [String: (unlock: [String], markers: [String])] = [
        "dart": (["dart", "flutter", "pubspec"], ["pubspec.yaml", "dart"]),
        "flutter": (["flutter", "dart", "pubspec"], ["pubspec.yaml", "dart"]),
        "flutterflow": (["flutterflow"], []),
        "firebase": (["firebase", "firestore"], ["firebase.json", ".firebaserc"]),
        "bigquery": (["bigquery"], []),
        "gcp": (["gcp", "gke", "dataproc", "vertex", "bigquery", "gcs", "dataflow"], []),
        "figma": (["figma"], ["fig"]),
        "canva": (["canva"], []),
        "wix": (["wix"], []),
        "android": (["android", "adb", "apk", "gradle", "emulator"], ["build.gradle", "build.gradle.kts", "kt"]),
        "chrome": (["chrome", "devtools", "lighthouse", "lcp"], []),
        "gemini": (["gemini"], []),
        "alphagenome": (["alphagenome", "genome", "genomic"], []),
        "cheminformatics": (["chemistry", "chemical", "molecule", "molecular", "smiles", "rdkit", "cheminformatics"], ["sdf", "mol"])
    ]

    /// A skill is returned only with enough evidence: the summed rarity (IDF) of the matched words must reach this
    /// share of the rarest possible word's IDF. Relative, so it behaves the same with 12 skills or 300; a lone
    /// common word ("server", "test", "query") is not enough, one rare word ("pdf", "playwright") or two are.
    static let evidenceShare = 0.6
    static let relativeCutoff = 0.4

    private let records: [SkillRouteRecord]
    private let termFrequencies: [[String: Int]]
    private let lengths: [Int]
    private let documentFrequency: [String: Int]
    private let averageLength: Double

    init(records: [SkillRouteRecord]) {
        let enabled = records.filter { $0.isEnabled }
        var frequencies: [[String: Int]] = []
        var lengths: [Int] = []
        var df: [String: Int] = [:]
        for record in enabled {
            var tf: [String: Int] = [:]
            let idText = record.id.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            for term in SkillText.terms(idText) { tf[term, default: 0] += 2 } // the id is the most specific signal
            if record.name.lowercased() != record.id.lowercased() {
                for term in SkillText.terms(record.name) { tf[term, default: 0] += 1 }
            }
            for term in SkillText.terms(record.description) { tf[term, default: 0] += 1 }
            frequencies.append(tf)
            lengths.append(tf.values.reduce(0, +))
            for term in tf.keys { df[term, default: 0] += 1 }
        }
        self.records = enabled
        self.termFrequencies = frequencies
        self.lengths = lengths
        self.documentFrequency = df
        self.averageLength = lengths.isEmpty ? 1 : max(1, Double(lengths.reduce(0, +)) / Double(lengths.count))
    }

    func search(_ query: String, context: Context = Context(), limit: Int = 8) -> [Hit] {
        guard !records.isEmpty else { return [] }
        let queryTerms = Set(SkillText.terms(query))
        let lowerQuery = query.lowercased()
        let count = Double(records.count)
        let rarestIdf = log(1 + (count - 0.5) / 1.5)
        var hits: [Hit] = []

        for (index, record) in records.enumerated() {
            guard Self.isUnlocked(record, queryTerms: queryTerms, context: context),
                  !Self.isExcluded(record, lowerQuery: lowerQuery) else { continue }
            let tf = termFrequencies[index]
            var score = 0.0
            var evidence = 0.0
            var matched: [String] = []
            for term in queryTerms {
                guard let frequency = tf[term], let df = documentFrequency[term] else { continue }
                let idf = log(1 + (count - Double(df) + 0.5) / (Double(df) + 0.5))
                let f = Double(frequency)
                let norm = 1.2 * (0.25 + 0.75 * Double(lengths[index]) / averageLength)
                score += idf * f * 2.2 / (f + norm)
                evidence += idf
                matched.append(term)
            }
            let boost = Self.contextBoost(record, lowerQuery: lowerQuery, queryTerms: queryTerms, context: context)
            score += boost
            guard evidence + boost >= rarestIdf * Self.evidenceShare else { continue }
            hits.append(Hit(id: record.id, score: (score * 100).rounded() / 100, matchedTerms: matched.sorted()))
        }

        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
        if let top = hits.first?.score {
            hits = hits.filter { $0.score >= top * Self.relativeCutoff }
        }
        return Array(hits.prefix(limit))
    }

    static func isUnlocked(_ record: SkillRouteRecord, queryTerms: Set<String>, context: Context) -> Bool {
        guard let rule = platformFamilies[record.family] else { return true }
        if !queryTerms.isDisjoint(with: rule.unlock.map(SkillText.stem)) { return true }
        let present = context.workspaceMarkers.union(context.openFileExtensions)
        return !present.isDisjoint(with: rule.markers)
    }

    /// `mcp-builder` is for writing a new MCP server, never for connecting to or using an existing one (Canva, GitHub…).
    static func isExcluded(_ record: SkillRouteRecord, lowerQuery: String) -> Bool {
        guard record.id.lowercased() == "mcp-builder" else { return false }
        let connecting = ["เชื่อม", "ต่อ mcp", "connect", "install", "login", "enable", "canva", "figma", "github", "gmail", "notion", "supabase"]
            .contains { lowerQuery.contains($0) }
        let authoring = ["build", "create", "write", "develop", "implement", "fastmcp", "mcp sdk", "สร้าง", "เขียน", "พัฒนา"]
            .contains { lowerQuery.contains($0) }
        return connecting && !authoring
    }

    /// Precise workspace/domain signals carried over from the previous router.
    static func contextBoost(_ record: SkillRouteRecord, lowerQuery q: String, queryTerms: Set<String>, context: Context) -> Double {
        let id = record.id.lowercased()
        let ext = context.openFileExtensions
        var boost = 0.0
        if id.contains("ardium") && (ext.contains("ar") || q.contains("ardium")) { boost += 8 }
        if record.isScience && (!ext.isDisjoint(with: ["pdb", "cif", "mmcif"]) || ["protein", "alphafold", "uniprot"].contains(where: { q.contains($0) })) {
            boost += 6
        }
        if id == "runpod-orchestrator" && (q.contains("runpod") || queryTerms.contains("gpu")) { boost += 8 }
        if id == "dotmini-omni-ai" && ["omni", "o1x", "tpat"].contains(where: { q.contains($0) }) { boost += 8 }
        if ["device-automation", "android-cli", "mobile-release-automation", "xcode-project-setup"].contains(id),
           !queryTerms.isDisjoint(with: ["simulator", "emulator", "adb", "android", "ios"].map(SkillText.stem)) {
            boost += 6
        }
        if ["chrome-devtools", "debug-optimize-lcp", "a11y-debugging", "memory-leak-debugging"].contains(id),
           context.workspaceMarkers.contains("package.json"),
           ["lcp", "devtools", "a11y", "memory leak"].contains(where: { q.contains($0) }) {
            boost += 6
        }
        return boost
    }
}

// MARK: - Catalog (tier 1, always in the system prompt)

enum SkillCatalog {
    struct Listing: Equatable {
        let listed: [SkillRouteRecord]
        let hidden: [SkillRouteRecord]
    }

    /// ~2k tokens. Listing all 236 skills found on a typical machine would cost ~10k tokens on every request.
    static let defaultBudgetChars = 8_000
    static let descriptionLimit = 200

    /// Stable order (tier, then id) independent of the message, so the prompt prefix stays cacheable and a
    /// follow-up like "continue" does not swap the list. Skills that do not fit stay searchable via `match`.
    static func build(_ records: [SkillRouteRecord], excluding excludedIds: Set<String> = [], budgetChars: Int = defaultBudgetChars) -> Listing {
        let candidates = records
            .filter { $0.isEnabled && !excludedIds.contains($0.id) }
            .sorted { ($0.tier, $0.id) < ($1.tier, $1.id) }
        var listed: [SkillRouteRecord] = []
        var hidden: [SkillRouteRecord] = []
        var used = 0
        var overflowed = false
        for record in candidates {
            let cost = line(for: record).count + 1
            if !overflowed && used + cost <= budgetChars {
                listed.append(record)
                used += cost
            } else {
                overflowed = true // keep tier priority: nothing from a later tier jumps ahead of a hidden one
                hidden.append(record)
            }
        }
        return Listing(listed: listed, hidden: hidden)
    }

    static func shortDescription(_ text: String, limit: Int = descriptionLimit) -> String {
        let flat = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard flat.count > limit else { return flat }
        let cut = flat.prefix(limit)
        if let space = cut.lastIndex(of: " ") { return String(cut[..<space]) + "…" }
        return String(cut) + "…"
    }

    static func line(for record: SkillRouteRecord) -> String {
        "- \(record.id): \(shortDescription(record.description))"
    }

    static func hiddenSummary(_ hidden: [SkillRouteRecord], maxFamilies: Int = 10) -> String {
        var counts: [String: Int] = [:]
        for record in hidden { counts[record.family, default: 0] += 1 }
        let groups = counts.filter { $0.value >= 2 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(maxFamilies)
        return groups.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
    }

    static func render(_ listing: Listing) -> String {
        guard !listing.listed.isEmpty || !listing.hidden.isEmpty else { return "" }
        var text = "\n\n## AGENT SKILLS\n"
        text += "Skills hold instructions for specific kinds of tasks. When the user's task clearly matches a skill's description, load it with `skill_engine(action: \"read\", query: \"<skill id>\")` before starting and follow it. Most tasks need no skill: never load one just because it is listed.\n"
        if !listing.listed.isEmpty {
            text += "<available_skills>\n" + listing.listed.map(line(for:)).joined(separator: "\n") + "\n</available_skills>\n"
        }
        if !listing.hidden.isEmpty {
            let families = hiddenSummary(listing.hidden)
            text += "\(listing.hidden.count) more installed skills are not listed\(families.isEmpty ? "" : " (\(families))"). If the task involves one of those tools or platforms, search them with `skill_engine(action: \"match\", query: \"<what the task needs>\")`.\n"
        }
        return text
    }
}

// MARK: - Explicit invocation and lookup

enum SkillInvocation {
    /// Skills the user asked for by name: `/skill-id …` at the start of the message, or `$skill-id` anywhere.
    static func explicitIds(in message: String, enabledIds: [String], limit: Int = 3) -> [String] {
        let byLowercased = Dictionary(enabledIds.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var found: [String] = []
        func consider(_ raw: Substring) {
            let key = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}\"'`")).lowercased()
            if let id = byLowercased[key], !found.contains(id) { found.append(id) }
        }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("/") {
            consider(text.dropFirst().prefix { !$0.isWhitespace })
        }
        for word in text.split(whereSeparator: { $0.isWhitespace }) where word.hasPrefix("$") && word.count > 1 {
            consider(word.dropFirst())
        }
        return Array(found.prefix(limit))
    }
}

enum SkillLookup {
    enum Result: Equatable {
        case found(String)
        case emptyQuery
        case notFound
        case ambiguous([String])
        case disabled(String)
    }

    static func normalize(_ query: String) -> String {
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "`\"'"))
        while text.hasPrefix("$") || text.hasPrefix("/") { text.removeFirst() }
        return text.lowercased()
    }

    /// Exact id → exact name → unique id/name prefix. Never "first skill whose name contains the query"
    /// (that opened the first skill in the list for an empty query) and never a disabled skill.
    static func resolve(_ query: String, records: [SkillRouteRecord]) -> Result {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return .emptyQuery }
        var candidates = [normalized]
        if let colon = normalized.lastIndex(of: ":") {
            let tail = String(normalized[normalized.index(after: colon)...])
            if !tail.isEmpty { candidates.append(tail) } // e.g. "anthropic-skills:pdf"
        }
        for candidate in candidates {
            if let exact = records.first(where: { $0.id.lowercased() == candidate }) {
                return exact.isEnabled ? .found(exact.id) : .disabled(exact.id)
            }
        }
        for candidate in candidates {
            let named = records.filter { $0.name.lowercased() == candidate }
            guard !named.isEmpty else { continue }
            let enabled = named.filter { $0.isEnabled }
            if enabled.count == 1 { return .found(enabled[0].id) }
            if enabled.isEmpty { return .disabled(named[0].id) }
            return .ambiguous(enabled.map(\.id).sorted())
        }
        let enabled = records.filter { $0.isEnabled }
        for candidate in candidates where candidate.count >= 3 {
            let prefixed = enabled.filter { $0.id.lowercased().hasPrefix(candidate) || $0.name.lowercased().hasPrefix(candidate) }
            if prefixed.count == 1 { return .found(prefixed[0].id) }
            if prefixed.count > 1 { return .ambiguous(Array(prefixed.map(\.id).sorted().prefix(8))) }
        }
        return .notFound
    }
}
