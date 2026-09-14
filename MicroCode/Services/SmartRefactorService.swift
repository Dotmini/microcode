// Copyright © 2025 Dotmini Software. All rights reserved.

import Foundation
import Combine
import SwiftUI

// MARK: - Refactoring Category

public enum RefactoringCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case extract = "Extract"
    case inline = "Inline"
    case restructure = "Restructure"
    case optimize = "Optimize"
    case modernize = "Modernize"
    case safety = "Safety"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .extract: return "arrow.up.right.and.arrow.down.left.rectangle"
        case .inline: return "arrow.down.forward.and.arrow.up.backward"
        case .restructure: return "arrow.triangle.branch"
        case .optimize: return "speedometer"
        case .modernize: return "sparkles"
        case .safety: return "shield.lefthalf.filled"
        }
    }
    
    public var description: String {
        switch self {
        case .extract:
            return "Decompose complex code into reusable functions, variables, protocols, or UI components."
        case .inline:
            return "Fold single-use methods, variables, or types directly back into their usage sites."
        case .restructure:
            return "Reorganize files, declarations, member ordering, and imports for structural clarity."
        case .optimize:
            return "Prune dead code, simplify branching logic, optimize imports, and streamline loops."
        case .modernize:
            return "Upgrade code to modern language features including async/await, pattern matching, and optional chaining."
        case .safety:
            return "Strengthen defensive resilience with error handling, null guards, explicit types, and documentation."
        }
    }
}

// MARK: - Refactoring Risk Level

public enum RefactoringRiskLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .low: return "checkmark.circle.fill"
        case .medium: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.octagon.fill"
        }
    }
    
    public var description: String {
        switch self {
        case .low:
            return "Safe transformation with minimal impact on surrounding code."
        case .medium:
            return "May alter function signatures or require updating call sites."
        case .high:
            return "Structural architectural change with potential API breaking effects."
        }
    }
}

// MARK: - Refactoring Operation

