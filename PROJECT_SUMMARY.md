# CodeTunner - Project Summary

## 🎯 Overview

CodeTunner is a modern, AI-powered code editor built with a native SwiftUI frontend and high-performance Rust backend. It combines the power of native macOS UI with the speed and safety of Rust, offering developers a seamless coding experience with integrated AI assistance, Git support, and multi-language code execution.

## 🏗️ Architecture

### Frontend: SwiftUI (macOS Native)
- **Language**: Swift
- **Framework**: SwiftUI
- **Minimum Version**: macOS 13.0+
- **Features**:
  - Native macOS appearance and behavior
  - Hardware-accelerated rendering
  - Native keyboard shortcuts
  - System theme support (Light/Dark mode)
  - Multi-tab interface
  - Real-time code editing with NSTextView
  - Responsive sidebar and panels

### Backend: Rust Web Server
- **Language**: Rust
- **Framework**: Axum (async web framework)
- **Runtime**: Tokio (async runtime)
- **Features**:
  - RESTful API architecture
  - WebSocket support for real-time updates
  - Multi-threaded execution
  - Type-safe error handling
  - Zero-cost abstractions
  - Memory safety guarantees

## 📂 Project Structure

```
codetunner-native/
│
├── backend/                          # Rust Backend
│   ├── src/
│   │   ├── main.rs                  # Server entry point & routing
│   │   ├── ai.rs                    # AI provider integrations
│   │   ├── code/
│   │   │   ├── mod.rs               # Code operations module
│   │   │   ├── file_ops.rs          # File I/O operations
│   │   │   ├── analyzer.rs          # Code analysis
│   │   │   ├── formatter.rs         # Code formatting
│   │   │   └── highlighter.rs       # Syntax highlighting
│   │   ├── git.rs                   # Git operations
│   │   ├── runner.rs                # Code execution
│   │   ├── error.rs                 # Error types & handling
│   │   ├── models.rs                # Data models
│   │   └── state.rs                 # Application state
│   ├── Cargo.toml                   # Rust dependencies
│   └── .env.example                 # Environment template
│
├── CodeTunner/                       # SwiftUI Frontend
│   ├── CodeTunnerApp.swift          # App entry point
│   ├── Models/
│   │   └── AppState.swift           # Observable app state
│   ├── Views/
│   │   └── ContentView.swift        # Main UI components
│   └── Services/
│       └── BackendService.swift     # HTTP client for backend
│
├── build.sh                          # Build automation script
├── README.md                         # Full documentation
├── QUICKSTART.md                     # Quick start guide
└── PROJECT_SUMMARY.md               # This file
```

## 🔧 Technology Stack

### Backend Dependencies
- **axum**: Web framework for building REST APIs
- **tokio**: Async runtime for concurrent operations
- **tower-http**: Middleware for CORS, tracing, etc.
- **serde/serde_json**: Serialization/deserialization
- **reqwest**: HTTP client for AI API calls
- **git2**: Native Git integration
- **syntect**: Syntax highlighting engine
- **tracing**: Structured logging
- **anyhow/thiserror**: Error handling

### Frontend Technologies
- **SwiftUI**: Modern declarative UI framework
- **Combine**: Reactive programming framework
- **Foundation**: Core iOS/macOS APIs
- **AppKit**: NSTextView for code editing

## 🚀 Key Features

### 1. AI Integration
- **Multiple Providers**: Gemini, OpenAI (GPT-4), Claude
- **AI-Powered Refactoring**: Transform code with natural language instructions
- **Code Explanation**: Get detailed explanations of complex code
- **Code Completion**: Intelligent code suggestions

### 2. Code Editing
- **Multi-Tab Interface**: Work on multiple files simultaneously
- **Syntax Highlighting**: Support for 20+ programming languages
- **Line Numbers**: Easy navigation and debugging
- **Font Customization**: Adjustable font size
- **Auto-Save**: Never lose your work

### 3. Code Execution
- **Multi-Language Support**: Python, JavaScript, Rust, Swift, Go, Ruby
- **Real-Time Output**: See stdout and stderr in console
- **Execution Control**: Start and stop processes
- **Error Reporting**: Detailed error messages and stack traces

### 4. Git Integration
- **Status View**: See changed, added, and deleted files
- **Commit**: Create commits with custom messages
- **Push/Pull**: Sync with remote repositories
- **Branch Info**: View current branch and ahead/behind status
- **Diff View**: See file changes

### 5. File Management
- **File Tree**: Browse project files in sidebar
- **Quick Open**: Fast file opening with keyboard shortcuts
- **Drag & Drop**: Import files easily
- **Context Menu**: Right-click file operations

### 6. Native macOS Features
- **Dark Mode**: Automatic system theme support
- **Native Shortcuts**: Standard macOS keyboard shortcuts
- **Window Management**: Native window controls
- **Menu Bar**: Full menu bar integration
- **System Notifications**: Native alerts

## 🔌 API Endpoints

### Health & Status
- `GET /health` - Health check

### File Operations
- `POST /api/files/list` - List directory contents
- `POST /api/files/read` - Read file content
- `POST /api/files/write` - Write file content
- `POST /api/files/delete` - Delete file/directory

