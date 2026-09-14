import SwiftUI

struct ToolApprovalView: View {
    @ObservedObject var manager: ToolApprovalManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded: Bool = false
    
    var body: some View {
        if let request = manager.pendingRequest {
            VStack(alignment: .leading, spacing: 7) {
                // Header row: Shield Icon, Title, Inline Tool Pill, Spacer, Risk Badge, Expand Toggle
                HStack(spacing: 6) {
                    Image(systemName: request.riskLevel == .critical || request.riskLevel == .dangerous ? "exclamationmark.shield.fill" : "shield.lefthalf.filled")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(riskColor(for: request.riskLevel))
                    
                    Text("Permission Required")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    // Tool Name Pill
                    HStack(spacing: 4) {
                        Image(systemName: "terminal")
                            .font(.system(size: 8.5))
                        Text(request.toolName)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(4)
                    
                    Spacer()
                    
                    // Risk Badge
                    Text(request.riskLevel.rawValue.uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(riskColor(for: request.riskLevel).opacity(0.12))
                        .foregroundColor(riskColor(for: request.riskLevel))
                        .cornerRadius(3.5)
                    
                    if !request.arguments.isEmpty {
                        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(2)
                        }
                        .buttonStyle(.plain)
                        .help(isExpanded ? "Collapse parameters" : "Expand all parameters")
                    }
                }
                
                // Description (shown if expanded or if arguments are empty)
                if !request.description.isEmpty && (request.arguments.isEmpty || isExpanded) {
                    Text(request.description)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary.opacity(0.85))
                        .lineLimit(isExpanded ? nil : 1)
                }
                
                // Compact Arguments View
                if !request.arguments.isEmpty {
                    let sortedKeys = Array(request.arguments.keys.sorted())
                    let displayKeys = isExpanded ? sortedKeys : Array(sortedKeys.prefix(2))
                    
                    VStack(alignment: .leading, spacing: 2.5) {
                        ForEach(displayKeys, id: \.self) { key in
                            HStack(alignment: .top, spacing: 4) {
                                Text("\(key):")
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.7))
                                Text(request.arguments[key] ?? "")
                                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                                    .foregroundColor(.primary.opacity(0.9))
                                    .lineLimit(isExpanded ? nil : 1)
                                    .truncationMode(.middle)
                            }
                        }
                        if !isExpanded && sortedKeys.count > 2 {
                            Text("+\(sortedKeys.count - 2) more parameter(s)...")
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(5)
                }
                
                // Action Buttons: Reject, Always Allow, Approve (sleek, compact native buttons)
                HStack(spacing: 8) {
                    // Reject Button
                    Button(action: {
                        manager.reject()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("Reject")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundColor(.red.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.red.opacity(0.2), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Always Allow Button
                    Button(action: {
                        manager.alwaysAllow(toolName: request.toolName)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.open")
                                .font(.system(size: 8.5))
                            Text("Always Allow")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Approve Button (Native Accent Button)
                    Button(action: {
                        manager.approve()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("Approve")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .cornerRadius(5)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.96) : Color(nsColor: .windowBackgroundColor))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    private func riskColor(for level: ToolRiskLevel) -> Color {
        switch level {
        case .safe: return .green
        case .moderate: return .yellow
        case .dangerous: return .orange
        case .critical: return .red
        }
    }
}

struct ToolApprovalModePickerView: View {
    @ObservedObject var manager: ToolApprovalManager
    
    var body: some View {
        Picker("Tool Approval Mode", selection: $manager.mode) {
            ForEach(ToolApprovalMode.allCases, id: \.self) { mode in
                HStack {
                    Image(systemName: mode.icon)
                    Text(mode.displayName)
                }
                .tag(mode)
            }
        }
        .pickerStyle(.menu)
        .help(manager.mode.description)
    }
}
