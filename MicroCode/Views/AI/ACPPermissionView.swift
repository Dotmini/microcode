// /Users/dotmini/Documents/SX/codetunner-native/MicroCode/Views/AI/ACPPermissionView.swift
import SwiftUI

struct ACPPermissionView: View {
    let filePath: String
    let command: String?
    let diffAdded: [String]
    let diffRemoved: [String]
    let onApprove: () -> Void
    let onReject: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(.accentColor)
                Text("Permission Required")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            if let cmd = command {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Command Execution")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Text(cmd)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("File Modification: \(filePath)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(diffRemoved, id: \.self) { line in
                                Text("- " + line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(Color.red.opacity(0.85))
                                    .padding(.horizontal, 4)
                                    .background(Color.red.opacity(0.08))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(diffAdded, id: \.self) { line in
                                Text("+ " + line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(Color.green.opacity(0.85))
                                    .padding(.horizontal, 4)
                                    .background(Color.green.opacity(0.08))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                }
            }
            
            HStack(spacing: 12) {
                Button(action: onReject) {
                    Text("Reject")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.red.opacity(0.2), lineWidth: 0.8)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .buttonStyle(.plain)
                
                Button(action: onApprove) {
                    Text("Approve")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 3, x: 0, y: 1)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 480)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.96) : Color(nsColor: .windowBackgroundColor))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }
}