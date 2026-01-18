//
//  EmbeddedStudioView.swift
//  MicroCode
//
//  Created by SPU AI CLUB - Dotmini Software
//

import SwiftUI
import CodeTunnerSupport

struct EmbeddedStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    // Studio State
    @State private var selectedDevice: String?
    @State private var terminalOutput: String = ""
    @State private var isBuilding: Bool = false
    @State private var showWizard: Bool = false
    @State private var selectedTool: Int = 0 
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Sidebar (Glassmorphic)
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                    Text("Embedded Studio")
                        .font(.system(size: 14, weight: .bold))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        
                        // Device Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CONNECTED DEVICES")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                            
                            // Mock Device Card
                            DeviceCard(name: "ESP32-S3", port: "COM3 / tty.usbserial", isConnected: true) {
                                selectedDevice = "ESP32-S3"
                            }
                        }
                        .padding(.top, 10)
                        
                        Divider()
                        
                        // Tools Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TOOLS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                            
                            StudioToolButton(title: "Serial Monitor", icon: "chart.bar.doc.horizontal", isSelected: selectedTool == 0) { selectedTool = 0 }
                            StudioToolButton(title: "Crash Decoder", icon: "ladybug", isSelected: selectedTool == 1) { selectedTool = 1 }
                            StudioToolButton(title: "Partitions", icon: "square.split.3x1", isSelected: selectedTool == 2) { selectedTool = 2 }
                        }
                    }
                    .padding(10)
                }
            }
            .frame(width: 260)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
            .background(.ultraThinMaterial)
            
            Divider()
            
            // MARK: - Main Content Area
            VStack(spacing: 0) {
                // Modern Toolbar
                HStack(spacing: 12) {
                    Button(action: { showWizard = true }) {
                        Label("New Project", systemImage: "plus")
                    }
                    .buttonStyle(StudioButtonStyle(color: .blue))
                    
                    Divider().frame(height: 20)
                    
                    Button(action: { buildProject() }) {
                        if isBuilding {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Build", systemImage: "hammer.fill")
                        }
                    }
                    .buttonStyle(StudioButtonStyle(color: .secondary))
                    .disabled(isBuilding)
                    
                    Button(action: { flashProject() }) {
                        Label("Flash", systemImage: "bolt.fill")
                    }
                    .buttonStyle(StudioButtonStyle(color: .orange))
                    .disabled(isBuilding || selectedDevice == nil)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
                .padding(12)
                .background(.ultraThinMaterial)
                
                Divider()
                
                // Workspace
                ZStack {
                    Color(nsColor: .textBackgroundColor).opacity(0.5)
                    
                    if terminalOutput.isEmpty {
                        VStack(spacing: 24) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.blue.opacity(0.2), .purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 120, height: 120)
                                
                                Image(systemName: "cpu")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(spacing: 8) {
                                Text("Ready to Code")
                                    .font(.title2.bold())
                                    .foregroundColor(.primary)
                                
                                Text("Select a device or create a new project to get started.")
                                    .foregroundColor(.secondary)
                            }
                            
                            Button("Create Embedded Project") {
                                showWizard = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    } else {
                        ScrollView {
                            Text(terminalOutput)
                                .font(.monospaced(.body)())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showWizard) {
            EmbeddedProjectWizard(isPresented: $showWizard)
        }
    }
    
    // Actions
    func buildProject() {
        withAnimation { isBuilding = true }
        terminalOutput += "\n[MicroCode] Starting Build...\n"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                terminalOutput += "[MicroCode] Build Successful! (Artifact: firmware.bin)\n"
                isBuilding = false
            }
        }
    }
    
    func flashProject() {
        terminalOutput += "\n[MicroCode] Flashing to device (COM3)...\n"
    }
}

// MARK: - UI Components

struct DeviceCard: View {
    let name: String
    let port: String
    let isConnected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isConnected ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "cable.connector")
                        .font(.system(size: 14))
                        .foregroundColor(isConnected ? .green : .gray)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text(port)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct StudioToolButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct StudioButtonStyle: ButtonStyle {
    var color: Color = .primary
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(color == .secondary ? Color(nsColor: .controlBackgroundColor) : color.opacity(0.1))
            .foregroundColor(color == .secondary ? .primary : color)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}
