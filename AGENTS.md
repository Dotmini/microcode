# Codex Development Guide for CodeTuner

## Project Overview
CodeTuner is a native macOS code editor with an AI-powered backend. The project consists of:
- **Frontend**: SwiftUI-based macOS application
- **Backend**: Rust-based web server providing AI integration and code execution capabilities

## Key Architecture Points

### Frontend (Swift/SwiftUI)
- Located in `CodeTuner/` directory
- Uses SwiftUI for declarative UI
- Native macOS UI with dark/light mode support
- Multi-tab interface for editing files
- Real-time console output
- Git integration UI

### Backend (Rust)
- Located in `backend/` directory
- Uses Axum web framework
- Provides REST API endpoints
- Integrates with multiple AI providers (Gemini, OpenAI, Codex)
- Handles code execution in isolated environments
- Git operations support

## Development Commands

### Building the Project
```bash
# Build both frontend and backend
./build.sh

# Or build separately
cd backend && cargo build --release
# Build frontend in Xcode
```

### Running the Application
```bash
# Start backend server (port 3000)
cd backend && cargo run

# Run frontend from Xcode
# Set backend URL in environment: API_URL=http://localhost:3000
```

## Key Files and Their Locations

### Configuration
- `backend/.env` - Environment variables for API keys and settings
- `CodeTuner/Config.swift` - Frontend configuration

### Core Models
- `backend/src/models.rs` - Backend data structures
- `CodeTuner/Models/AppState.swift` - Frontend state management

### API Endpoints
- `backend/src/main.rs` - Main routing and server setup
- `backend/src/git.rs` - Git operations
- `backend/src/runner.rs` - Code execution
- `backend/src/ai.rs` - AI provider integrations

### UI Components
- `CodeTuner/Views/ContentView.swift` - Main UI view
- `CodeTuner/Views/CodeEditorView.swift` - Code editing interface
- `CodeTuner/Views/GitView.swift` - Git operations UI

## Environment Setup
1. Copy `backend/.env.example` to `backend/.env`
2. Add your API keys for Gemini, OpenAI, or Codex
3. Install Rust dependencies with `cargo build`
4. Open `CodeTuner.xcodeproj` in Xcode
5. Run backend server, then frontend application

## Common Development Tasks

### Adding a New AI Provider
1. Update `backend/src/ai.rs` with new provider implementation
2. Add provider enum variant in `backend/src/models.rs`
3. Update UI in `CodeTuner/Views/AIView.swift`

### Adding Support for a New Language
1. Add syntax highlighting rules in `backend/src/code/highlighter.rs`
2. Update code runner in `backend/src/runner.rs`
3. Add language icon to frontend resources

### Adding New Git Operations
1. Implement backend logic in `backend/src/git.rs`
2. Add API endpoints in `backend/src/main.rs`
3. Create UI components in `CodeTuner/Views/GitView.swift`

## Testing
- Backend tests: `cd backend && cargo test`
- Frontend tests: Run through Xcode Test Navigator
- Integration tests: Test frontend against running backend

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