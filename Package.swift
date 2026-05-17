// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MicroCode",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MicroCode", targets: ["MicroCode"]),
        .library(name: "MicroCodeCore", targets: ["MicroCodeCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "MicroCodeSupport",
            dependencies: [],
            path: "MicroCodeSupport",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MicroCodeKernel",
            dependencies: [],
            path: "MicroCodeKernel",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MicroCodeCore",
            dependencies: ["MicrocodeCoreSupport"],
            path: "MicroCodeCore/Sources"
        ),
        .executableTarget(
            name: "MicroCode",
            dependencies: ["MicroCodeSupport", "MicroCodeKernel", "SwiftTerm", "MicrocodeCoreSupport", "MicroCodeCore"],
            path: "MicroCode",
            exclude: [
                "Views/Design/DesignModeView.swift",
                "Views/Design/DesignLayersPanel.swift",
                "Views/Design/DesignToolbar.swift",
                "Views/Design/PropertiesInspector.swift",
                "Views/Design/DesignRulerView.swift"
            ],
            sources: [
                "MicroCodeApp.swift",
                "Services/CrashReporter.swift",
                "Managers/ReportLogManager.swift",
                "Managers/PDFGenerator.swift",
                "Models/AppState.swift",
                "Models/AnyCodable.swift",
                "Models/CellModels.swift",
                "Models/MicFormat.swift",
                "Services/BackendService.swift",
                "Services/TerminalService.swift",
                "Services/SimulatorManager.swift",
                "Services/CodeAnalyzer.swift",
                "Services/ExportService.swift",
                "Views/SymbolEffectModifier.swift",
                "Views/ContentView.swift",
                "Views/RefactorProWindow.swift",
                "Views/ExpandCodeWindow.swift",
                "Views/FormatCodeWindow.swift",
                "Views/CodeAnalysisWindow.swift",

                "Views/PlaygroundView.swift",
                "Views/PlaygroundCellView.swift",
                "Views/DocumentViewer.swift",
                "Views/CatalogueSidebar.swift",
                "Views/SyntaxHighlighter.swift",
                "Views/StatusBarView.swift",
                "Views/FileTabBar.swift",
                "Views/NotebookView.swift",
                "Views/DotnetProjectView.swift",
                "Services/DotnetService.swift",
                "Models/MLModels.swift",
                "Services/MLTrainer.swift",
                "Views/AI/AITrainerView.swift",
                "Views/AI/AIAgentView.swift",
                "Services/ProjectManager.swift",
                "Views/ProjectToolbar.swift",
                "Services/PythonEnvManager.swift",
                "Services/ArdiumLSPService.swift",
                "Services/ArdiumRunner.swift",
                "Services/LSPClientService.swift",
                "Services/LSPManager.swift",
                "Views/PythonEnvSheet.swift",
                "Views/EditorView.swift",
                "Views/DotnetToolbar.swift",
                "Models/ScenarioModels.swift",
                "Views/ScenarioView.swift",
                "Services/RuntimeManager.swift",
                "Views/RuntimeManagerView.swift",
                "Views/AI/CodeAnalysisView.swift",
                "Views/CodeAnalysisPanel.swift",
                "Views/GitSettingsView.swift",
                "Views/GitPanelView.swift",
                "Views/FilePreviewView.swift",
                "Services/ExtensionManager.swift",
                "Views/ExtensionSettingsView.swift",
                "Models/AICodeReport.swift",
                "Services/AgentCore/AgentToolBox.swift",
                "Services/AuthService.swift",
                "Services/CollaborationService.swift",
                "Views/EmbeddedToolsView.swift",
                "Views/EmbeddedStudioView.swift",
                "Views/EmbeddedProjectWizard.swift",
                "Views/CollaborationView.swift",
                "Models/SASProcedures.swift",
                "Views/Tasks/GitHistoryView.swift", // New Phase 10
                "Views/Notebook/SASProcedureView.swift", // New Phase 12
                "Views/Notebook/NotebookAIPanel.swift", // Cell Mode AI Agent
                "Models/DesignModels.swift", // Design Engine
                "Services/DesignStore.swift",
                "Services/Design/DesignCodeGenerator.swift",
                "Views/Design/DesignCanvasView.swift",
                // "Views/Design/DesignToolbar.swift", // Replaced by FloatingToolbar
                // "Views/Design/PropertiesInspector.swift", // Replaced by Sidebar
                "Views/Design/DesignElementView.swift",
                // "Views/Design/DesignLayersPanel.swift", // Legacy - Removed
                // "Views/Design/DesignRulerView.swift", // Legacy - Removed
                "Views/Design/Components/DesignInteractionOverlay.swift",
                // "Views/Design/DesignModeView.swift", // Replaced by Workbench
                // Phase 11 Redesign
                "Views/Design/DesignWorkbenchView.swift",
                "Views/Design/DesignNavigatorSidebar.swift",
                "Views/Design/DesignInspectorSidebar.swift",
                "Views/Design/DesignFloatingToolbar.swift",
                "Services/ContainerService.swift",
                "Views/ContainerView.swift",
                "Services/PerformanceManager.swift",
                "Services/PreviewService.swift",
                "Views/PreviewView.swift",
                "Views/Components/ToolWindowWrapper.swift",
                "Views/Components/NodeVersionPicker.swift",
                "Views/RemoteXView.swift",
                "Views/RemoteFileBrowser.swift",
                "Views/RemoteTerminalView.swift",
                "Services/HotReloadClient.swift",
                "Services/UITreeExtractor.swift",
                "Services/AutoHealerService.swift",
                "Services/AgentCore/HealerAgent.swift",
                "Services/AgentCore/TokenOptimizer.swift",
                "Services/DatabaseService.swift",
                "Services/DataFrameService.swift",
                "Services/APIClientService.swift",
                "Services/CICDService.swift",
                "Services/LocalPipelineRunner.swift",
                "Services/AgentService.swift",
                "Services/AgentMemoryService.swift",
                "Services/AIClient.swift",            // Direct AI API Client
                "Services/AIProviderAuthService.swift",// Multi-provider Auth + Keychain
                "Services/KeychainManager.swift",      // Keychain CRUD + Rust FFI Bridge
                "Services/MCPServer.swift",            // MCP Protocol Server
                "Services/LocalLLMService.swift",     // Local LLM Detection (LM Studio, Ollama)
                "Services/AIAutocompleteService.swift", // Ghost Text AI Engine
                
                "Services/MicroCodeService.swift",    // AI Core Service Wrapper
                "Kernel/ComputeKernel.swift",
                "Kernel/JupyterClient.swift",
                "Kernel/JupyterKernel.swift",
                "Kernel/RemoteGPUService.swift",
                "Kernel/RemoteProviderService.swift",
                "Kernel/CloudGPUService.swift",
                "Views/CloudGPUView.swift",
                "Views/Design/AIDesignPanel.swift",
                "Services/AIDesignEngine.swift",
                "Services/BillingService.swift",
                "Services/MicroCore/microcode_core.swift",
                "Views/HealerSuggestionView.swift",
                "Views/UniversalPreviewView.swift",
                "Views/Components/UniversalFilePreview.swift",
                "Views/Components/VisualEffectView.swift",
                "Views/Components/DeviceFrameView.swift",
                "Views/Components/SnowEffectView.swift",
                "Views/Components/ThemePickerView.swift",
                "Views/Components/AuthenticEditor.swift",
                "Views/Components/AuthenticEditor+GhostText.swift",
                "Views/Components/AuthenticFileTree.swift",
                "Views/Components/AuthenticLogConsole.swift",
                "Views/Components/AuthenticTerminal.swift",
                "Views/Components/FestiveOverlayView.swift",
                "Views/Components/LineNumberRulerView.swift",
                "Views/Components/DraggableSplitView.swift",
                "Views/DatabaseStudioView.swift",
                "Views/APIClientView.swift",
                "Views/CICDPipelineView.swift",
                "Views/IDEBrowserView.swift",
                "Views/ModelBrowserSheet.swift",
                "Views/Settings/MicroCodeLicenseSettingsView.swift",
                "Views/TerminalTextView.swift",
                "Views/TerminalWebView.swift",
                "Views/Components/PlaygroundTerminalView.swift",
                "Views/Components/TransparentTerminalView.swift",
                "Views/DataFrameView.swift",
                "Kernel/KernelClient.swift",
                "Kernel/WebEngine.swift",
                "Kernel/ThemeEngine.swift",
                "Kernel/ExtensionSandbox.swift",
                "SyntaxEngine/Token.swift",
                "SyntaxEngine/Lexer.swift",
                "SyntaxEngine/AuthenticLexerAdapter.swift",
                "SyntaxEngine/ThemeManager.swift",
                "SyntaxEngine/SyntaxCache.swift",
                "SyntaxEngine/SyntaxHighlightingEngine.swift",
                "Services/SSHConfigParser.swift",
                "Services/RemoteWorkspaceManager.swift",
                "Services/SharedMemoryService.swift",
                "Views/ProjectRuntimeView.swift",
                "Views/EnvEditorView.swift",
                "Views/NodeProjectManagerView.swift",
                "Views/DataProfilingView.swift",
                "Views/Metal/MetalView.swift",
                "Views/Metal/MetalGridView.swift",
                "Views/Metal/CyberBackgroundView.swift",
                "Extensions/URLExtensions.swift",
                "Extensions/ColorExtensions.swift",
                "Extensions/Compatibility.swift",
                "Extensions/NSColor+Hex.swift",
                "Helpers/GraphemeHelper.swift",
            ],
            resources: [
                // .process("Views/Metal/Shaders.metal")
            ],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        ),
        .target(
            name: "MicrocodeCoreSupport",
            dependencies: [],
            path: "MicrocodeCoreSupport",
            publicHeadersPath: "include"
        )
    ],
    cxxLanguageStandard: .cxx17
)
