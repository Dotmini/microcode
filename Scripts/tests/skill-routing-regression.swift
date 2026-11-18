import Foundation

// Phase 3c skill-routing regression. Compiled together with MicroCode/Services/AgentCore/SkillRouter.swift.
// Fixture descriptions are paraphrased stand-ins for the skills that were routed wrongly on a real machine.
// `--live` additionally prints routing against the skills installed on this Mac (report only, no assertions).

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}

func rec(_ id: String, _ description: String, _ tier: SkillCatalogTier = .user, enabled: Bool = true, science: Bool = false, name: String? = nil) -> SkillRouteRecord {
    SkillRouteRecord(id: id, name: name ?? id, description: description, isEnabled: enabled, tier: tier, isScience: science)
}

let fixtures: [SkillRouteRecord] = [
    rec("frontend-design", "Create distinctive, production-grade frontend interfaces: web pages, landing pages, dashboards and UI components with high design quality.", .builtin),
    rec("microcode-thai-ui-typography", "Thai text in UI, reports and PDF documents: Thai fonts, line breaking, typography and localization.", .builtin),
    rec("microcode-security-baseline", "Security baseline for changes touching auth, tokens, secrets, passwords, OAuth, encryption, keychain and injection risks.", .builtin),
    rec("microcode-swift-macos-ui", "Native macOS interfaces with SwiftUI and AppKit: windows, sidebars, toolbars, layout and platform conventions.", .builtin),
    rec("theme-factory", "Apply a theme (colors and fonts) to slides, documents, reports and web pages.", .builtin),
    rec("mcp-builder", "Guide for building MCP servers that let LLMs use external services through well-designed tools, in Python (FastMCP) or TypeScript (MCP SDK).", .builtin),
    rec("webapp-testing", "Test local web applications with Playwright: verify frontend behavior, capture screenshots, read browser logs.", .builtin),
    rec("microcode-skill-authoring", "Write and improve SKILL.md skills: structure, description triggers, scripts and references.", .builtin),
    rec("microcode-harness-core", "MicroCode core operating protocol.", .builtin),
    rec("microcode-anti-slop", "Avoid generic AI writing and design in copywriting, landing page text and articles.", .builtin),
    rec("uv", "Manage Python projects, dependencies and virtual environments with the uv package manager."),
    rec("pdf", "Read, create, merge, split and fill PDF documents; extract text and tables from PDF files."),
    rec("review-agent", "Review a change or pull request for bugs and regressions before it is merged."),
    rec("systematic-debugging", "Use when encountering any bug, crash, hang, test failure or unexpected behavior, before proposing fixes."),
    rec("presentations", "Create slide presentations and decks.", .ecosystem),
    rec("spreadsheets", "Create and edit spreadsheets with formulas and charts.", .ecosystem),
    rec("android-cli", "Build, install and debug Android apps with adb, gradle and the emulator.", .ecosystem),
    rec("alphafold-database-fetch-and-analyze", "Fetch AlphaFold protein structure predictions and analyze their confidence.", .ecosystem, science: true),
    rec("dart-add-unit-test", "Add unit tests to a Dart package using package:test, with test structure and mocks.", .pluginCache),
    rec("dart-generate-test-mocks", "Generate mock classes for Dart unit tests.", .pluginCache),
    rec("flutter-add-widget-test", "Add widget tests to a Flutter app.", .pluginCache),
    rec("flutter-fix-layout-issues", "Fix Flutter layout errors such as overflow and unbounded constraints.", .pluginCache),
    rec("firebase-basics", "Set up Firebase in an app: project config, Firestore, authentication and hosting.", .pluginCache),
    rec("bigquery-optimization", "Optimize BigQuery query cost and performance with partitioning, clustering and slots.", .pluginCache),
    rec("bigquery-sql", "Write BigQuery SQL queries.", .pluginCache),
    rec("figma-generate-design", "Create or update a Figma design from a screen, page or description.", .pluginCache),
    rec("figma-design-to-code", "Turn a Figma design into production code.", .pluginCache),
    rec("canva-resize-for-social-media", "Resize a Canva design for social media formats.", .pluginCache),
    rec("chrome-devtools", "Debug web pages with Chrome DevTools: network, console, performance and memory.", .pluginCache),
    rec("gcp-spark", "Run Apache Spark jobs on Google Cloud Dataproc server clusters.", .pluginCache),
    rec("wix-app", "Build a Wix app with the Wix editor and APIs.", .pluginCache),
    rec("old-disabled-skill", "A disabled skill about PDF reports.", enabled: false)
]
let coreIds: Set<String> = ["microcode-harness-core"]
let index = SkillSearchIndex(records: fixtures.filter { !coreIds.contains($0.id) })
func ids(_ hits: [SkillSearchIndex.Hit]) -> [String] { hits.map(\.id) }
func families(_ hits: [SkillSearchIndex.Hit]) -> Set<String> { Set(hits.map { SkillText.family(of: $0.id) }) }
let platformFamilies = Set(SkillSearchIndex.platformFamilies.keys)