public struct RefactoringOperation: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let category: RefactoringCategory
    public let icon: String
    public let applicableLanguages: [String]
    
    public init(
        id: String,
        name: String,
        description: String,
        category: RefactoringCategory,
        icon: String,
        applicableLanguages: [String] = ["*"]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.icon = icon
        self.applicableLanguages = applicableLanguages
    }
    
    public func isApplicable(to language: String, hasSelection: Bool) -> Bool {
        let lang = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let languageMatches = applicableLanguages.contains("*") ||
            applicableLanguages.map { $0.lowercased() }.contains(lang)
        
        guard languageMatches else { return false }
        
        // Contextual checks
        switch id {
        case "extractMethod", "extractVariable", "extractComponent", "inlineVariable", "inlineMethod":
            // Applicable in general, especially when code is present
            return true
        default:
            return true
        }
    }
    
    // MARK: - Built-in Catalog: Extract
    
    public static let extractMethod = RefactoringOperation(
        id: "extractMethod",
        name: "Extract Method",
        description: "Extract the selected statements into a dedicated, well-named function or method.",
        category: .extract,
        icon: "arrow.up.right.and.arrow.down.left.rectangle",
        applicableLanguages: ["*"]
    )
    
    public static let extractVariable = RefactoringOperation(
        id: "extractVariable",
        name: "Extract Variable",
        description: "Extract the selected expression into a local variable or constant.",
        category: .extract,
        icon: "character.textbox",
        applicableLanguages: ["*"]
    )
    
    public static let extractInterface = RefactoringOperation(
        id: "extractInterface",
        name: "Extract Interface / Protocol",
        description: "Extract common method signatures into a protocol or interface abstraction.",
        category: .extract,
        icon: "point.3.filled.connected.trianglepath.dotted",
        applicableLanguages: ["swift", "typescript", "java", "kotlin", "csharp", "go", "rust"]
    )
    
    public static let extractComponent = RefactoringOperation(
        id: "extractComponent",
        name: "Extract Component",
        description: "Extract selected UI view, SwiftUI struct, or React component into a reusable subcomponent.",
        category: .extract,
        icon: "square.2.layers.3d",
        applicableLanguages: ["swift", "typescript", "javascript", "tsx", "jsx", "html", "vue"]
    )
    
    // MARK: - Built-in Catalog: Inline
    
    public static let inlineVariable = RefactoringOperation(
        id: "inlineVariable",
        name: "Inline Variable",
        description: "Replace references to a redundant variable with its initialization expression.",
        category: .inline,
        icon: "arrow.down.forward.and.arrow.up.backward",
        applicableLanguages: ["*"]
    )
    
    public static let inlineMethod = RefactoringOperation(
        id: "inlineMethod",
        name: "Inline Method",
        description: "Replace calls to a trivial method with the method's body content.",
        category: .inline,
        icon: "arrow.turn.down.left",
        applicableLanguages: ["*"]
    )
    
    public static let inlineType = RefactoringOperation(
        id: "inlineType",
        name: "Inline Type",
        description: "Fold a single-use helper type, struct, or typealias directly into its consuming context.",
        category: .inline,
        icon: "square.3.layers.3d.down.right",
        applicableLanguages: ["*"]
    )
    
    // MARK: - Built-in Catalog: Restructure
    
    public static let moveToFile = RefactoringOperation(
        id: "moveToFile",
        name: "Move to File",
        description: "Move a type, class, enum, or extension into its own dedicated source file.",
        category: .restructure,
        icon: "arrow.right.doc.on.clipboard",
        applicableLanguages: ["*"]
    )
    
    public static let splitFile = RefactoringOperation(
        id: "splitFile",
        name: "Split File",
        description: "Decompose a large file into multiple cohesive files grouped by domain or layer.",
        category: .restructure,
        icon: "scissors",
        applicableLanguages: ["*"]
    )
    
    public static let reorderMembers = RefactoringOperation(
        id: "reorderMembers",
        name: "Reorder Members",
        description: "Reorder file members canonically: types, properties, inits, methods, extensions.",
        category: .restructure,
        icon: "arrow.up.arrow.down",
        applicableLanguages: ["*"]
    )
    
    public static let groupImports = RefactoringOperation(
        id: "groupImports",
        name: "Group & Sort Imports",
        description: "Group imports into system, third-party, and project modules with alphabetical sorting.",
        category: .restructure,
        icon: "tray.full",
        applicableLanguages: ["*"]
    )
    
    // MARK: - Built-in Catalog: Optimize
    
    public static let removeDeadCode = RefactoringOperation(
        id: "removeDeadCode",
        name: "Remove Dead Code",
        description: "Identify and prune unused variables, functions, and unreachable branches.",
        category: .optimize,
        icon: "trash",
        applicableLanguages: ["*"]
    )
    
    public static let simplifyConditionals = RefactoringOperation(
        id: "simplifyConditionals",
        name: "Simplify Conditionals",
        description: "Flatten nested if-statements, adopt guard clauses, and simplify boolean logic.",
        category: .optimize,
        icon: "wand.and.stars",
        applicableLanguages: ["*"]
    )
    
    public static let optimizeImports = RefactoringOperation(
        id: "optimizeImports",
        name: "Optimize Imports",
        description: "Detect and remove unused imports and dependencies to minimize compile time.",
        category: .optimize,
        icon: "cube.box",
        applicableLanguages: ["*"]
    )
    
    public static let convertLoop = RefactoringOperation(
        id: "convertLoop",
        name: "Convert Loop",
        description: "Transform between imperative for/while loops and declarative functional chains.",
        category: .optimize,
        icon: "arrow.triangle.2.circlepath",
        applicableLanguages: ["*"]
    )
    
    // MARK: - Built-in Catalog: Modernize
    
    public static let useAsyncAwait = RefactoringOperation(
        id: "useAsyncAwait",
        name: "Convert to Async/Await",
        description: "Migrate legacy completion handlers and callback-based APIs to native async/await.",
        category: .modernize,
        icon: "bolt.horizontal",
        applicableLanguages: ["swift", "javascript", "typescript", "python", "rust", "csharp"]
    )
    
    public static let usePatternMatching = RefactoringOperation(
        id: "usePatternMatching",
        name: "Adopt Pattern Matching",
        description: "Convert chained if-else or type checks to idiomatic pattern matching and switch statements.",
        category: .modernize,
        icon: "switch.2",
        applicableLanguages: ["swift", "rust", "kotlin", "typescript", "python"]
    )
    
    public static let useOptionalChaining = RefactoringOperation(
        id: "useOptionalChaining",
        name: "Use Optional Chaining",
        description: "Replace cascading null/nil checks with idiomatic safe optional chaining.",
        category: .modernize,
        icon: "link",
        applicableLanguages: ["swift", "typescript", "javascript", "kotlin", "csharp"]
    )
    
    public static let useModernSyntax = RefactoringOperation(
        id: "useModernSyntax",
        name: "Upgrade to Modern Syntax",
        description: "Adopt recent language features, syntactic sugars, and modern standard library idioms.",
        category: .modernize,
        icon: "sparkles",
        applicableLanguages: ["*"]
    )
    
    // MARK: - Built-in Catalog: Safety
    
    public static let addErrorHandling = RefactoringOperation(
        id: "addErrorHandling",
        name: "Add Error Handling",
        description: "Wrap potentially failing calls in structured try/catch blocks with typed, actionable errors.",
        category: .safety,
        icon: "exclamationmark.shield",
        applicableLanguages: ["*"]
    )
    
    public static let addNullChecks = RefactoringOperation(
        id: "addNullChecks",
        name: "Add Null/Nil Checks",
        description: "Introduce defensive guard assertions, nil coalescing, and non-null guarantees.",
        category: .safety,
        icon: "checkmark.shield",
        applicableLanguages: ["*"]
    )
    
    public static let addTypeAnnotations = RefactoringOperation(
        id: "addTypeAnnotations",
        name: "Add Type Annotations",
        description: "Add explicit type annotations to ambiguous declarations, parameters, and returns.",
        category: .safety,
        icon: "textformat",
        applicableLanguages: ["swift", "typescript", "python", "javascript"]
    )
    
    public static let addDocComments = RefactoringOperation(
        id: "addDocComments",
        name: "Add Documentation Comments",
        description: "Generate structured, standardized docstrings and documentation comments.",
        category: .safety,
        icon: "text.bubble",
        applicableLanguages: ["*"]
    )
    
    /// Complete catalog of all built-in refactoring operations
    public static let allOperations: [RefactoringOperation] = [
        // Extract
        extractMethod,
        extractVariable,
        extractInterface,
        extractComponent,
        // Inline
        inlineVariable,
        inlineMethod,
        inlineType,
        // Restructure
        moveToFile,
        splitFile,
        reorderMembers,
        groupImports,
        // Optimize
        removeDeadCode,
        simplifyConditionals,
        optimizeImports,
        convertLoop,
        // Modernize
        useAsyncAwait,
        usePatternMatching,
        useOptionalChaining,
        useModernSyntax,
        // Safety
        addErrorHandling,
        addNullChecks,
        addTypeAnnotations,
        addDocComments
    ]
}

