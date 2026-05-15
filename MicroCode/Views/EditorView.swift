import SwiftUI

struct EditorView: View {
    @State private var text: String = """
    fn main() {
        print("Hello from Ardium!");
    }
    """
    @State private var output: String = "Ready to run..."
    @State private var isRunning: Bool = false
    @State private var selectedTab: Int = 0
    
    // Use the Runner Engine
    private let runner = ArdiumRunner()
    
    var body: some View {
        HSplitView {
            // Left: Code Editor
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Text("StartUp.ar")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Run Button
                    Button(action: runCode) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("Run")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isRunning ? Color.gray : Color.green)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Editor Area (Reusing existing Syntax component)
                // Editor Area (Authentic IDE Core)
                AuthenticEditor(
                    text: $text,
                    language: "ardium"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 300)
            
            // Right: Console Output
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Picker("", selection: $selectedTab) {
                        Text("Output").tag(0)
                        Text("Terminal").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .labelsHidden()
                    
                    Spacer()
                    // Terminal controls (e.g. Split, Kill) could go here
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                if selectedTab == 0 {
                    // Fast Log Console (AppKit)
                    AuthenticLogConsole(text: $output, isReadOnly: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Authentic Native Terminal
                    AuthenticTerminal()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 200)
        }
    }
    
    private func runCode() {
        guard !isRunning else { return }
        isRunning = true
        output = "Compiling & Running...\n"
        
        Task {
            var buffer = ""
            var lastUpdate = Date()
            
            for await line in runner.run(code: text) {
                buffer += line + "\n"
                
                // Update UI visually instantly (5ms buffer to prevent single-char locking)
                if -lastUpdate.timeIntervalSinceNow > 0.005 {
                    let chunk = buffer
                    buffer = ""
                    lastUpdate = Date()
                    await MainActor.run {
                        output += chunk
                    }
                }
            }
            
            // Flush remaining
            if !buffer.isEmpty {
                let chunk = buffer
                await MainActor.run {
                    output += chunk
                }
            }
            
            await MainActor.run {
                isRunning = false
            }
        }
    }
}
