//
//  NodeProjectManagerView.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2024 AIPRENEUR. All rights reserved.
//

import SwiftUI

struct NodeProjectManagerView: View {
    @EnvironmentObject var appState: AppState
    @State private var envVariables: [EnvVariable] = []
    @State private var selectedNodeVersion: String = "system"
    @State private var statusMessage: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Version Selector
            GroupBox(label: Text("Runtime Environment")) {
                HStack {
                    Text("Node Version:")
                    Picker("", selection: $selectedNodeVersion) {
                        Text("System Default").tag("system")
                        Text("Node v22 (Latest)").tag("v22")
                        Text("Node v20 (LTS)").tag("v20")
                        Text("Node v18").tag("v18")
                    }
                    .frame(width: 200)
                    
                    Spacer()
                }
                .padding(8)
            }
            
            // ENV Manager (Reusable)
            EnvEditorView(
                envVariables: $envVariables,
                statusMessage: $statusMessage,
                onSave: saveEnv,
                onReload: loadEnv
            )
        }
        .padding()
        .onAppear {
            loadEnv()
        }
    }
    
    private func loadEnv() {
        guard let folder = appState.workspaceFolder else { return }
        let envPath = folder.appendingPathComponent(".env")
        do {
            let content = try String(contentsOf: envPath, encoding: .utf8)
            envVariables = EnvUtils.parseEnv(content)
            statusMessage = "Loaded .env"
        } catch {
            statusMessage = "No .env found (created new)"
        }
    }
    
    private func saveEnv() {
        guard let folder = appState.workspaceFolder else { return }
        let envPath = folder.appendingPathComponent(".env")
        let content = EnvUtils.serializeEnv(envVariables)
        try? content.write(to: envPath, atomically: true, encoding: .utf8)
        statusMessage = "Saved .env"
    }
}