// MARK: - Refactoring Preview

public struct RefactoringPreview: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public let operation: RefactoringOperation
    public let originalCode: String
    public let refactoredCode: String
    public let affectedFiles: [String]
    public let riskLevel: RefactoringRiskLevel
    public let explanation: String?
    
    public init(
        id: UUID = UUID(),
        operation: RefactoringOperation,
        originalCode: String,
        refactoredCode: String,
        affectedFiles: [String] = [],
        riskLevel: RefactoringRiskLevel,
        explanation: String? = nil
    ) {
        self.id = id
        self.operation = operation
        self.originalCode = originalCode
        self.refactoredCode = refactoredCode
        self.affectedFiles = affectedFiles
        self.riskLevel = riskLevel
        self.explanation = explanation
    }
    
    /// Estimated line additions count
    public var additionsCount: Int {
        let oldLines = Set(originalCode.components(separatedBy: .newlines))
        let newLines = refactoredCode.components(separatedBy: .newlines)
        return newLines.filter { !oldLines.contains($0) }.count
    }
    
    /// Estimated line deletions count
    public var deletionsCount: Int {
        let oldLines = originalCode.components(separatedBy: .newlines)
        let newLines = Set(refactoredCode.components(separatedBy: .newlines))
        return oldLines.filter { !newLines.contains($0) }.count
    }
}

// MARK: - Errors

public enum SmartRefactorError: LocalizedError {
    case noCodeProvided
    case unsupportedOperation(String)
    case analysisFailed(String)
    case generationFailed(String)
    case applyFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .noCodeProvided:
            return "No code content was provided for refactoring."
        case .unsupportedOperation(let name):
            return "Operation '\(name)' is not supported for this context."
        case .analysisFailed(let reason):
            return "Refactoring analysis failed: \(reason)"
        case .generationFailed(let reason):
            return "Failed to generate refactoring preview: \(reason)"
        case .applyFailed(let reason):
            return "Failed to apply refactoring: \(reason)"
        }
    }
}

// MARK: - SmartRefactorService

@MainActor
public class SmartRefactorService: ObservableObject {
    public static let shared = SmartRefactorService()
    
    @Published public var availableRefactorings: [RefactoringOperation] = []
    @Published public var isAnalyzing: Bool = false
    @Published public var preview: RefactoringPreview? = nil
    @Published public var lastError: String? = nil
    