// MARK: tokenizer
check(Set(SkillText.terms("Testing tests TESTED test")) == ["test"], "stemmer collapses test forms: \(SkillText.terms("Testing tests TESTED test"))")
check(SkillText.terms("debugging") == SkillText.terms("debug"), "debugging ~ debug")
check(SkillText.terms("create") == SkillText.terms("created"), "create ~ created")
check(!SkillText.terms("uvicorn").contains("uv"), "uvicorn is not uv")
check(SkillText.terms("this is the code that you want").isEmpty, "stopwords only → no terms")
let thai = Set(SkillText.terms("ทำรายงาน PDF ภาษาไทย"))
check(thai.isSuperset(of: ["report", "pdf", "thai"]), "Thai words map to English terms: \(thai)")

// MARK: search — the cases that were routed wrongly
let ts = SkillSearchIndex.Context(openFileExtensions: ["ts"], workspaceMarkers: ["package.json"])
let dartCtx = SkillSearchIndex.Context(openFileExtensions: ["dart"], workspaceMarkers: ["pubspec.yaml"])
let unitTestTS = index.search("add a unit test for the json parser", context: ts)
check(families(unitTestTS).isDisjoint(with: ["dart", "flutter"]), "TS project must not get Dart/Flutter skills: \(ids(unitTestTS))")
let unitTestDart = index.search("add a unit test for the json parser", context: dartCtx)
check(unitTestDart.first?.id == "dart-add-unit-test", "Dart project gets dart-add-unit-test first: \(ids(unitTestDart))")
let uvicorn = index.search("run the server with uvicorn", context: .init(openFileExtensions: ["py"]))
check(!ids(uvicorn).contains("uv"), "uvicorn must not pull the uv skill: \(ids(uvicorn))")
check(index.search("use uv to install dependencies").first?.id == "uv", "explicit uv request finds uv")
for prompt in ["ต่อ", "hello", "continue", "explain what this function does", "ok thanks"] {
    let hits = index.search(prompt, context: .init(openFileExtensions: ["py"]))
    check(hits.isEmpty, "'\(prompt)' should match no skill: \(ids(hits))")
}
let hang = index.search("ช่วยดู bug ว่าทำไมแอปค้าง")
check(hang.first?.id == "systematic-debugging", "Thai bug report (bug + hang) → debugging skill first: \(ids(hang))")
check(families(hang).isDisjoint(with: platformFamilies), "no platform skills for a generic bug: \(ids(hang))")
let thaiPDF = index.search("ทำรายงาน PDF ภาษาไทยสรุปยอดขาย")
check(Set(ids(thaiPDF).prefix(2)) == ["pdf", "microcode-thai-ui-typography"], "Thai PDF report → pdf + Thai typography on top: \(ids(thaiPDF))")
check(!ids(thaiPDF).contains("old-disabled-skill"), "disabled skills are never returned")
check(index.search("optimize my bigquery query cost").first?.id == "bigquery-optimization", "BigQuery cost → bigquery-optimization")
check(index.search("build an mcp server in python").first?.id == "mcp-builder", "authoring an MCP server → mcp-builder")
check(!ids(index.search("connect the canva mcp")).contains("mcp-builder"), "connecting an existing MCP never suggests mcp-builder")
check(index.search("create a figma design from this screen").first?.id == "figma-generate-design", "Figma request → figma-generate-design")
let swiftBuild = index.search("fix the build error in AgentService.swift", context: .init(openFileExtensions: ["swift"]))
check(families(swiftBuild).isDisjoint(with: platformFamilies), "Swift build error must not pull platform skills: \(ids(swiftBuild))")
check(index.search("ออกแบบหน้าเว็บ landing page ให้สวย").first?.id == "frontend-design", "Thai landing page → frontend-design")
check(ids(index.search("review how we store the oauth token")).contains("microcode-security-baseline"), "OAuth token storage → security baseline")
check(ids(index.search("debug the android app on the emulator")).contains("android-cli"), "Android emulator → android-cli")
check(index.search("ทดสอบเว็บด้วย playwright").first?.id == "webapp-testing", "Thai Playwright request → webapp-testing")
check(ids(index.search("add a widget test", context: ts)).isEmpty, "Flutter widget test is gated outside Flutter projects")
check(!ids(index.search("explain this protein structure")).isEmpty, "science boost still works")

