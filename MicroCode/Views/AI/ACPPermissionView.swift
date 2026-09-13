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
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(.white)
                Text("Permission Required")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            if let cmd = command {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Command Execution")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.white.opacity(0.8))
                    
                    Text(cmd)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("File Modification: \(filePath)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.white.opacity(0.8))
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(diffRemoved, id: \.self) { line in
                                Text("- " + line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(Color.white.opacity(0.6))
                                    .padding(.horizontal, 4)
                                    .background(Color.white.opacity(0.04))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(diffAdded, id: \.self) { line in
                                Text("+ " + line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .background(Color.white.opacity(0.08))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .background(Color.black)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
            }
            
            HStack(spacing: 16) {
                Button(action: onReject) {
                    Text("Reject")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .buttonStyle(.plain)
                
                Button(action: onApprove) {
                    Text("Approve")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 500)
        .background(Color.black)
    }
}