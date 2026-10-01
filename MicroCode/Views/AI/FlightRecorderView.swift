import SwiftUI

// MARK: - Flight Recorder View (P2 Audit Trail)
// Apple HIG Monochrome — Deep Slate theme

struct FlightRecorderView: View {
    @StateObject private var recorder = FlightRecorder.shared
    @State private var filterAction: AuditAction? = nil
    @State private var filterActor: AuditActor? = nil
    @State private var searchText: String = ""
    @State private var showExportMenu = false
    
    private var filteredEntries: [AuditLogEntry] {
        var result = recorder.entries
        
        if let action = filterAction {
            result = result.filter { $0.action == action }
        }
        if let actor = filterActor {
            result = result.filter { $0.actor == actor }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.details.lowercased().contains(q) ||
                $0.target.path.lowercased().contains(q) ||
                $0.action.rawValue.lowercased().contains(q)
            }
        }
        
        return result.reversed() // Newest first
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Flight Recorder")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(recorder.entries.count) events · Session \(String(recorder.currentSessionId.prefix(8)))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Chain integrity badge
                let chainResult = recorder.verifyChain()
                HStack(spacing: 4) {
                    Image(systemName: chainResult.isValid ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 10))
                    Text(chainResult.isValid ? "Chain Valid" : "Chain Broken")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(chainResult.isValid ? .green : .red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((chainResult.isValid ? Color.green : Color.red).opacity(0.1))
                .cornerRadius(4)
                
                // Controls
                Toggle(isOn: $recorder.piiSanitizationEnabled) {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 9))
                        Text("PII")
                            .font(.system(size: 10))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                
                Toggle(isOn: $recorder.recordingEnabled) {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(recorder.recordingEnabled ? Color.red : Color.gray)
                            .frame(width: 6, height: 6)
                        Text("REC")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                
                Menu {
                    Button("Export JSON (SOC2)") {
                        let json = recorder.exportJSON()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(json, forType: .string)
                    }
                    Button("Export CSV") {
                        let csv = recorder.exportCSV()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(csv, forType: .string)
                    }
                    Divider()
                    Button("New Session") {
                        recorder.startNewSession()
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.03))
            
            Divider()
            
            // Filter bar
            HStack(spacing: 8) {
                // Search
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("Search events…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(5)
                .frame(maxWidth: 200)
                
                // Actor filter
                Menu {
                    Button("All Actors") { filterActor = nil }
                    Divider()
                    ForEach([AuditActor.user, .agent, .system, .tool], id: \.rawValue) { actor in
                        Button(actor.rawValue.capitalized) { filterActor = actor }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "person")
                        Text(filterActor?.rawValue.capitalized ?? "All Actors")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(filterActor != nil ? .primary : .secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 100)
                
                // Action filter
                Menu {
                    Button("All Actions") { filterAction = nil }
                    Divider()
                    Section("Files") {
                        Button("file.create") { filterAction = .fileCreate }
                        Button("file.modify") { filterAction = .fileModify }
                        Button("file.delete") { filterAction = .fileDelete }
                    }
                    Section("Agent") {
                        Button("agent.tool_call") { filterAction = .agentToolCall }
                        Button("agent.approval") { filterAction = .agentApprovalGranted }
                    }
                    Section("Changes") {
                        Button("change.proposed") { filterAction = .changeProposed }
                        Button("change.accepted") { filterAction = .changeAccepted }
                        Button("change.rejected") { filterAction = .changeRejected }
                    }
                    Section("Commands") {
                        Button("command.execute") { filterAction = .commandExecute }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(filterAction?.rawValue ?? "All Actions")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(filterAction != nil ? .primary : .secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 130)
                
                Spacer()
                
                // Stats
                HStack(spacing: 12) {
                    statBadge(label: "Files", count: recorder.totalFileChanges, color: .blue)
                    statBadge(label: "Tools", count: recorder.totalToolCalls, color: .orange)
                    statBadge(label: "Cmds", count: recorder.totalCommands, color: .purple)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.02))
            
            Divider()
            
            // Event list
            if filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("No audit events recorded")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("Events will appear as the AI agent operates")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            AuditEventRow(entry: entry)
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
    }
    
    private func statBadge(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Audit Event Row

private struct AuditEventRow: View {
    let entry: AuditLogEntry
    @State private var isExpanded = false
    
    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Time
                Text(timeFormatter.string(from: entry.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 55, alignment: .leading)
                
                // Actor badge
                Text(entry.actor.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(actorColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(actorColor.opacity(0.1))
                    .cornerRadius(3)
                    .frame(width: 55)
                
                // Action
                Text(entry.action.rawValue)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(actionColor)
                    .frame(width: 130, alignment: .leading)
                
                // Target path (truncated)
                Text(URL(fileURLWithPath: entry.target.path).lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                // Hash (short)
                Text(String(entry.entryHash.prefix(8)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                
                // Expand
                Button(action: { withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Path:")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(entry.target.path)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    }
                    
                    if !entry.details.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Text("Details:")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(entry.details)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(4)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Text("Hash: \(entry.entryHash)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("Prev: \(String(entry.previousHash.prefix(16)))")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .padding(.leading, 55 + 8) // Align with action column
                .background(Color.primary.opacity(0.02))
            }
        }
        .background(isExpanded ? Color.primary.opacity(0.015) : Color.clear)
    }
    
    private var actorColor: Color {
        switch entry.actor {
        case .user: return .blue
        case .agent: return .orange
        case .subAgent: return .purple
        case .system: return .gray
        case .tool: return .green
        }
    }
    
    private var actionColor: Color {
        let action = entry.action.rawValue
        if action.hasPrefix("file.") { return .blue }
        if action.hasPrefix("agent.") { return .orange }
        if action.hasPrefix("change.") { return .green }
        if action.hasPrefix("command.") { return .purple }
        if action.hasPrefix("git.") { return .red }
        if action.hasPrefix("session.") { return .gray }
        return .primary
    }
}