// MARK: catalog
let listing = SkillCatalog.build(fixtures, excluding: coreIds)
check(!listing.listed.contains { $0.id == "microcode-harness-core" }, "core protocol is not in the catalog")
check(!(listing.listed + listing.hidden).contains { !$0.isEnabled }, "disabled skills are hidden entirely")
check(listing.listed.first?.tier == .builtin, "built-in skills come first")
let tiny = SkillCatalog.build(fixtures, excluding: coreIds, budgetChars: 1_200)
check(!tiny.hidden.isEmpty, "a small budget hides the tail")
let order = (tiny.listed + tiny.hidden).map { "\($0.tier.rawValue)|\($0.id)" }
check(order == order.sorted(), "listed skills always precede hidden ones in tier/id order")
let rendered = SkillCatalog.render(tiny)
check(rendered.contains("<available_skills>") && rendered.contains("more installed skills are not listed"), "render lists + points to match for the rest")
check(rendered.contains("dart ×2") || rendered.contains("figma ×2") || rendered.contains("bigquery ×2"), "hidden summary names platform families: \(rendered)")
check(!rendered.contains("MUST read"), "catalog no longer orders the model to read skills")
check(rendered.count <= 1_200 + 900, "rendered catalog stays near the budget (\(rendered.count) chars)")
check(SkillCatalog.render(SkillCatalog.build([], excluding: [])).isEmpty, "no skills → no catalog block")
check(SkillCatalog.build(fixtures, excluding: coreIds) == SkillCatalog.build(fixtures.reversed(), excluding: coreIds), "catalog is independent of input order")
let long = SkillCatalog.shortDescription(String(repeating: "word ", count: 80))
check(long.count <= SkillCatalog.descriptionLimit + 1 && long.hasSuffix("…"), "long descriptions are cut on a word boundary")

// MARK: explicit invocation
let enabledIds = fixtures.filter(\.isEnabled).map(\.id)
check(SkillInvocation.explicitIds(in: "/pdf make a report", enabledIds: enabledIds) == ["pdf"], "/pdf invokes pdf")
check(SkillInvocation.explicitIds(in: "please use $frontend-design.", enabledIds: enabledIds) == ["frontend-design"], "$skill invokes it")
check(SkillInvocation.explicitIds(in: "/plan refactor the parser", enabledIds: enabledIds).isEmpty, "/plan is not a skill")
check(SkillInvocation.explicitIds(in: "echo $HOME then add a test", enabledIds: enabledIds).isEmpty, "$HOME is not a skill")
check(SkillInvocation.explicitIds(in: "$PDF and $uv", enabledIds: enabledIds) == ["pdf", "uv"], "several invocations, in order")
check(SkillInvocation.explicitIds(in: "$old-disabled-skill now", enabledIds: enabledIds).isEmpty, "disabled skills cannot be invoked")
check(SkillInvocation.explicitIds(in: "write a pdf report", enabledIds: enabledIds).isEmpty, "plain words never inject a skill")

// MARK: lookup (skill_engine read)
check(SkillLookup.resolve("", records: fixtures) == .emptyQuery, "empty query no longer opens the first skill")
check(SkillLookup.resolve("   ", records: fixtures) == .emptyQuery, "blank query")
for query in ["pdf", "PDF", "$pdf", "/pdf", "`pdf`", "anthropic-skills:pdf"] {
    check(SkillLookup.resolve(query, records: fixtures) == .found("pdf"), "'\(query)' resolves to pdf")
}
check(SkillLookup.resolve("old-disabled-skill", records: fixtures) == .disabled("old-disabled-skill"), "disabled skill is refused")
check(SkillLookup.resolve("figma", records: fixtures) == .ambiguous(["figma-design-to-code", "figma-generate-design"]), "ambiguous prefix lists candidates")
check(SkillLookup.resolve("dart-add", records: fixtures) == .found("dart-add-unit-test"), "unique prefix resolves")
check(SkillLookup.resolve("no-such-skill", records: fixtures) == .notFound, "unknown id")
check(SkillLookup.resolve("ui", records: fixtures) == .notFound, "short fragments do not match by substring")

