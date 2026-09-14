# Agent Development Guide for MicroCode

## Project Overview
MicroCode is a native macOS code editor and AI agent workstation with an integrated backend. The project consists of:
- **Frontend**: Native macOS application written in Swift (SwiftUI + AppKit) with Metal-accelerated rendering and SwiftPM integration.
- **Backend**: Rust server (Axum + Tokio) and FFI static library providing multi-provider AI integration, autonomous agent tool calling, and Tree-sitter indexing.

## Key Architecture Points

### Frontend (Swift/SwiftUI + AppKit)
- Located in `MicroCode/` directory
- Uses SwiftUI for declarative UI and AppKit for native high-performance text view
- Objective-C++ bridging layers in `MicroCodeSupport/` and `MicroCodeKernel/`
- Multi-tab interface for editing files
- Autonomous AI loop, interactive implementation plans, and terminal harness
- Git integration UI

### Backend (Rust)
- Located in `backend/` and `microcode_core/` directories
- Uses Axum web framework and C ABI static libraries
- Provides REST API and WebSocket endpoints
- Integrates with multiple AI providers (Gemini, Claude, OpenAI, DeepSeek, Grok, Qwen, GLM)
- Handles autonomous agent tool execution in workspace-sandboxed environments
- Git operations support

## Development Commands

### Building the Project
```bash
# Build both Rust backend and Swift frontend into MicroCode.app
./build.sh

# Fast incremental build and deployment to ~/Applications/MicroCode.app
./build_dev.sh

# Build frontend only (if Rust static libraries are already built)
./build.sh --frontend-only

# Build backend only
./build.sh --backend-only
```

### Running the Application
```bash
# Run the built application
open /Applications/MicroCode.app
# Or if built to default build root:
open .codetuner-build/apps/MicroCode.app
```

## Key Files and Their Locations

### Configuration
- `backend/.env` - Environment variables for API keys and settings
- `MicroCode/Config.swift` - Frontend configuration

### Core Models
- `backend/src/models.rs` - Backend data structures
- `MicroCode/Models/AppState.swift` - Frontend state management
- `MicroCode/Models/ImplementationPlanModels.swift` - Plan, approval, and execution tracking

### API Endpoints & Agent Engine
- `backend/src/main.rs` - Main routing and server setup
- `backend/src/agent.rs` - AI agent with autonomous tool execution
- `backend/src/ai.rs` - Multi-provider AI streaming integrations
- `backend/src/git.rs` - Git operations
- `backend/src/runner.rs` - Code execution

### UI Components
- `MicroCode/Views/ContentView.swift` - Main UI layout
- `MicroCode/Views/Editor/CodeEditorView.swift` - Code editing interface
- `MicroCode/Views/AI/AgentPlanningView.swift` - Interactive plan & tool approval interface
- `MicroCode/Views/Git/GitView.swift` - Git operations UI

## Environment Setup
1. Copy `backend/.env.example` to `backend/.env`
2. Add your API keys for Gemini, OpenAI, Claude, or local Ollama
3. Install Rust toolchain: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
4. Ensure Xcode command line tools are installed: `xcode-select --install`
5. Run `./build.sh` to compile both backend and frontend

## Common Development Tasks

### Adding a New AI Provider
1. Update `backend/src/ai.rs` with new provider implementation
2. Add provider enum variant in `backend/src/models.rs`
3. Update UI in `MicroCode/Views/Settings/AIProviderSettingsView.swift`

### Adding Support for a New Language
1. Add syntax highlighting rules in `MicroCode/SyntaxEngine/`
2. Update code runner in `backend/src/runner.rs`
3. Add language icon to frontend resources

### Adding New Git Operations
1. Implement backend logic in `backend/src/git.rs`
2. Add API endpoints in `backend/src/main.rs`
3. Create UI components in `MicroCode/Views/Git/`

## Testing
- Backend tests: `cd backend && cargo test`
- Frontend tests: `swift test`
- Integration tests: Test frontend against running backend via `./build_dev.sh`

## Common Issues
- Backend not starting: Check if port 3000 is available
- AI requests failing: Verify API keys in `.env` file
- Git operations not working: Ensure git is initialized in the project directory
- Code execution failing: Check if the language runtime is installed

## Debugging Tips
- Backend logs: Check console output for Rust server
- Frontend logs: Use Xcode console for SwiftUI logs
- API issues: Check Network tab in Xcode or use curl to test endpoints
- Git issues: Run git commands manually to verify repository state

## Performance Considerations
- Backend uses async/await for concurrent operations
- Frontend uses Combine for reactive updates
- Large files are streamed to avoid memory issues
- AI requests have timeout configurations

## Security Notes
- API keys are loaded from environment variables only
- Code execution is sandboxed
- File operations are restricted to project directory
- No sensitive data is logged

## Contributing
When making changes:
1. Create a feature branch
2. Update tests for new functionality
3. Ensure backward compatibility for API changes
4. Update documentation as needed
5. Test both frontend and backend integration