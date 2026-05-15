//
//  EnvEditorView.swift
//  MicroCode
//
//  Reusable Environment Variable Editor
//

import SwiftUI

struct EnvVariable: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
}

struct EnvEditorView: View {
    @Binding var envVariables: [EnvVariable]
    @Binding var statusMessage: String
    
    @State private var newKey: String = ""
    @State private var newValue: String = ""
    
    var onSave: () -> Void
    var onReload: () -> Void
    
    var body: some View {
        GroupBox(label: Text("Environment Variables (.env)")) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Key").frame(width: 150, alignment: .leading)
                    Text("Value").frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                
                // List
                List {
                    ForEach($envVariables) { $env in
                        HStack {
                            TextField("Key", text: $env.key)
                                .textFieldStyle(.plain)
                                .frame(width: 150)
                                .foregroundColor(.green)
                            
                            Divider()
                            
                            TextField("Value", text: $env.value)
                                .textFieldStyle(.plain)
                            
                            Button(action: { removeEnv(env) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(minHeight: 150)
                
                Divider()
                
                // Add New
                HStack {
                    TextField("NEW_KEY", text: $newKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    
                    TextField("Value", text: $newValue)
                        .textFieldStyle(.roundedBorder)
                    
                    Button(action: addEnv) {
                        Image(systemName: "plus")
                    }
                    .disabled(newKey.isEmpty)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.05))
            }
        }
        
        HStack {
            Button(action: onReload) {
                Label("Reload .env", systemImage: "arrow.clockwise")
            }
            
            Spacer()
            
            Text(statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(action: onSave) {
                Label("Save Changes", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 8)
    }
    
    private func addEnv() {
        guard !newKey.isEmpty else { return }
        envVariables.append(EnvVariable(key: newKey, value: newValue))
        newKey = ""
        newValue = ""
    }
    
    private func removeEnv(_ env: EnvVariable) {
        envVariables.removeAll { $0.id == env.id }
    }
}
