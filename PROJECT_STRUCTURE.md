# CodeTunner Project Structure

## 📁 Directory Tree

```
codetunner-native/
│
├── 📄 README.md                      # Main documentation
├── 📄 QUICKSTART.md                  # Quick start guide
├── 📄 MIGRATION_GUIDE.md             # PyQt to SwiftUI migration guide
├── 📄 PROJECT_SUMMARY.md             # Project overview
├── 📄 PROJECT_STRUCTURE.md           # This file
├── 🔧 build.sh                       # Build automation script
│
├── 🦀 backend/                       # Rust Backend Server
│   ├── 📦 Cargo.toml                 # Rust dependencies and build config
│   ├── 📝 .env.example               # Environment variables template
│   │
│   └── 📂 src/                       # Rust source code
│       ├── 🔧 main.rs                # Server entry point & HTTP routing
│       │   ├─ Health check endpoint
│       │   ├─ File operation routes
│       │   ├─ Code operation routes
│       │   ├─ AI operation routes
│       │   ├─ Git operation routes
│       │   ├─ WebSocket handler
│       │   └─ Request handlers
│       │
│       ├── 🤖 ai.rs                  # AI Provider Integration (1,534 lines)
│       │   ├─ AIProvider trait
│       │   ├─ GeminiProvider
│       │   ├─ OpenAIProvider
│       │   ├─ ClaudeProvider
│       │   ├─ refactor() function
│       │   ├─ explain() function
│       │   ├─ complete() function
│       │   └─ list_models() function
│       │
│       ├── 📝 code.rs                # Code operations module wrapper
│       │   └─ Re-exports submodules
│       │
│       ├── 📂 code/                  # Code operations submodules
│       │   ├── 📄 file_ops.rs        # File system operations (306 lines)
│       │   │   ├─ list_directory()
│       │   │   ├─ read_file()
│       │   │   ├─ write_file()
│       │   │   ├─ delete_file()
│       │   │   └─ get_metadata()
│       │   │
│       │   ├── 🔍 analyzer.rs        # Code analysis (433 lines)
│       │   │   ├─ analyze()
│       │   │   ├─ analyze_python()
│       │   │   ├─ analyze_javascript()
│       │   │   ├─ analyze_rust()
│       │   │   ├─ analyze_swift()
│       │   │   └─ calculate_complexity()
│       │   │
│       │   ├── 💅 formatter.rs       # Code formatting (167 lines)
│       │   │   ├─ format()
│       │   │   ├─ format_python()
│       │   │   ├─ format_javascript()
│       │   │   ├─ format_rust()
│       │   │   └─ format_swift()
│       │   │
│       │   └── 🎨 highlighter.rs     # Syntax highlighting (127 lines)
│       │       ├─ highlight()
│       │       ├─ get_available_themes()
│       │       └─ get_available_languages()
│       │
│       ├── 🔧 git.rs                 # Git operations (281 lines)
│       │   ├─ status()
│       │   ├─ commit()
│       │   ├─ push()
│       │   ├─ pull()
│       │   ├─ log()
│       │   └─ diff()
│       │
│       ├── ▶️ runner.rs               # Code execution (419 lines)
│       │   ├─ execute()
│       │   ├─ execute_python()
│       │   ├─ execute_javascript()
│       │   ├─ execute_rust()
│       │   ├─ execute_go()
│       │   ├─ execute_ruby()
│       │   └─ execute_swift()
│       │
│       ├── ❌ error.rs                # Error handling (124 lines)
│       │   ├─ AppError enum
│       │   ├─ Result type alias
│       │   └─ IntoResponse implementation
│       │
│       ├── 📊 models.rs               # Data models (366 lines)
│       │   ├─ Request/Response types
│       │   ├─ FileInfo, CodeAnalysis
│       │   ├─ AIConfig, AIModel
│       │   ├─ GitStatus, GitCommit
│       │   └─ ExecutionOutput
│       │
│       └── 🗂️ state.rs                # Application state (241 lines)
│           ├─ AppState struct
│           ├─ ExecutionInfo
│           ├─ WatcherInfo
│           └─ Configuration structs
│
└── 🍎 CodeTunner/                    # SwiftUI Frontend (macOS App)
    ├── 🚀 CodeTunnerApp.swift        # App entry point (186 lines)
    │   ├─ @main App struct
    │   ├─ WindowGroup configuration
    │   ├─ Menu commands
    │   ├─ Keyboard shortcuts
    │   └─ AppDelegate
    │
    ├── 📂 Models/                    # Data models & state
    │   └── 🔄 AppState.swift         # Observable app state (593 lines)
    │       ├─ @Published properties
    │       ├─ File operations
    │       ├─ Code execution
    │       ├─ AI operations
    │       ├─ Git operations
    │       └─ View management
    │
    ├── 📂 Views/                     # UI components
    │   └── 🖼️ ContentView.swift      # Main UI (766 lines)
    │       ├─ ContentView (main layout)
    │       ├─ SidebarView (file tree)
    │       ├─ TabBarView (open files)
    │       ├─ EditorView (code editor)
    │       ├─ ConsoleView (output)
    │       ├─ GitPanelView (git status)
    │       ├─ WelcomeView (startup)
    │       ├─ RefactorDialog
    │       ├─ CommitDialog
    │       └─ SettingsView
    │
    └── 📂 Services/                  # Backend communication
        └── 🌐 BackendService.swift   # HTTP client (449 lines)
            ├─ Backend process management
            ├─ File operations API
            ├─ Code operations API
            ├─ AI operations API
            ├─ Git operations API
            ├─ Code execution API
            └─ Request/Response models
```