### Code Operations
- `POST /api/code/analyze` - Analyze code structure
- `POST /api/code/format` - Format code
- `POST /api/code/highlight` - Get syntax highlighting tokens

### AI Operations
- `POST /api/ai/refactor` - Refactor code with AI
- `POST /api/ai/explain` - Explain code with AI
- `POST /api/ai/complete` - Complete code with AI
- `GET /api/ai/models` - List available AI models

### Git Operations
- `POST /api/git/status` - Get repository status
- `POST /api/git/commit` - Create commit
- `POST /api/git/push` - Push to remote
- `POST /api/git/pull` - Pull from remote
- `POST /api/git/log` - Get commit history
- `POST /api/git/diff` - Get file differences

### Code Execution
- `POST /api/run/execute` - Execute code
- `POST /api/run/stop` - Stop execution

## 🎨 Design Principles

1. **Native First**: Leverage macOS native APIs for best performance and UX
2. **Safety**: Use Rust for memory safety and thread safety
3. **Performance**: Async operations for responsive UI
4. **Simplicity**: Clean, intuitive interface
5. **Extensibility**: Modular architecture for future features
6. **AI-Powered**: Seamless AI integration without disrupting workflow

## 🔐 Security Considerations

- **API Keys**: Stored in environment variables, never in code
- **Sandboxing**: Code execution in isolated processes
- **Input Validation**: All user inputs validated on backend
- **HTTPS**: All AI API calls over HTTPS
- **Error Sanitization**: No sensitive data in error messages

## 📊 Performance Metrics

- **Backend Startup**: < 500ms
- **File Load**: < 100ms for files under 1MB
- **Code Execution**: Near-native performance
- **AI Response**: 2-5 seconds (provider-dependent)
- **Syntax Highlighting**: < 50ms for 1000 lines
- **Git Operations**: < 200ms for status check

## 🛣️ Development Roadmap

### Phase 1 (Current) - Core Functionality ✅
- [x] File operations (open, save, edit)
- [x] Multi-tab interface
- [x] Basic code editing
- [x] Console output
- [x] Rust backend with REST API

### Phase 2 - AI & Advanced Features ✅
- [x] AI integration (Gemini, OpenAI, Claude)
- [x] Code refactoring with AI
- [x] Code explanation
- [x] Syntax highlighting
- [x] Code analysis

### Phase 3 - Git Integration ✅
- [x] Git status view
- [x] Commit functionality
- [x] Push/Pull operations
- [x] Commit history
- [x] Branch information

### Phase 4 - Polish & Optimization 🚧
- [ ] LSP (Language Server Protocol) support
- [ ] Advanced syntax highlighting themes
- [ ] Plugin system
- [ ] Custom keybindings
- [ ] Snippet support

### Phase 5 - Advanced Features 📋
- [ ] Debugger integration
- [ ] Collaborative editing
- [ ] Cloud synchronization
- [ ] Mobile companion app
- [ ] Extensions marketplace

## 🧪 Testing Strategy

### Backend Tests
- Unit tests for each module
- Integration tests for API endpoints
- Performance benchmarks
- Error handling tests

### Frontend Tests
- UI tests with XCTest
- Unit tests for business logic
- Integration tests with backend
- Accessibility tests

## 📦 Deployment

### Backend
- Compile to single binary
- Docker container support
- systemd service for Linux
- launchd service for macOS

### Frontend
- Xcode Archive for distribution
- Mac App Store compatible
- Notarization support
- Auto-update mechanism (planned)

## 🤝 Contributing

We welcome contributions! Areas for contribution:
- Language support (new languages)
- AI providers (new providers)
- Themes and UI improvements
- Performance optimizations
- Bug fixes and testing
- Documentation improvements

## 📄 License

Elastic License v2 (ELv2) & BSL - See LICENSE and README.md for details

## 👥 Creator & Maintainer

**Dotmini Company Limited (บริษัท ดอทมินิ จำกัด)**
- Founder & CEO: Tirawat Nantamas (นายถิรวัฒน์ นันตมาศ)
- Organization: Dotmini Company Limited
- GitHub: [Dotmini](https://github.com/Dotmini)

## 🙏 Acknowledgments

- **Rust Community**: For amazing libraries and tools
- **Swift Community**: For SwiftUI, AppKit, and Metal
- **AI Providers**: Google (Gemini), Anthropic (Claude), OpenAI, DeepSeek, xAI
- **Open Source**: All the amazing open source projects we build upon

## 📞 Support & Resources

- **Documentation**: README.md for detailed docs
- **Build Guide**: BUILDING.md for setup instructions
- **Issues**: GitHub Issues for bug reports

## 📈 Project Status

**Current Version**: 2.0.1
**Status**: Active Development
**Stability**: Stable Workstation

## 🎯 Project Goals

1. **Performance**: Native macOS speed, instant launch, Metal GPU text rendering
2. **Autonomous AI**: Formal implementation planning with human-in-the-loop safety gate
3. **Simulators & Streaming**: Live iOS & Android device mirroring inside editor
4. **Developer Studios**: Built-in Database, API, and CI/CD testing workbench
5. **No Electron**: 100% native SwiftUI, AppKit, Metal, and Rust

---

**Maintained by**: Dotmini Company Limited (Tirawat Nantamas)

Made with ❤️ by Dotmini Company Limited