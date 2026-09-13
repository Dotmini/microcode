// /Users/dotmini/Documents/SX/codetunner-native/MicroCode/Views/AI/ACPPermissionView.swift
import SwiftUI

struct ACPPermissionView: View {
    let filePath: String
    let command: String?
    let diffAdded: [String]
    let diffRemoved: [String]
    let onApprove: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text("Permission Required")
                    .font(.headline)
            }
            
            if let cmd = command {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Command Execution")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(cmd)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("File Modification: \(filePath)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(diffRemoved, id: \.self) { line in
                                Text("- " + line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 4)
                                    .background(Color.red.opacity(0.1))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(diffAdded, id: \.self) { line in
                                Text("+ " + line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 4)
                                    .background(Color.green.opacity(0.1))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            
            HStack(spacing: 16) {
                Button(action: onReject) {
                    Text("Reject")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .buttonStyle(.bordered)
                .tint(.red)
                
                Button(action: onApprove) {
                    Text("Approve")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
        .frame(width: 500)
    }
}