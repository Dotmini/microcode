//
//  EmbeddedProjectWizard.swift
//  MicroCode
//
//  Created by SPU AI CLUB - Dotmini Software
//

import SwiftUI

struct EmbeddedProjectWizard: View {
    @Binding var isPresented: Bool
    
    @State private var projectName: String = "MyEmbeddedApp"
    @State private var selectedBoard: String = "ESP32"
    @State private var selectedFramework: String = "Arduino"
    
    let boards = ["ESP32-S3", "ESP32-C3", "ESP32 DevKit V1", "Arduino Uno R4", "STM32F4 Discovery", "Raspberry Pi Pico W"]
    let frameworks = ["Arduino", "ESP-IDF v5.1", "Zephyr RTOS", "MicroPython", "Rust (std)", "Rust (no_std)"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create New Project")
                        .font(.headline)
                    Text("Configure your embedded system environment")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "cpu")
                    .font(.system(size: 30))
                    .foregroundColor(.orange.opacity(0.8))
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Form
            ScrollView {
                VStack(spacing: 20) {
                    // Project Name
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Project Name", systemImage: "pencil.and.outline")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                        
                        TextField("Enter project name", text: $projectName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(size: 14))
                    }
                    
                    // Hardware Selection
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Target Board", systemImage: "memorychip")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $selectedBoard) {
                                ForEach(boards, id: \.self) { board in
                                    Text(board)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Framework", systemImage: "swift") // Using generic code icon
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $selectedFramework) {
                                ForEach(frameworks, id: \.self) { fw in
                                    Text(fw)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                    
                    // Info Card
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("MicroCode will generate the necessary build configuration (CMakeLists.txt / platformio.ini) automatically.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                }
                .padding(24)
            }
            .frame(width: 500, height: 320)
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button(action: { createProject() }) {
                    Text("Create Project")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(width: 140)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
    
    func createProject() {
        print("Creating \(projectName) for \(selectedBoard) with \(selectedFramework)")
        isPresented = false
    }
}