    private var analysisTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    
    private init() {
        self.availableRefactorings = RefactoringOperation.allOperations
    }
    
    // MARK: - Query Catalog
    
    /// Returns operations filtered by category
    public func operations(for category: RefactoringCategory) -> [RefactoringOperation] {
        availableRefactorings.filter { $0.category == category }
    }
    
    /// Resets the current preview state
    public func clearPreview() {
        preview = nil
        lastError = nil
    }
    
    /// Cancels any in-flight analysis or preview generation
    public func cancel() {
        analysisTask?.cancel()
        previewTask?.cancel()
        isAnalyzing = false
    }
    
    // MARK: - Code Analysis
    
    /// Analyzes code and selection to determine applicable refactorings
    public func analyzeCode(content: String, selection: String?, language: String) async throws {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SmartRefactorError.noCodeProvided
        }
        
        cancel()
        isAnalyzing = true
        lastError = nil
        
        defer {
            isAnalyzing = false
        }
        
        let hasSelection = selection != nil && !selection!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let normalizedLang = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // 1. Filter operations applicable by language and context
        let candidates = RefactoringOperation.allOperations.filter {
            $0.isApplicable(to: normalizedLang, hasSelection: hasSelection)
        }
        
        // 2. Perform intelligent AI ranking if available
        let catalogListing = candidates.map { "- \($0.id): \($0.name) (\($0.category.rawValue)) - \($0.description)" }.joined(separator: "\n")
        
        let systemPrompt = """
        You are a compiler and static analysis engine for \(language).
        Analyze the provided source code snippet and user selection to recommend the most relevant and high-impact semantic refactorings.
        
        AVAILABLE REFACTORING IDS:
        \(catalogListing)
        
        INSTRUCTIONS:
        1. Examine complexity, code smells, readability, error safety, and idiomatic practices.
        2. Select 3 to 8 of the MOST relevant and beneficial operation IDs from the available list.
        3. Order them from highest to lowest relevance.
        4. Return ONLY a valid JSON array of strings, e.g.: ["extractMethod", "simplifyConditionals", "addErrorHandling"].
        5. Do NOT include markdown code blocks, intro, or outro text. Output raw JSON only.
        """
        
        let contextSnippet: String
        if content.count > 4000 {
            contextSnippet = String(content.prefix(4000)) + "\n// ... [truncated for analysis]"
        } else {
            contextSnippet = content
        }
        
        var userPrompt = "Language: \(language)\nHas Selection: \(hasSelection)\n"
        if let sel = selection, hasSelection {
            let truncatedSelection = sel.count > 1500 ? String(sel.prefix(1500)) : sel
            userPrompt += "Selected code:\n```\(language)\n\(truncatedSelection)\n```\n\n"
        }
        userPrompt += "Code Context:\n```\(language)\n\(contextSnippet)\n```"
        
        let messages = [
            (role: "system", content: systemPrompt),
            (role: "user", content: userPrompt)
        ]
        
