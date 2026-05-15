//
//  DatabaseStudioView.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2024 AIPRENEUR. All rights reserved.
//

import SwiftUI

struct DatabaseStudioView: View {
    @StateObject private var dbService = DatabaseService.shared
    @Environment(\.dismiss) private var dismiss
    
    // Connection State
    @State private var selectedType: DatabaseType = .sqlite
    @State private var connectionString: String = ""
    @State private var connections: [SavedConnection] = [
        SavedConnection(name: "Local SQLite", icon: "cylinder.split.1x2", type: .sqlite, connectionString: "sqlite:./local.db"),
        SavedConnection(name: "Production Postgres", icon: "cylinder.split.1x2", type: .postgres, connectionString: "")
    ]
    @State private var selectedConnectionID: UUID?
    
    // Query State
    @State private var sqlQuery: String = "SELECT * FROM sqlite_master WHERE type='table';"
    @State private var queryResult: QueryResult?
    @State private var isExecuting = false
    @State private var executionError: String?
    
    var body: some View {
        HSplitView {
            // Sidebar: Connections
            VStack(spacing: 0) {
                sidebarHeader
                connectionList
                Divider()
                newConnectionForm
            }
            .frame(minWidth: 260, maxWidth: 300)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow).ignoresSafeArea())
            
            // Main Area: Query & Results
            VStack(spacing: 0) {
                if dbService.activeConnectionId != nil {
                    queryEditor
                    Divider()
                    resultsArea
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 900, minHeight: 600)
        // Auto-connect if selecting a simulated saved connection (Mock behavior for demo)
        .onChange(of: selectedConnectionID) { id in
            if let conn = connections.first(where: { $0.id == id }) {
                selectedType = conn.type
                connectionString = conn.connectionString
                // Auto-fill form
            }
        }
    }
    
    // MARK: - Sidebar Components
    
    private var sidebarHeader: some View {
        HStack {
            Image(systemName: "server.rack")
                .foregroundColor(.accentColor)
            Text("Connections")
                .font(.headline)
            Spacer()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    private var connectionList: some View {
        List(selection: $selectedConnectionID) {
            Section("Recent") {
                ForEach(connections) { conn in
                    HStack {
                        Image(systemName: conn.icon)
                            .foregroundColor(.secondary)
                        Text(conn.name)
                            .font(.subheadline)
                    }
                    .tag(conn.id)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.sidebar)
    }
    
    private var newConnectionForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Connection")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            Picker("Type", selection: $selectedType) {
                ForEach(DatabaseType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
            
            HStack {
                TextField("Connection String", text: $connectionString)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .placeholder(when: connectionString.isEmpty) {
                        Text(selectedType.placeholder).foregroundColor(.gray)
                    }
                
                if selectedType == .sqlite {
                    Button(action: selectSQLiteFile) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Select SQLite File")
                }
            }
            
            if let error = dbService.connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
            
            Button(action: {
                Task {
                    _ = await dbService.connect(type: selectedType, connectionString: connectionString)
                }
            }) {
                HStack {
                    if dbService.isConnecting {
                        ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
                    }
                    Text("Connect")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(connectionString.isEmpty || dbService.isConnecting)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Main Area Components
    
    private var queryEditor: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Label("SQL Query", systemImage: "terminal.fill")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: runQuery) {
                    Label("Run", systemImage: "play.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)
            
            // Editor
            TextEditor(text: $sqlQuery)
                .font(.system(.body, design: .monospaced))
                .padding(4)
                .frame(minHeight: 150)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(height: 200)
    }
    
    private var resultsArea: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Results")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                if let result = queryResult {
                    Text("\(result.rows.count) rows")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)
            
            if isExecuting {
                ProgressView("Executing Query...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = executionError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Query Error")
                        .font(.headline)
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = queryResult {
                DataGrid(result: result)
            } else {
                Text("Run a query to see results")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 120, height: 120)
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
            }
            
            VStack(spacing: 8) {
                Text("Connect to a Database")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                Text("Select a connection from the sidebar or create a new one to start writing queries.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func runQuery() {
        isExecuting = true
        executionError = nil
        queryResult = nil
        
        Task {
            do {
                let result = try await dbService.executeQuery(sqlQuery)
                await MainActor.run {
                    self.queryResult = result
                    self.isExecuting = false
                }
            } catch {
                await MainActor.run {
                    self.executionError = error.localizedDescription
                    self.isExecuting = false
                }
            }
        }
    }
    
    private func selectSQLiteFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select an existing SQLite database file"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                connectionString = "sqlite:\(url.path)"
            }
        }
    }
}

// MARK: - Supporting Views

struct SavedConnection: Identifiable {
    let id = UUID()
    let name: String
    let icon: String // SF Symbol
    let type: DatabaseType
    let connectionString: String
}

struct DataGrid: View {
    let result: QueryResult
    private let columnWidth: CGFloat = 150
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(spacing: 1) {
                        ForEach(result.columns, id: \.self) { col in
                            Text(col)
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .frame(width: columnWidth, alignment: .leading)
                                .padding(8)
                                .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
                        }
                    }
                    
                    // Rows
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<result.rows.count, id: \.self) { i in
                            let row = result.rows[i]
                            HStack(spacing: 1) {
                                ForEach(0..<row.count, id: \.self) { j in
                                    Text(row[j].description)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                        .frame(width: columnWidth, alignment: .leading)
                                        .padding(8)
                                        .background(i % 2 == 0 ? Color(nsColor: .controlBackgroundColor).opacity(0.3) : Color.clear)
                                }
                            }
                            Divider()
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
        }
    }
}

// Helper extension for placeholder
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}
