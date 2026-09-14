// Copyright © 2025 Dotmini Software. All rights reserved.

import Foundation
import SwiftUI
import Combine

// MARK: - Test Framework

public enum TestFramework: String, Codable, CaseIterable, Identifiable {
    case xctest = "xctest"
    case pytest = "pytest"
    case jest = "jest"
    case mocha = "mocha"
    case cargo_test = "cargo_test"
    case go_test = "go_test"
    case junit = "junit"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .xctest: return "XCTest"
        case .pytest: return "pytest"
        case .jest: return "Jest"
        case .mocha: return "Mocha"
        case .cargo_test: return "Cargo Test"
        case .go_test: return "Go Test"
        case .junit: return "JUnit"
        }
    }
    
    public var fileExtension: String {
        switch self {
        case .xctest: return "swift"
        case .pytest: return "py"
        case .jest: return "test.ts"
        case .mocha: return "test.js"
        case .cargo_test: return "rs"
        case .go_test: return "go"
        case .junit: return "java"
        }
    }
    
    public var defaultTestDirectory: String {
        switch self {
        case .xctest: return "Tests"
        case .pytest: return "tests"
        case .jest, .mocha: return "__tests__"
        case .cargo_test: return "tests"
        case .go_test: return ""
        case .junit: return "src/test/java"
        }
    }
    
    public var cliCommand: String {
        switch self {
        case .xctest: return "swift test"
        case .pytest: return "pytest"
        case .jest: return "npm test"
        case .mocha: return "npx mocha"
        case .cargo_test: return "cargo test"
        case .go_test: return "go test ./..."
        case .junit: return "mvn test"
        }
    }
}

// MARK: - Test Status

public enum TestStatus: String, Codable, CaseIterable {
    case generated
    case accepted
    case rejected
    case modified
}

// MARK: - Generated Test Model

public struct GeneratedTest: Identifiable, Codable, Equatable {
    public var id: UUID
    public var sourceFile: String
    public var testFile: String
    public var testCode: String
    public var language: String
    public var framework: TestFramework
    public var status: TestStatus
    public var testCount: Int
    public var createdAt: Date
    
    public init(
        id: UUID = UUID(),
        sourceFile: String,
        testFile: String,
        testCode: String,
        language: String,
        framework: TestFramework,
        status: TestStatus = .generated,
        testCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceFile = sourceFile
        self.testFile = testFile
        self.testCode = testCode
        self.language = language
        self.framework = framework
        self.status = status
        self.testCount = testCount
        self.createdAt = createdAt
    }
}

// MARK: - Test Coverage Model

public struct TestCoverage: Codable, Equatable {
    public var totalFunctions: Int
    public var coveredFunctions: Int
    public var percentage: Double
    public var uncoveredFunctions: [String]
    
    public init(
        totalFunctions: Int,
        coveredFunctions: Int,
        percentage: Double,
        uncoveredFunctions: [String]
    ) {
        self.totalFunctions = totalFunctions
        self.coveredFunctions = coveredFunctions
        self.percentage = percentage
        self.uncoveredFunctions = uncoveredFunctions
    }
    
    public var formattedPercentage: String {
        String(format: "%.1f%%", percentage)
    }
    
    public var isComplete: Bool {
        percentage >= 100.0
    }
}

// MARK: - Test Generator Errors

public enum TestGeneratorError: LocalizedError {
    case invalidInput(String)
    case generationFailed(String)
    case coverageAnalysisFailed(String)
    case writeFailed(String)
    case testNotFound(UUID)
    
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Invalid input for test generator: \(message)"
        case .generationFailed(let message):
            return "Test generation failed: \(message)"
        case .coverageAnalysisFailed(let message):
            return "Coverage analysis failed: \(message)"
        case .writeFailed(let message):
            return "Failed to write test file: \(message)"
        case .testNotFound(let id):
            return "Generated test with ID \(id) not found"
        }
    }
}

// MARK: - Test Generator Service

@MainActor
public class TestGeneratorService: ObservableObject {
    public static let shared = TestGeneratorService()
    
    @Published public var generatedTests: [GeneratedTest] = []
    @Published public var isGenerating: Bool = false
    @Published public var coverage: TestCoverage?
    @Published public var lastError: String?
    
    private init() {}
    
    // MARK: - 1. Detect Test Framework
    
