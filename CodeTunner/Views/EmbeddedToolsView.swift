//
//  EmbeddedToolsView.swift
//  CodeTunner
//
//  Created by SPU AI CLUB - Dotmini Software
//

import SwiftUI
import CodeTunnerSupport

struct EmbeddedToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @State private var logs: String = ""
    @State private var crashInput: String = ""
    @State private var crashResult: String = ""
    @State private var isMonitoring: Bool = false
    
    // Timer for simulating log updates/checking status
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Embedded Tools", systemImage: "cpu.fill")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            TabView {
                // Tab 1: Intelligent Board Detection
                VStack(spacing: 20) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Intelligent Board Detection")
                                .font(.title3.bold())
                            Text("Automatically detect ESP32 and other boards via USB.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("Monitor USB", isOn: $isMonitoring)
                            .toggleStyle(.switch)
                            .onChange(of: isMonitoring) { newValue in
                                if newValue {
                                    startMonitoring()
                                } else {
                                    stopMonitoring()
                                }
                            }
                    }
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.1))
                    .cornerRadius(8)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Connected Devices:")
                                .font(.subheadline.bold())
                            
                            // Mock Data or Real Status
                            if isMonitoring {
                                Label("Monitoring active...", systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Text("Monitoring stopped.")
                                    .italic()
                                    .foregroundColor(.secondary)
                            }
                            
                            // This would be populated by actual events in a real binding
                            Text(logs)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                }
                .padding()
                .tabItem {
                    Label("Devices", systemImage: "cable.connector")
                }
                
                // Tab 2: Ghost Crash Decoder
                VStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("Ghost Crash Decoder")
                            .font(.title3.bold())
                        Text("Paste 'Guru Meditation Error' logs here to decode.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    TextEditor(text: $crashInput)
                        .font(.system(.body, design: .monospaced))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        .frame(minHeight: 100)
                    
                    Button("Decode Crash") {
                        decodeCrash()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if !crashResult.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Result:")
                                .font(.caption.bold())
                            Text(crashResult)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .transition(.slide)
                    }
                    
                    Spacer()
                }
                .padding()
                .tabItem {
                    Label("Crash Decoder", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .frame(width: 500, height: 400)
    }
    
    // Placeholder actions calling into the C/Rust bridge conceptually
    // In a real implementation, we'd bind this to the C++ singleton logic
    func startMonitoring() {
        logs += "[System] USB Monitoring Started...\n"
        // Actual call: AuthenticsUSBServices.shared.startMonitoring()
    }
    
    func stopMonitoring() {
        logs += "[System] USB Monitoring Stopped.\n"
    }
    
    func decodeCrash() {
        // Simple mock of the Rust decoder integration for the UI prototype
        if crashInput.contains("Guru Meditation Error") {
            // In real app: call bridge function
            crashResult = """
            decoded: Exception: LoadProhibited
            PC: 0x400d1234
            (Simulated Decode)
            """
        } else {
            crashResult = "No valid crash signature found."
        }
    }
}