## 📊 Statistics

### Backend (Rust)
- **Total Lines**: ~4,000+ lines
- **Modules**: 10 main modules
- **API Endpoints**: 20+ REST endpoints
- **Supported Languages**: 8+ programming languages
- **AI Providers**: 3 (Gemini, OpenAI, Claude)

### Frontend (SwiftUI)
- **Total Lines**: ~2,000+ lines
- **Views**: 12+ SwiftUI views
- **State Management**: 1 centralized AppState
- **Services**: 1 backend communication service
- **UI Components**: Native macOS components

## 🔄 Data Flow

```
User Action (SwiftUI)
        ↓
    AppState
        ↓
  BackendService
        ↓
   HTTP Request
        ↓
  Rust Backend (Axum)
        ↓
   Route Handler
        ↓
  Business Logic
  (ai.rs, git.rs, etc.)
        ↓
  External Services
  (AI APIs, Git, etc.)
        ↓
   HTTP Response
        ↓
  BackendService
        ↓
    AppState
        ↓
  SwiftUI View Update
```

## 🎯 Key Components

### Backend Core (Rust)

1. **main.rs** - HTTP Server
   - Axum web framework
   - REST API routes
   - WebSocket support
   - Middleware (CORS, logging)

2. **ai.rs** - AI Integration
   - Multi-provider support
   - Async API calls
   - Error handling
   - Response parsing

3. **git.rs** - Version Control
   - git2 library integration
   - Repository operations
   - Commit management
   - Remote sync

4. **runner.rs** - Code Execution
   - Multi-language support
   - Process management
   - Output capture
   - Timeout handling

5. **code/** - Code Operations
   - File I/O
   - Syntax analysis
   - Code formatting
   - Syntax highlighting

### Frontend Core (Swift)

1. **CodeTunnerApp.swift** - App Lifecycle
   - Window management
   - Menu commands
   - Keyboard shortcuts
   - Settings

2. **AppState.swift** - State Management
   - Observable object
   - File management
   - Backend communication
   - UI state

3. **ContentView.swift** - User Interface
   - Layout structure
   - Editor components
   - Sidebar & panels
   - Dialogs & sheets

4. **BackendService.swift** - API Client
   - HTTP requests
   - JSON encoding/decoding
   - Error handling
   - Async operations

## 🔌 API Endpoints

### File Operations
```
POST /api/files/list     - List directory contents
POST /api/files/read     - Read file content
POST /api/files/write    - Write file content
POST /api/files/delete   - Delete file or directory
```

### Code Operations
```
POST /api/code/analyze    - Analyze code structure
POST /api/code/format     - Format code
POST /api/code/highlight  - Get syntax tokens
```

### AI Operations
```
POST /api/ai/refactor    - Refactor code with AI
POST /api/ai/explain     - Explain code with AI
POST /api/ai/complete    - Complete code with AI
GET  /api/ai/models      - List available models
```

### Git Operations
```
POST /api/git/status     - Get repository status
POST /api/git/commit     - Commit changes
POST /api/git/push       - Push to remote
POST /api/git/pull       - Pull from remote
POST /api/git/log        - Get commit history
POST /api/git/diff       - Get file differences
```

### Code Execution
```
POST /api/run/execute    - Execute code
POST /api/run/stop       - Stop execution
```

## 🛠️ Technology Stack

### Backend
- **Language**: Rust 🦀
- **Web Framework**: Axum
- **Async Runtime**: Tokio
- **HTTP Client**: Reqwest
- **Git Library**: git2
- **Syntax Highlighting**: Syntect
- **Serialization**: Serde
- **Logging**: Tracing

### Frontend
- **Language**: Swift 🍎
- **UI Framework**: SwiftUI
- **State Management**: Combine
- **Text Editing**: AppKit (NSTextView)
- **HTTP Client**: URLSession

## 📦 Build Artifacts

### Backend
```
backend/target/release/
└── codetunner-backend    # Single binary (~15MB)
```

### Frontend
```
CodeTunner.app/
├── Contents/
│   ├── MacOS/
│   │   └── CodeTunner    # Executable
│   ├── Resources/
│   └── Info.plist
```

## 🚀 Deployment

### Development
```bash
# Terminal 1: Backend
cd backend && cargo run

# Terminal 2: Frontend
open CodeTunner.xcodeproj
# Press ⌘R in Xcode
```

### Production
```bash
# Build backend
cd backend
cargo build --release

# Archive frontend
# Xcode → Product → Archive
```

## 📈 Performance

- **Backend Memory**: ~20-50 MB idle
- **Frontend Memory**: ~30-50 MB idle
- **Startup Time**: < 1 second
- **API Response**: < 100ms (local)
- **File Load**: < 50ms (1MB file)

## 🔐 Security

- API keys in environment variables
- Code execution in isolated processes
- Input validation on all endpoints
- HTTPS for external API calls
- No sensitive data in logs

## 📝 License

Elastic License v2 (ELv2) & BSL - See LICENSE and README.md for details

---

**Version**: 2.0.1  
**Maintained by**: Dotmini Company Limited (Tirawat Nantamas)  

Made with ❤️ by Dotmini Company Limited