    /// Auto-detects the appropriate test framework by inspecting project marker files or falling back to language.
    public func detectTestFramework(language: String, projectPath: String) -> TestFramework {
        let fileManager = FileManager.default
        var searchURL = URL(fileURLWithPath: projectPath)
        
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: searchURL.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                searchURL = searchURL.deletingLastPathComponent()
            }
        }
        
        // Scan up to 4 directory levels up looking for project config manifests
        var currentDir = searchURL
        for _ in 0..<4 {
            let path = currentDir.path
            
            // Rust Cargo
            if fileManager.fileExists(atPath: currentDir.appendingPathComponent("Cargo.toml").path) {
                return .cargo_test
            }
            
            // Go Module
            if fileManager.fileExists(atPath: currentDir.appendingPathComponent("go.mod").path) {
                return .go_test
            }
            
            // Apple Swift / Xcode
            if fileManager.fileExists(atPath: currentDir.appendingPathComponent("Package.swift").path) {
                return .xctest
            }
            if let files = try? fileManager.contentsOfDirectory(atPath: path) {
                if files.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
                    return .xctest
                }
            }
            
            // Java / Kotlin (Maven / Gradle)
            if fileManager.fileExists(atPath: currentDir.appendingPathComponent("pom.xml").path) ||
               fileManager.fileExists(atPath: currentDir.appendingPathComponent("build.gradle").path) ||
               fileManager.fileExists(atPath: currentDir.appendingPathComponent("build.gradle.kts").path) {
                return .junit
            }
            
            // Python
            if fileManager.fileExists(atPath: currentDir.appendingPathComponent("pytest.ini").path) ||
               fileManager.fileExists(atPath: currentDir.appendingPathComponent("conftest.py").path) ||
               fileManager.fileExists(atPath: currentDir.appendingPathComponent("pyproject.toml").path) ||
               fileManager.fileExists(atPath: currentDir.appendingPathComponent("setup.cfg").path) {
                return .pytest
            }
            
            // Node.js (package.json)
            let packageJsonURL = currentDir.appendingPathComponent("package.json")
            if fileManager.fileExists(atPath: packageJsonURL.path),
               let data = try? Data(contentsOf: packageJsonURL),
               let content = String(data: data, encoding: .utf8) {
                if content.contains("\"mocha\"") && !content.contains("\"jest\"") {
                    return .mocha
                }
                return .jest
            }
            
            let parent = currentDir.deletingLastPathComponent()
            if parent.path == currentDir.path { break }
            currentDir = parent
        }
        
        // Language-based fallback
        let normalizedLang = language.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalizedLang {
        case "swift":
            return .xctest
        case "python", "py":
            return .pytest
        case "javascript", "js", "typescript", "ts", "jsx", "tsx", "node":
            return .jest
        case "rust", "rs":
            return .cargo_test
        case "go", "golang":
            return .go_test
        case "java", "kotlin", "kt":
            return .junit
        default:
            let ext = (projectPath as NSString).pathExtension.lowercased()
            switch ext {
            case "swift": return .xctest
            case "py": return .pytest
            case "ts", "tsx", "js", "jsx": return .jest
            case "rs": return .cargo_test
            case "go": return .go_test
            case "java", "kt": return .junit
            default: return .xctest
            }
        }
    }
    
    // MARK: - 2. Suggest Test File Path
    
    /// Determines the standard test file path for a given source file and framework.
    public func suggestTestFilePath(forSourceFile sourcePath: String, framework: TestFramework) -> String {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let fileNameWithoutExt = sourceURL.deletingPathExtension().lastPathComponent
        let parentDir = sourceURL.deletingLastPathComponent()
        
        switch framework {
        case .xctest:
            let components = sourceURL.pathComponents
            if let sourcesIdx = components.firstIndex(of: "Sources") {
                var testComponents = components
                testComponents[sourcesIdx] = "Tests"
                let targetModuleIdx = sourcesIdx + 1
                if targetModuleIdx < testComponents.count - 1 {
                    testComponents[targetModuleIdx] = testComponents[targetModuleIdx] + "Tests"
                }
                testComponents[testComponents.count - 1] = "\(fileNameWithoutExt)Tests.swift"
                return NSString.path(withComponents: testComponents)
            }
            let testsDir = parentDir.appendingPathComponent("Tests")
            return testsDir.appendingPathComponent("\(fileNameWithoutExt)Tests.swift").path
            
        case .pytest:
            let testsDir = parentDir.appendingPathComponent("tests")
            return testsDir.appendingPathComponent("test_\(fileNameWithoutExt).py").path
            
        case .jest:
            let ext = sourceURL.pathExtension.isEmpty ? "ts" : sourceURL.pathExtension
            return parentDir.appendingPathComponent("\(fileNameWithoutExt).test.\(ext)").path
            
        case .mocha:
            let ext = sourceURL.pathExtension.isEmpty ? "js" : sourceURL.pathExtension
            return parentDir.appendingPathComponent("\(fileNameWithoutExt).test.\(ext)").path
            
        case .cargo_test:
            let rootDir = parentDir.lastPathComponent == "src" ? parentDir.deletingLastPathComponent() : parentDir
            let testsDir = rootDir.appendingPathComponent("tests")
            return testsDir.appendingPathComponent("\(fileNameWithoutExt)_test.rs").path
            
        case .go_test:
            return parentDir.appendingPathComponent("\(fileNameWithoutExt)_test.go").path
            
        case .junit:
            let pathStr = sourceURL.path
            if pathStr.contains("/src/main/") {
                let testPath = pathStr.replacingOccurrences(of: "/src/main/", with: "/src/test/")
                let testURL = URL(fileURLWithPath: testPath)
                return testURL.deletingLastPathComponent().appendingPathComponent("\(fileNameWithoutExt)Test.java").path
            }
            return parentDir.appendingPathComponent("\(fileNameWithoutExt)Test.java").path
        }
    }
    
    // MARK: - 3. Count Tests in Code
    
    /// Parses test code using framework-specific regex to count generated test cases.
    public func countTests(in code: String, framework: TestFramework) -> Int {
        let pattern: String
        switch framework {
        case .xctest:
            pattern = #"func\s+test[A-Za-z0-9_]*\s*\("#
        case .pytest:
            pattern = #"def\s+test_[a-zA-Z0-9_]*\s*\("#
        case .jest, .mocha:
            pattern = #"(?:test|it)\s*\(\s*["'`]"#
        case .cargo_test:
            pattern = #"#\[(?:tokio::)?test\]"#
        case .go_test:
            pattern = #"func\s+Test[A-Za-z0-9_]*\s*\("#
        case .junit:
            pattern = #"@Test"#
        }
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let count = regex.numberOfMatches(in: code, options: [], range: NSRange(location: 0, length: code.utf16.count))
            if count > 0 { return count }
        }
        
        // Fallback: estimate from assertion lines
        let lines = code.components(separatedBy: .newlines)
        let fallbackMatches = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.contains("test") || trimmed.contains("Test") || trimmed.contains("assert") || trimmed.contains("expect(")
        }.count
        return max(1, min(fallbackMatches, 15))
    }
    
    // MARK: - 4. Generate Tests
    
    /// Analyzes source code and automatically generates unit tests ready to save.
    public func generateTests(forFile path: String, content: String, language: String) async throws {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw TestGeneratorError.invalidInput("Source file content cannot be empty.")
        }
        
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }
        
        let framework = detectTestFramework(language: language, projectPath: path)
        let suggestedTestPath = suggestTestFilePath(forSourceFile: path, framework: framework)
        
        let systemPrompt = "Generate comprehensive unit tests for the following code. Include edge cases, error paths, and boundary conditions."
        let userPrompt = """
        Source File: \(path)
        Language: \(language)
        Target Framework: \(framework.displayName) (\(framework.rawValue))
        Suggested Destination: \(suggestedTestPath)
        
        Source Code:
        ```\(language)
        \(content)
        ```
        
        Requirements:
        1. Generate a complete, self-contained test file ready to save directly to disk.
        2. Test all primary functions, error handling paths, boundary conditions, and invalid inputs.
        3. Include all required imports, test suites, mocks, and lifecycle methods (setUp / tearDown).
        4. Write clean, production-ready code with clear assertion messages.
        5. Return ONLY the code for the test file. Do not include markdown preamble or conversational explanations.
        """
        
        let (model, provider) = currentModelAndProvider()
        let messages = [
            (role: "system", content: systemPrompt),
            (role: "user", content: userPrompt)
        ]
        
        do {
            let stream = try await AIClient.shared.streamCompletion(
                messages: messages,
                model: model,
                provider: provider,
                tools: nil,
                stream: false
            )
            
            var responseText = ""
            for try await chunk in stream {
                responseText += chunk
            }
            
            let testCode = stripMarkdownFences(from: responseText)
            guard !testCode.isEmpty else {
                throw TestGeneratorError.generationFailed("AI returned empty test code.")
            }
            
            let count = countTests(in: testCode, framework: framework)
            let testItem = GeneratedTest(
                id: UUID(),
                sourceFile: path,
                testFile: suggestedTestPath,
                testCode: testCode,
                language: language,
                framework: framework,
                status: .generated,
                testCount: count
            )
            
            if let index = generatedTests.firstIndex(where: { $0.sourceFile == path }) {
                generatedTests[index] = testItem
            } else {
                generatedTests.append(testItem)
            }
            
            // Automatically assess coverage
            _ = try? await analyzeTestCoverage(sourceFile: path, testFile: suggestedTestPath)
            
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - 5. Generate Edge Cases
    
    /// Generates targeted edge case and boundary tests for a specific function or context.
    public func generateEdgeCases(forFunction functionName: String, context: String) async throws -> [GeneratedTest] {
        let trimmedFunction = functionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFunction.isEmpty else {
            throw TestGeneratorError.invalidInput("Function name cannot be empty.")
        }
        
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }
        
        let framework = detectTestFramework(language: "swift", projectPath: context)
        let systemPrompt = "Generate comprehensive unit tests for the following code. Include edge cases, error paths, and boundary conditions."
        let userPrompt = """
        Target Function: `\(trimmedFunction)`
        
        Context and Implementation:
        ```
        \(context)
        ```
        
        Generate specialized edge-case unit tests specifically targeting `\(trimmedFunction)`.
        Test scenarios:
        1. Boundary limits: maximum/minimum integer or floating-point values, off-by-one indices.
        2. Null, empty, zero, and single-element collections or strings.
        3. Malformed data, unexpected characters, and unicode edge cases.
        4. Error handling: thrown exceptions, failure states, network timeouts, or rejected promises.
        5. Concurrency and cancellation paths if applicable.
        
        Format each test case with explicit assertions.
        Return full, executable test methods ready to integrate.
        """
        
        let (model, provider) = currentModelAndProvider()
        let messages = [
            (role: "system", content: systemPrompt),
            (role: "user", content: userPrompt)
        ]
        
        do {
            let stream = try await AIClient.shared.streamCompletion(
                messages: messages,
                model: model,
                provider: provider,
                tools: nil,
                stream: false
            )
            
            var responseText = ""
            for try await chunk in stream {
                responseText += chunk
            }
            
            let fullCode = stripMarkdownFences(from: responseText)
            let blocks = splitIndividualTestMethods(in: fullCode, framework: framework)
            var edgeTests: [GeneratedTest] = []
            
            if !blocks.isEmpty {
                for (index, block) in blocks.enumerated() {
                    let test = GeneratedTest(
                        id: UUID(),
                        sourceFile: trimmedFunction,
                        testFile: "\(trimmedFunction)_EdgeCase_\(index + 1).\(framework.fileExtension)",
                        testCode: block,
                        language: "swift",
                        framework: framework,
                        status: .generated,
                        testCount: 1
                    )
                    edgeTests.append(test)
                }
            } else {
                let count = countTests(in: fullCode, framework: framework)
                let test = GeneratedTest(
                    id: UUID(),
                    sourceFile: trimmedFunction,
                    testFile: "\(trimmedFunction)_EdgeCases.\(framework.fileExtension)",
                    testCode: fullCode,
                    language: "swift",
                    framework: framework,
                    status: .generated,
                    testCount: count
                )
                edgeTests.append(test)
            }
            
            // Add new edge tests to the published collection
            for item in edgeTests {
                if let idx = generatedTests.firstIndex(where: { $0.id == item.id }) {
                    generatedTests[idx] = item
                } else {
                    generatedTests.append(item)
                }
            }
            
            return edgeTests
            
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - 6. Analyze Test Coverage
    
    /// Evaluates test coverage for a source file against its test suite using AI analysis.
    public func analyzeTestCoverage(sourceFile: String, testFile: String) async throws -> TestCoverage {
        let sourceContent = try readContent(for: sourceFile)
        let testContent = try readContent(for: testFile)
        
        let systemPrompt = "You are an expert code quality and test coverage auditor. Analyze the source code and its test file to determine unit test coverage."
        let userPrompt = """
        Analyze unit test coverage for the source code and its test suite.
        
        Source File: \(sourceFile)
        Source Content:
        ```
        \(sourceContent)
        ```
        
        Test File: \(testFile)
        Test Content:
        ```
        \(testContent)
        ```
        
        Analyze:
        1. All callable functions/methods declared in the source code.
        2. Which functions have active test assertions covering them.
        3. Which functions are uncovered or only partially tested.
        4. Calculate coverage percentage (0.0 to 100.0).
        
        Respond with ONLY a raw JSON object conforming strictly to this format:
        {
          "totalFunctions": 5,
          "coveredFunctions": 4,
          "percentage": 80.0,
          "uncoveredFunctions": ["functionName1", "functionName2"]
        }
        """
        
        let (model, provider) = currentModelAndProvider()
        let messages = [
            (role: "system", content: systemPrompt),
            (role: "user", content: userPrompt)
        ]
        
        do {
            let stream = try await AIClient.shared.streamCompletion(
                messages: messages,
                model: model,
                provider: provider,
                tools: nil,
                stream: false
            )
            
            var responseText = ""
            for try await chunk in stream {
                responseText += chunk
            }
            
            let jsonString = stripMarkdownFences(from: responseText)
            
            struct CoverageJSON: Codable {
                let totalFunctions: Int
                let coveredFunctions: Int
                let percentage: Double
                let uncoveredFunctions: [String]
            }
            
            var parsedCoverage: TestCoverage? = nil
            if let data = jsonString.data(using: .utf8) {
                if let decoded = try? JSONDecoder().decode(CoverageJSON.self, from: data) {
                    parsedCoverage = TestCoverage(
                        totalFunctions: decoded.totalFunctions,
                        coveredFunctions: decoded.coveredFunctions,
                        percentage: decoded.percentage,
                        uncoveredFunctions: decoded.uncoveredFunctions
                    )
                }
            }
            
            // Fallback heuristic parser if AI returned non-JSON text
            let finalCoverage = parsedCoverage ?? heuristicCoverage(source: sourceContent, test: testContent)
            self.coverage = finalCoverage
            return finalCoverage
            
        } catch {
            let fallback = heuristicCoverage(source: sourceContent, test: testContent)
            self.coverage = fallback
            return fallback
        }
    }
    
    // MARK: - 7. Write Test File
    
    /// Writes the generated test code directly to the appropriate destination directory on disk.
    public func writeTestFile(test: GeneratedTest) async throws {
        let destination = test.testFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else {
            throw TestGeneratorError.invalidInput("Test file path cannot be empty.")
        }
        
        let targetURL = URL(fileURLWithPath: destination)
        let directoryURL = targetURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: directoryURL.path) {
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                throw TestGeneratorError.writeFailed("Could not create directory at \(directoryURL.path): \(error.localizedDescription)")
            }
        }
        
        do {
            try test.testCode.write(to: targetURL, atomically: true, encoding: .utf8)
        } catch {
            throw TestGeneratorError.writeFailed("Could not write file to \(targetURL.path): \(error.localizedDescription)")
        }
        
        if let index = generatedTests.firstIndex(where: { $0.id == test.id }) {
            generatedTests[index].status = .accepted
        }
    }
    
    // MARK: - 8. Lifecycle & Approval Actions
    
    /// Accepts a generated test and writes it to disk.
    public func acceptTest(id: UUID) async throws {
        guard let test = generatedTests.first(where: { $0.id == id }) else {
            throw TestGeneratorError.testNotFound(id)
        }
        try await writeTestFile(test: test)
    }
    
    /// Rejects a generated test.
    public func rejectTest(id: UUID) {
        if let index = generatedTests.firstIndex(where: { $0.id == id }) {
            generatedTests[index].status = .rejected
        }
    }
    
    /// Updates the code of an existing generated test and marks it modified.
    public func modifyTest(id: UUID, newCode: String) {
        if let index = generatedTests.firstIndex(where: { $0.id == id }) {
            generatedTests[index].testCode = newCode
            generatedTests[index].status = .modified
            generatedTests[index].testCount = countTests(in: newCode, framework: generatedTests[index].framework)
        }
    }
    
    /// Removes a test from the generator collection.
    public func removeTest(id: UUID) {
        generatedTests.removeAll(where: { $0.id == id })
    }
    
    /// Clears all generated tests and coverage metrics.
    public func clearAll() {
        generatedTests.removeAll()
        coverage = nil
        lastError = nil
        isGenerating = false
    }
    
    // MARK: - Private Helpers
    
    private func currentModelAndProvider() -> (model: String, provider: String) {
        let configuredProvider = UserDefaults.standard.string(forKey: "aiProvider") ?? "omni"
        let configuredModel = UserDefaults.standard.string(forKey: "aiModel") ?? StreamableAIProvider.omni.defaultModel
        return (model: configuredModel, provider: configuredProvider)
    }
    
    private func readContent(for path: String) throws -> String {
        // Check disk first
        if FileManager.default.fileExists(atPath: path),
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            return content
        }
        // Check in-memory generated tests
        if let test = generatedTests.first(where: { $0.testFile == path || $0.sourceFile == path }) {
            return test.testCode
        }
        // If the path itself is actually code content (multi-line string)
        if path.contains("\n") || path.contains("func ") || path.contains("class ") {
            return path
        }
        return ""
    }
    
    private func stripMarkdownFences(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            var cleanLines: [String] = []
            var inFence = false
            for line in lines {
                if !inFence && line.hasPrefix("```") {
                    inFence = true
                    continue
                }
                if inFence && line.trimmingCharacters(in: .whitespaces) == "```" {
                    continue
                }
                cleanLines.append(line)
            }
            trimmed = cleanLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
    
    private func splitIndividualTestMethods(in code: String, framework: TestFramework) -> [String] {
        var results: [String] = []
        let lines = code.components(separatedBy: .newlines)
        var current: [String] = []
        var capturing = false
        var braceBalance = 0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isStart: Bool
            switch framework {
            case .xctest:
                isStart = trimmed.hasPrefix("func test")
            case .pytest:
                isStart = trimmed.hasPrefix("def test_")
            case .jest, .mocha:
                isStart = trimmed.hasPrefix("test(") || trimmed.hasPrefix("it(")
            case .cargo_test:
                isStart = trimmed == "#[test]" || trimmed.hasPrefix("#[tokio::test]")
            case .go_test:
                isStart = trimmed.hasPrefix("func Test")
            case .junit:
                isStart = trimmed == "@Test" || trimmed.hasPrefix("@Test(")
            }
            
            if isStart && !capturing {
                capturing = true
                current = [line]
                braceBalance = line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
                continue
            }
            
            if capturing {
                current.append(line)
                braceBalance += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
                
                if framework == .pytest {
                    if !trimmed.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("\t") && !isStart {
                        results.append(current.dropLast().joined(separator: "\n"))
                        current = [line]
                        capturing = false
                    }
                } else if braceBalance <= 0 && current.count > 1 {
                    results.append(current.joined(separator: "\n"))
                    current = []
                    capturing = false
                }
            }
        }
        
        if capturing && !current.isEmpty {
            results.append(current.joined(separator: "\n"))
        }
        
        return results
    }
    
    private func heuristicCoverage(source: String, test: String) -> TestCoverage {
        let funcPattern = #"(?:func|def|fn|function)\s+([A-Za-z0-9_]+)"#
        var declaredFunctions: [String] = []
        
        if let regex = try? NSRegularExpression(pattern: funcPattern, options: []) {
            let matches = regex.matches(in: source, options: [], range: NSRange(location: 0, length: source.utf16.count))
            for match in matches {
                if let range = Range(match.range(at: 1), in: source) {
                    let name = String(source[range])
                    if !name.hasPrefix("init") && !name.hasPrefix("deinit") && !declaredFunctions.contains(name) {
                        declaredFunctions.append(name)
                    }
                }
            }
        }
        
        if declaredFunctions.isEmpty {
            return TestCoverage(totalFunctions: 1, coveredFunctions: 1, percentage: 100.0, uncoveredFunctions: [])
        }
        
        var coveredCount = 0
        var uncovered: [String] = []
        
        for fn in declaredFunctions {
            if test.contains(fn) {
                coveredCount += 1
            } else {
                uncovered.append(fn)
            }
        }
        
        let percentage = (Double(coveredCount) / Double(declaredFunctions.count)) * 100.0
        return TestCoverage(
            totalFunctions: declaredFunctions.count,
            coveredFunctions: coveredCount,
            percentage: (percentage * 10).rounded() / 10,
            uncoveredFunctions: uncovered
        )
    }
}