        do {
            let stream = try await AIClient.shared.streamCompletion(
                messages: messages,
                stream: false
            )
            
            var responseText = ""
            for try await chunk in stream {
                responseText += chunk
            }
            
            var jsonText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonText.hasPrefix("```json") {
                jsonText = jsonText.replacingOccurrences(of: "```json", with: "")
                jsonText = jsonText.replacingOccurrences(of: "```", with: "")
            } else if jsonText.hasPrefix("```") {
                jsonText = jsonText.replacingOccurrences(of: "```", with: "")
            }
            jsonText = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let data = jsonText.data(using: .utf8),
               let recommendedIds = try? JSONDecoder().decode([String].self, from: data),
               !recommendedIds.isEmpty {
                let idSet = Set(recommendedIds)
                var prioritized: [RefactoringOperation] = []
                for id in recommendedIds {
                    if let found = candidates.first(where: { $0.id == id }) {
                        prioritized.append(found)
                    }
                }
                let remaining = candidates.filter { !idSet.contains($0.id) }
                self.availableRefactorings = prioritized + remaining
            } else {
                self.availableRefactorings = heuristicSort(candidates: candidates, hasSelection: hasSelection)
            }
        } catch {
            // Graceful fallback to heuristic candidates if AI call fails
            self.availableRefactorings = heuristicSort(candidates: candidates, hasSelection: hasSelection)
        }
    }
    
    // MARK: - Preview Generation
    
    /// Generates a preview for the specified refactoring operation
    public func previewRefactoring(
        operation: RefactoringOperation,
        content: String,
        selection: String?
    ) async throws -> RefactoringPreview {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SmartRefactorError.noCodeProvided
        }
        
        lastError = nil
        let hasSelection = selection != nil && !selection!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let targetCode = hasSelection ? selection! : content
        
        let systemPrompt = systemPrompt(for: operation.category, operation: operation)
        
        var userPrompt = "Refactor the following code using the operation: \"\(operation.name)\" (\(operation.id)).\n\n"
        userPrompt += "Description: \(operation.description)\n\n"
        
        if hasSelection {
            userPrompt += "TARGET CODE TO REFACTOR (SELECTION):\n```\n\(targetCode)\n```\n\n"
            userPrompt += "SURROUNDING FILE CONTEXT FOR REFERENCE:\n```\n\(content)\n```\n\n"
            userPrompt += "Return ONLY the refactored replacement for the selection."
        } else {
            userPrompt += "FULL FILE CODE TO REFACTOR:\n```\n\(content)\n```\n\n"
            userPrompt += "Return the entire refactored file."
        }
        
        let messages = [
            (role: "system", content: systemPrompt),
            (role: "user", content: userPrompt)
        ]
        
        do {
            let stream = try await AIClient.shared.streamCompletion(
                messages: messages,
                stream: false
            )
            
            var generatedText = ""
            for try await chunk in stream {
                generatedText += chunk
            }
            
            let cleanRefactoredCode = extractCleanCode(from: generatedText)
            let risk = determineRiskLevel(for: operation, originalCode: targetCode, refactoredCode: cleanRefactoredCode)
            
            let previewResult = RefactoringPreview(
                operation: operation,
                originalCode: targetCode,
                refactoredCode: cleanRefactoredCode,
                affectedFiles: [],
                riskLevel: risk,
                explanation: "Applied \(operation.name) to streamline code structure."
            )
            
            self.preview = previewResult
            return previewResult
        } catch {
            let err = SmartRefactorError.generationFailed(error.localizedDescription)
            self.lastError = err.localizedDescription
            throw err
        }
    }
    
    // MARK: - Apply Refactoring
    
    /// Applies the generated refactoring preview to disk and records changes
    public func applyRefactoring(preview: RefactoringPreview) async throws {
        // 1. Write changes if affected files are specified
        for filePath in preview.affectedFiles {
            let url = URL(fileURLWithPath: filePath)
            if FileManager.default.fileExists(atPath: filePath) {
                do {
                    let existing = try String(contentsOf: url, encoding: .utf8)
                    let updated: String
                    if existing == preview.originalCode {
                        updated = preview.refactoredCode
                    } else if existing.contains(preview.originalCode) {
                        updated = existing.replacingOccurrences(of: preview.originalCode, with: preview.refactoredCode)
                    } else {
                        updated = preview.refactoredCode
                    }
                    try updated.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    throw SmartRefactorError.applyFailed("Failed writing to \(filePath): \(error.localizedDescription)")
                }
            }
            
            // Record change in AgentService pending changes
            let change = PendingChangeModel(
                id: UUID().uuidString,
                filePath: filePath,
                description: "\(preview.operation.name): \(preview.operation.description)",
                additions: preview.additionsCount,
                deletions: preview.deletionsCount,
                oldContent: preview.originalCode,
                newContent: preview.refactoredCode,
                status: .accepted
            )
            AgentService.shared.pendingChanges.append(change)
        }
        
        // If no explicit file path was specified, still record pending change model
        if preview.affectedFiles.isEmpty {
            let change = PendingChangeModel(
                id: UUID().uuidString,
                filePath: "active_editor_buffer",
                description: "\(preview.operation.name): \(preview.operation.description)",
                additions: preview.additionsCount,
                deletions: preview.deletionsCount,
                oldContent: preview.originalCode,
                newContent: preview.refactoredCode,
                status: .accepted
            )
            AgentService.shared.pendingChanges.append(change)
        }
        
        // Broadcast notification for UI listeners
        NotificationCenter.default.post(
            name: NSNotification.Name("SmartRefactorDidApply"),
            object: preview
        )
        
        // Reset preview upon successful application
        self.preview = nil
    }
    
    // MARK: - Private Helpers
    
    private func heuristicSort(candidates: [RefactoringOperation], hasSelection: Bool) -> [RefactoringOperation] {
        if hasSelection {
            let selectionPriority: [String] = [
                "extractMethod", "extractVariable", "extractComponent",
                "inlineVariable", "inlineMethod", "simplifyConditionals",
                "convertLoop", "usePatternMatching", "useOptionalChaining",
                "addErrorHandling", "addNullChecks", "addTypeAnnotations", "addDocComments"
            ]
            return candidates.sorted { op1, op2 in
                let index1 = selectionPriority.firstIndex(of: op1.id) ?? 999
                let index2 = selectionPriority.firstIndex(of: op2.id) ?? 999
                return index1 < index2
            }
        } else {
            let filePriority: [String] = [
                "groupImports", "optimizeImports", "reorderMembers",
                "removeDeadCode", "simplifyConditionals", "useModernSyntax",
                "extractInterface", "splitFile", "moveToFile",
                "addDocComments", "addErrorHandling"
            ]
            return candidates.sorted { op1, op2 in
                let index1 = filePriority.firstIndex(of: op1.id) ?? 999
                let index2 = filePriority.firstIndex(of: op2.id) ?? 999
                return index1 < index2
            }
        }
    }
    
    private func determineRiskLevel(
        for operation: RefactoringOperation,
        originalCode: String,
        refactoredCode: String
    ) -> RefactoringRiskLevel {
        switch operation.category {
        case .optimize:
            return .low
        case .safety:
            return .low
        case .inline:
            return operation.id == "inlineType" ? .medium : .low
        case .extract:
            if operation.id == "extractInterface" || operation.id == "extractComponent" {
                return .medium
            }
            return .low
        case .modernize:
            return operation.id == "useAsyncAwait" ? .medium : .low
        case .restructure:
            if operation.id == "splitFile" || operation.id == "moveToFile" {
                return .high
            }
            return .medium
        }
    }
    
    private func extractCleanCode(from response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            if lines.count >= 2 && lines.first?.hasPrefix("```") == true && lines.last?.hasPrefix("```") == true {
                let innerLines = lines.dropFirst().dropLast()
                return innerLines.joined(separator: "\n")
            }
        }
        return trimmed
    }
    
    private func systemPrompt(for category: RefactoringCategory, operation: RefactoringOperation) -> String {
        let base = """
        You are an expert compiler and software refactoring engineer.
        You are executing the semantic refactoring operation: "\(operation.name)" (\(operation.id)).
        
        RULES:
        1. Preserve exact runtime behavior, edge cases, and semantics unless the refactoring specifically addresses logic simplification.
        2. Output ONLY the replacement code inside a single standard markdown code block: ``` ... ```
        3. Do NOT add any conversational explanation, preamble, or epilogue.
        4. Maintain existing indentation, naming conventions, and style.
        """
        
        let categoryPrompt: String
        switch category {
        case .extract:
            categoryPrompt = """
            CATEGORY FOCUS - EXTRACT:
            - Accurately determine all inputs, bound variables, and return values.
            - Produce clean signatures with descriptive parameter and function names.
            - Avoid unnecessary closures or unintended state mutation.
            """
        case .inline:
            categoryPrompt = """
            CATEGORY FOCUS - INLINE:
            - Substitute expressions or method bodies cleanly at usage sites.
            - Preserve mathematical and logical operator precedence using parentheses when required.
            - Avoid duplicating side-effecting operations.
            """
        case .restructure:
            categoryPrompt = """
            CATEGORY FOCUS - RESTRUCTURE:
            - Organize declarations canonically: imports, type definitions, stored properties, inits, methods, extensions.
            - Maintain appropriate visibility (public, internal, private).
            - Group related logic cohesively.
            """
        case .optimize:
            categoryPrompt = """
            CATEGORY FOCUS - OPTIMIZE:
            - Eliminate dead, unreachable, or redundant logic.
            - Apply early exits, guard clauses, and De Morgan's laws to flatten nested branching.
            - Convert loops to clean, idiomatic functional pipelines where readability is enhanced.
            """
        case .modernize:
            categoryPrompt = """
            CATEGORY FOCUS - MODERNIZE:
            - Convert callback-based asynchronous flows to native async/await.
            - Adopt pattern matching, enum destructuring, and concise switch statements.
            - Leverage safe optional chaining and the latest language constructs.
            """
        case .safety:
            categoryPrompt = """
            CATEGORY FOCUS - SAFETY:
            - Add robust error handling with typed errors and informative error propagation.
            - Introduce defensive null/nil validation with guard clauses or safe unwrapping.
            - Ensure explicit type annotations and comprehensive documentation comments.
            """
        }
        
        return base + "\n\n" + categoryPrompt
    }
}


