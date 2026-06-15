//
//  ProjectToolbar.swift
//  MicroCode
//
//  Universal Build/Run/Debug Toolbar
//

import SwiftUI

struct ProjectToolbar: View {
    @ObservedObject var projectManager = ProjectManager.shared
    @EnvironmentObject var appState: AppState
    
    @State private var showingOutput: Bool = false
    
    var body: some View {
        let currentType = appState.currentProjectType
        
        HStack(spacing: 12) {
            // Project Type Indicator
            if let folder = appState.workspaceFolder {
                HStack(spacing: 6) {
                    Image(systemName: currentType.icon)
                        .foregroundColor(projectColor(currentType))
                    Text(currentType.rawValue)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(projectColor(currentType).opacity(0.15))
                .cornerRadius(6)
                
                Divider()
                    .frame(height: 20)
                
                // Configuration Picker
                Picker("", selection: $projectManager.buildConfiguration) {
                    Text("Debug").tag(BuildConfiguration.debug)
                    Text("Release").tag(BuildConfiguration.release)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                
                Divider()
                    .frame(height: 20)
                
                // Action Buttons
                Group {
                    ActionButton(action: .build, projectPath: folder)
                    ActionButton(action: .run, projectPath: folder)
                    ActionButton(action: .debug, projectPath: folder)
                    ActionButton(action: .test, projectPath: folder)
                    ActionButton(action: .clean, projectPath: folder)
                }
                
                if projectManager.isRunning {
                    Button(action: { projectManager.stopCurrentProcess() }) {
                        Image(systemName: "stop.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop")
                    
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            Spacer()
            
            // Output Toggle
            Button(action: { showingOutput.toggle() }) {
                Image(systemName: "terminal")
                    .foregroundColor(showingOutput ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle Output")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showingOutput) {
            ProjectOutputView()
                .environmentObject(appState)
        }
    }

    private func projectColor(_ type: ProjectType) -> Color {
        switch type {
        case .nodejs: return .green
        case .python: return .blue
        case .rust: return .orange
        case .dotnet: return .purple
        case .unknown: return .secondary
        default: return .secondary
        }
    }
}

struct ActionButton: View {
    let action: ProjectAction
    let projectPath: URL
    @ObservedObject var projectManager = ProjectManager.shared
    
    var body: some View {
        Button(action: executeAction) {
            Image(systemName: action.icon)
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundColor(projectManager.isRunning ? .secondary : .primary)
        .disabled(projectManager.isRunning)
        .help(action.rawValue)
    }
    
    func executeAction() {
        projectManager.execute(action: action, projectPath: projectPath) { success, output in
            print("[\(action.rawValue)] \(success ? "Success" : "Failed")")
        }
    }
}

struct ProjectOutputView: View {
    @ObservedObject var projectManager = ProjectManager.shared
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0 // 0: Report, 1: Raw Log
    
    var body: some View {
        let isXcode = appState.currentProjectType == .xcode
        
        VStack(spacing: 0) {
            // Header
            HStack {
                if isXcode {
                    Picker("", selection: $selectedTab) {
                        Text("Report").tag(0)
                        Text("Raw Log").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                } else {
                    Text("Build Output")
                        .font(.headline)
                }
                
                Spacer()
                
                if projectManager.isRunning {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    Spacer().frame(width: 8)
                    
                    Button("Stop") {
                        projectManager.stopCurrentProcess()
                    }
                    .buttonStyle(.bordered)
                }
                
                Button("Clear") {
                    projectManager.output = ""
                    if isXcode {
                        projectManager.buildParser.clear()
                    }
                }
                .buttonStyle(.borderless)
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            if isXcode && selectedTab == 0 {
                BuildReportView(parser: projectManager.buildParser, isEmbedded: true)
            } else {
                // Output
                ScrollView {
                    Text(projectManager.output)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .frame(width: 750, height: 500)
    }
}