// MARK: live report
if CommandLine.arguments.contains("--live") {
    let home = NSHomeDirectory()
    let builtinRoot = "/Applications/MicroCode.app/Contents/Resources/BuiltinSkills"
    let roots = ["\(home)/.microcode/skills", "\(home)/.agents/skills", "\(home)/.claude/skills", "\(home)/.claude/plugins",
                 "\(home)/.codex/skills", "\(home)/.codex/plugins/cache", "\(home)/.gemini/config/skills", "\(home)/.gemini/config/plugins",
                 "\(home)/.gemini/antigravity/builtin/skills", builtinRoot]
    let ignored: Set<String> = [".git", ".build", "target", "node_modules", "DerivedData", "dist", "build", "inactive-skills"]
    var paths: [String] = []
    for root in roots {
        guard let walker = FileManager.default.enumerator(atPath: root) else { continue }
        while let element = walker.nextObject() as? String {
            if ignored.contains((element as NSString).lastPathComponent) { walker.skipDescendants(); continue }
            if element.hasSuffix("SKILL.md") || element.hasSuffix("skill.md") { paths.append("\(root)/\(element)") }
        }
    }
    func frontmatter(_ text: String) -> (name: String?, description: String?) {
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, nil) }
        var name: String?; var description: String?; var block: [String]? = nil
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if var collected = block {
                if line.hasPrefix(" ") || line.hasPrefix("\t") || trimmed.isEmpty { collected.append(trimmed); block = collected; continue }
                description = collected.joined(separator: " "); block = nil
            }
            if trimmed.hasPrefix("name:") { name = String(trimmed.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
            if trimmed.hasPrefix("description:") {
                let value = String(trimmed.dropFirst(12)).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if ["|", ">", ">-", "|-", ""].contains(value) { block = [] } else { description = value }
            }
        }
        if let collected = block { description = collected.joined(separator: " ") }
        return (name, description)
    }
    var seen: Set<String> = []
    var live: [SkillRouteRecord] = []
    for path in Set(paths).sorted(by: { ($0.hasPrefix(builtinRoot) ? 1 : 0, $0) < ($1.hasPrefix(builtinRoot) ? 1 : 0, $1) }) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
        let meta = frontmatter(text)
        let folder = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let slug = meta.name?.trimmingCharacters(in: .whitespaces) ?? ""
        let id = (!slug.isEmpty && !slug.contains(" ") && slug.count <= 64) ? slug.lowercased() : folder
        guard !seen.contains(id) else { continue }
        seen.insert(id)
        let isBuiltin = path.hasPrefix(builtinRoot)
        let science = ["alpha", "chem", "bio", "pdb", "gene", "variant", "fold", "mol", "med"].contains { id.contains($0) } || path.lowercased().contains("science")
        live.append(SkillRouteRecord(id: id, name: slug.isEmpty ? id : slug, description: meta.description ?? "", isEnabled: true,
                                     tier: SkillCatalogTier.classify(path: path, isBuiltin: isBuiltin, isProjectSkill: false, home: home), isScience: science))
    }
    let liveIndex = SkillSearchIndex(records: live.filter { !coreIds.contains($0.id) })
    let liveListing = SkillCatalog.build(live, excluding: coreIds)
    let liveRendered = SkillCatalog.render(liveListing)
    print("LIVE: \(live.count) skills; catalog lists \(liveListing.listed.count), hides \(liveListing.hidden.count); \(liveRendered.count) chars ≈ \(liveRendered.count / 4) tokens")
    print("LIVE hidden families: \(SkillCatalog.hiddenSummary(liveListing.hidden))")
    let probes: [(String, SkillSearchIndex.Context)] = [
        ("ต่อ", .init()), ("ช่วยดู bug ว่าทำไมแอปค้าง", .init()), ("ตอนพิมพ์ใน Editor มันไม่ smooth ช่วยแก้หน่อย", .init(openFileExtensions: ["swift"])),
        ("fix the build error in AgentService.swift", .init(openFileExtensions: ["swift"])),
        ("Research Review สิ่งที่ต้องปรับปรุง AI Agent, Skill, ACP MCP และ Harness", .init()),
        ("ทำรายงาน PDF ภาษาไทยสรุปยอดขาย", .init()), ("add a unit test for the json parser", .init(openFileExtensions: ["ts"], workspaceMarkers: ["package.json"])),
        ("commit แล้ว push ให้หน่อย", .init()), ("explain what this function does", .init(openFileExtensions: ["py"])),
        ("run the server with uvicorn", .init(openFileExtensions: ["py"])), ("optimize this query, it's too slow", .init(openFileExtensions: ["py"])),
        ("hello", .init()), ("optimize my bigquery query cost", .init()), ("build an mcp server in python", .init()),
        ("create a figma design from this screen", .init()), ("ออกแบบหน้าเว็บ landing page ให้สวย", .init())
    ]
    for (prompt, context) in probes {
        let hits = liveIndex.search(prompt, context: context, limit: 5)
        let shown = hits.isEmpty ? "— no skill" : hits.map { "\($0.id) \($0.score) [\($0.matchedTerms.joined(separator: ","))]" }.joined(separator: " | ")
        print("LIVE \(String(prompt.prefix(48)).padding(toLength: 50, withPad: " ", startingAt: 0)) → \(shown)")
    }
}

if failures == 0 {
    print("SKILL ROUTING REGRESSION: PASS")
} else {
    print("SKILL ROUTING REGRESSION: \(failures) FAILURE(S)")
    exit(1)
}
