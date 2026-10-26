//
//  CollaborationView.swift
//  MicroCode
//
//  Formal Native-IDE Multi-User Team Collaboration Hub
//  Zero-Setup Host/Join, Bonjour LAN Auto-Discovery, Online Tunnel,
//  Multi-Cursor Presence, Follow Mode, Shared Workspace Files, and Team Tasks.
//  Matches MicroCode's formal monochrome Settings & IDE theme.
//
//  Dotmini Company Limited
//

import SwiftUI
import AppKit

struct CollaborationView: View {
    var isEmbeddedInSettings: Bool = false
    @StateObject private var collab = CollaborationService.shared
    @ObservedObject private var taskStore = TeamTaskService.shared
    @ObservedObject private var integrations = TeamIntegrationService.shared
    
    @State private var selectedTab: CollabTab = .overview
    @State private var joinInput: String = ""
    @State private var joinError: String? = nil
    @State private var isJoining: Bool = false
    @State private var chatInput: String = ""
    @State private var fileFilter: String = ""
    @State private var copiedLink: Bool = false
    @State private var copiedToken: Bool = false
    @State private var showQRPopover: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    
    enum CollabTab: String, CaseIterable, Identifiable {
        case overview = "Session & Peers"
        case files = "Workspace Files"
        case tasks = "Team Tasks"
        case activity = "Chat & Activity"
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .overview: return "person.2"
            case .files: return "folder"
            case .tasks: return "checklist"
            case .activity: return "text.bubble"
            }
        }
    }
    
    var body: some View {
        Group {
            if isEmbeddedInSettings {
                embeddedSettingsBody
            } else {
                standaloneSheetBody
            }
        }
        .onAppear {
            collab.refreshNetworkAddresses()
            collab.startBonjourDiscovery()
            if let wsPath = AppState.shared?.workspaceFolder?.path {
                taskStore.load(workspacePath: wsPath)
            }
        }
    }
    
    // MARK: - Embedded in Settings Layout (No Nested ScrollView / Box)
    
    private var embeddedSettingsBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            serviceHeaderCard
            
            if collab.currentSession != nil {
                activeSessionBannerCard
                embeddedTabContent
            } else {
                switch selectedTab {
                case .overview:
                    disconnectedOverviewStack
                case .files:
                    sharedWorkspaceFilesCard
                case .tasks:
                    TeamTasksView(
                        workspacePath: AppState.shared?.workspaceFolder?.path,
                        activeChatID: AgentService.shared.activeChatId,
                        isEmbedded: true
                    )
                case .activity:
                    chatAndActivitySplitCard
                }
            }
        }
    }
    
    // MARK: - Standalone Modal Sheet Layout
    
    private var standaloneSheetBody: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                serviceHeaderTopRow(showCloseButton: true)
                navigationTabBar
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider().opacity(0.5)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if collab.currentSession != nil {
                        activeSessionBannerCard
                        embeddedTabContent
                    } else {
                        switch selectedTab {
                        case .overview:
                            disconnectedOverviewStack
                        case .files:
                            sharedWorkspaceFilesCard
                        case .tasks:
                            TeamTasksView(
                                workspacePath: AppState.shared?.workspaceFolder?.path,
                                activeChatID: AgentService.shared.activeChatId,
                                isEmbedded: true
                            )
                        case .activity:
                            chatAndActivitySplitCard
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(minWidth: 820, maxWidth: 880, minHeight: 580, maxHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - 1. Service Header & Single-Line Navigation Tab Bar
    
    private var serviceHeaderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            serviceHeaderTopRow(showCloseButton: false)
            Divider().opacity(0.4)
            navigationTabBar
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func serviceHeaderTopRow(showCloseButton: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 38, height: 38)
                Image(systemName: "person.2")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Team Collaboration Service")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    statusBadge
                }
                
                Text("Zero-setup P2P LAN & Online Tunnel co-editing, live cursor presence, and shared task contracts.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 8)
            
            if showCloseButton {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var navigationTabBar: some View {
        HStack(spacing: 4) {
            ForEach(CollabTab.allCases) { tab in
                let isSelected = (selectedTab == tab)
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        Text(tab.rawValue)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        if tab == .tasks && !taskStore.tasks.isEmpty {
                            Text("\(taskStore.tasks.count)")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.08))
                                .cornerRadius(3)
                        }
                    }
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.primary.opacity(0.16) : Color.clear, lineWidth: 1)
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .cornerRadius(8)
    }
    
    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 5.5, height: 5.5)
            Text(statusBadgeText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(4)
    }
    
    private var statusDotColor: Color {
        switch collab.connectionStatus {
        case .connected: return Color.primary.opacity(0.8)
        case .connecting, .reconnecting: return Color.primary.opacity(0.55)
        case .disconnected: return Color.secondary.opacity(0.45)
        case .error: return Color.secondary.opacity(0.6)
        }
    }
    
    private var statusBadgeText: String {
        if let session = collab.currentSession {
            if session.isHostingLocally {
                return "HOSTING · PORT \(collab.listeningPort)"
            }
            return "CONNECTED · \(session.shareCode)"
        }
        switch collab.connectionStatus {
        case .connected: return "CONNECTED"
        case .connecting: return "CONNECTING"
        case .reconnecting: return "RECONNECTING"
        case .disconnected: return "STANDBY"
        case .error(let msg): return msg.uppercased()
        }
    }
    
    // MARK: - 2. Disconnected Overview Stack
    
    private var disconnectedOverviewStack: some View {
        VStack(alignment: .leading, spacing: 16) {
            identityProfileCard
            
            HStack(alignment: .top, spacing: 14) {
                hostSessionCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                
                joinSessionCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
            
            discoveredLANSessionsCard
        }
    }
    
    // MARK: - Collaborator Identity Card (Formal Monochrome, Zero Text Crushing)
    
    private var identityProfileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("COLLABORATOR IDENTITY")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Used for live cursor labels, file lock indicators, and shared task ownership")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            HStack(spacing: 10) {
                // Formal Monochrome Avatar Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: 30, height: 30)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                        )
                    Text(String(collab.localDisplayName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.88))
                }
                
                // Flat Theme-Matched Display Name Field
                HStack(spacing: 8) {
                    Text("NAME")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                    
                    TextField("Collaborator display name", text: $collab.localDisplayName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                )
                .cornerRadius(6)
                
                // Flat Monochrome Role Selector ("Editor" / "Reviewer")
                HStack(spacing: 2) {
                    ForEach(["Editor", "Reviewer"], id: \.self) { role in
                        let isSelected = (collab.localRole == role)
                        Button {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                collab.localRole = role
                            }
                        } label: {
                            Text(role)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(isSelected ? .primary : .secondary)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(isSelected ? Color.primary.opacity(0.09) : Color.clear)
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                )
                .cornerRadius(6)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Host Workspace Session Card
    
    private var hostSessionCard: some View {
        let wsName = AppState.shared?.workspaceFolder?.lastPathComponent ?? "Workspace"
        let wsPath = AppState.shared?.workspaceFolder?.path ?? ""
        let wsLang = PhoneCompanionService.shared.detectWorkspaceLanguageInfo(path: wsPath)
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("HOST WORKSPACE SESSION")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("ZERO SETUP")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
            }
            
            HStack(spacing: 8) {
                ProgrammingLanguageIconView(fileName: wsLang.primary, size: 16)
                Text(wsName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if wsLang.label != "Workspace" {
                    Text(wsLang.label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                }
            }
            
            Text("Starts an embedded collaboration host on this Mac. Teammates on the same Wi-Fi discover it automatically, or join via Online Tunnel.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
            
            // Full-width Formal Monochrome Transport Mode Bar
            HStack(spacing: 4) {
                ForEach(CollaborationService.TransportMode.allCases) { mode in
                    let isSelected = (collab.transportMode == mode)
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            collab.setTransportMode(mode)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode == .lan ? "wifi" : "globe")
                                .font(.system(size: 10, weight: .medium))
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(isSelected ? Color.primary.opacity(0.09) : Color.clear)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .cornerRadius(6)
            
            // Full-width Formal Monochrome Primary Button
            Button {
                Task {
                    joinError = nil
                    _ = try? await collab.createSession(projectId: wsName)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9.5))
                    Text("Start Host Session")
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                )
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Join Teammate Session Card
    
    private var joinSessionCard: some View {
        let canJoin = !joinInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isJoining
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("JOIN TEAMMATE SESSION")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("LAN / TUNNEL")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
            }
            
            Text("Enter a teammate's Join Token (e.g. 192.168.1.50:8472#ABCD12), Online Tunnel URL, or 6-character Room Code.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            if let err = joinError {
                Text(err)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
            
            // Flat Theme-Matched Join Input Row with Inline Paste Action
            HStack(spacing: 6) {
                TextField("192.168.1.x:8472#CODE or https://...", text: $joinInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(.primary)
                    .onSubmit { triggerJoin() }
                
                Button {
                    if let str = NSPasteboard.general.string(forType: .string) {
                        joinInput = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 9.5))
                        Text("Paste")
                            .font(.system(size: 10.5, weight: .medium))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            )
            .cornerRadius(6)
            
            // Full-width Formal Monochrome Primary Button
            Button {
                triggerJoin()
            } label: {
                HStack(spacing: 6) {
                    if isJoining {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text("Connect to Session")
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundColor(canJoin ? .primary : .secondary.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(canJoin ? Color.primary.opacity(0.09) : Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(canJoin ? Color.primary.opacity(0.18) : Color.primary.opacity(0.07), lineWidth: 1)
                )
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(!canJoin)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Discovered LAN Sessions Card
    
    private var discoveredLANSessionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "wifi")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("DISCOVERED ON LOCAL NETWORK (BONJOUR / mDNS)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    collab.startBonjourDiscovery()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                        Text("Refresh")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
            
            if collab.discoveredSessions.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("No active MicroCode sessions detected on the local subnet yet. When a teammate starts a host session on the same Wi-Fi/LAN, it appears here automatically.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(collab.discoveredSessions) { item in
                    HStack(spacing: 10) {
                        ProgrammingLanguageIconView(fileName: item.workspaceLang, size: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.workspaceName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("ROOM \(item.shareCode)")
                                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.06))
                                    .cornerRadius(3)
                            }
                            Text("Hosted by \(item.hostName) · \(item.hostAddress):\(item.port)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await collab.joinDiscoveredSession(item) }
                        } label: {
                            Text("Join Session")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                                )
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(6)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Active Session Banner Card
    
    private var activeSessionBannerCard: some View {
        let session = collab.currentSession
        let link = collab.getShareLink() ?? ""
        let token = collab.getJoinToken()
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgrammingLanguageIconView(fileName: session?.workspaceLang ?? "code", size: 16)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session?.workspaceName ?? "Workspace")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("ROOM \(session?.shareCode ?? "")")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.07))
                            .cornerRadius(4)
                    }
                    Text(link)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer()
                
                if session?.isHostingLocally == true {
                    HStack(spacing: 2) {
                        ForEach(CollaborationService.TransportMode.allCases) { mode in
                            let isSelected = (collab.transportMode == mode)
                            Button {
                                collab.setTransportMode(mode)
                            } label: {
                                Text(mode.rawValue)
                                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(isSelected ? .primary : .secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isSelected ? Color.primary.opacity(0.09) : Color.clear)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                }
                
                formalActionButton(
                    icon: copiedToken ? "checkmark" : "key",
                    label: copiedToken ? "Copied" : "Copy Token"
                ) {
                    collab.copyJoinTokenToClipboard()
                    copiedToken = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedToken = false }
                }
                .help("Copy IDE Join Token (\(token))")
                
                formalActionButton(
                    icon: copiedLink ? "checkmark" : "doc.on.doc",
                    label: copiedLink ? "Copied" : "Copy Link"
                ) {
                    collab.copyShareLinkToClipboard()
                    copiedLink = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedLink = false }
                }
                
                formalActionButton(icon: "qrcode", label: "QR") {
                    showQRPopover.toggle()
                }
                .popover(isPresented: $showQRPopover) {
                    VStack(spacing: 10) {
                        Text("SCAN TO JOIN IN BROWSER")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                        if let qr = collab.qrCodeImage {
                            Image(nsImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 150, height: 150)
                                .padding(8)
                                .background(Color.white)
                                .cornerRadius(8)
                        }
                        Text(link)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(14)
                    .frame(width: 220)
                }
                
                formalActionButton(
                    icon: "xmark",
                    label: session?.isHostingLocally == true ? "End" : "Leave"
                ) {
                    Task { await collab.leaveSession() }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func formalActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Active Session Tab Content
    
    @ViewBuilder
    private var embeddedTabContent: some View {
        switch selectedTab {
        case .overview:
            overviewSplitCard
        case .files:
            sharedWorkspaceFilesCard
        case .tasks:
            TeamTasksView(
                workspacePath: AppState.shared?.workspaceFolder?.path,
                activeChatID: AgentService.shared.activeChatId,
                isEmbedded: true
            )
        case .activity:
            chatAndActivitySplitCard
        }
    }
    
    private var overviewSplitCard: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left: Active Participants
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("PARTICIPANTS (\(collab.participants.count))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    if collab.followingUserId != nil {
                        Button("Stop Following") {
                            collab.followingUserId = nil
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.primary)
                    }
                }
                
                Divider().opacity(0.4)
                
                if collab.participants.isEmpty {
                    Text("No active participants.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(collab.participants) { participant in
                            ParticipantRow(
                                participant: participant,
                                isSelf: participant.userId == collab.localUserId,
                                isFollowing: collab.followingUserId == participant.userId,
                                onToggleFollow: { collab.toggleFollow(userId: participant.userId) }
                            )
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            // Right: Shared Workspace Files
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("SHARED WORKSPACE FILES (\(collab.sharedFiles.count))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        collab.indexLocalWorkspaceFiles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Divider().opacity(0.4)
                
                if collab.sharedFiles.isEmpty {
                    Text("Start or join a session to browse shared workspace files.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(collab.sharedFiles.prefix(15)) { file in
                            sharedFileRow(file)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    private var sharedWorkspaceFilesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("Filter shared workspace files by name or path…", text: $fileFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                Spacer()
                Text("\(filteredSharedFiles.count) files")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
                Button {
                    collab.indexLocalWorkspaceFiles()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .cornerRadius(6)
            
            if filteredSharedFiles.isEmpty {
                Text("No workspace files indexed yet. Start a host session or click refresh.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(filteredSharedFiles.prefix(80)) { file in
                        sharedFileRow(file)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var filteredSharedFiles: [SharedWorkspaceFile] {
        let q = fileFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return collab.sharedFiles }
        return collab.sharedFiles.filter {
            $0.relativePath.lowercased().contains(q) || $0.name.lowercased().contains(q)
        }
    }
    
    private func sharedFileRow(_ file: SharedWorkspaceFile) -> some View {
        HStack(spacing: 10) {
            ProgrammingLanguageIconView(fileName: file.name, size: 15)
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if file.isOpenOnHost {
                        Text("OPEN")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(3)
                    }
                }
                Text(file.relativePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let editor = file.activeEditorName, !editor.isEmpty {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: 5.5, height: 5.5)
                    Text(editor)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
            }
            
            formalActionButton(icon: "arrow.up.forward.square", label: "Open") {
                Task {
                    await collab.openSharedFileInEditor(file)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    // MARK: - Chat & Activity Split Card
    
    private var chatAndActivitySplitCard: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left: Session Engineering Chat
            VStack(alignment: .leading, spacing: 10) {
                Text("SESSION CHAT")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Divider().opacity(0.4)
                
                if collab.chatMessages.isEmpty {
                    Text("No messages in this session yet.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 16)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(collab.chatMessages.suffix(25)) { msg in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(msg.displayName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text(msg.timestamp.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Text(msg.message)
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                            }
                            .padding(9)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                        }
                    }
                }
                
                HStack(spacing: 8) {
                    TextField("Message collaborators…", text: $chatInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                        )
                        .cornerRadius(6)
                        .onSubmit { submitChat() }
                    
                    formalActionButton(icon: "paperplane", label: "Send") {
                        submitChat()
                    }
                    .disabled(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            // Right: Realtime Audit Activity Feed
            VStack(alignment: .leading, spacing: 10) {
                Text("REALTIME ACTIVITY LOG")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Divider().opacity(0.4)
                
                if collab.activityLog.isEmpty {
                    Text("Session events (joins, edits, tasks) appear here.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 16)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(collab.activityLog.suffix(25).reversed()) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(item.actorName)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text(item.action)
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.secondary)
                                    if !item.target.isEmpty {
                                        Text(item.target)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                    }
                                }
                                Text(item.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.025))
                            .cornerRadius(5)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Actions
    
    private func triggerJoin() {
        let code = joinInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isJoining = true
        joinError = nil
        Task {
            do {
                _ = try await collab.joinSession(shareCode: code)
                isJoining = false
            } catch {
                isJoining = false
                joinError = error.localizedDescription
            }
        }
    }
    
    private func submitChat() {
        let msg = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return }
        chatInput = ""
        Task {
            await collab.sendChatMessage(msg)
        }
    }
}

// MARK: - Formal Participant Row

struct ParticipantRow: View {
    let participant: CollaborationSession.Participant
    var isSelf: Bool = false
    var isFollowing: Bool = false
    var onToggleFollow: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                    )
                Text(participant.displayName.prefix(1).uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.88))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(participant.displayName + (isSelf ? " (You)" : ""))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(participant.role.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(3)
                }
                
                if let cursor = participant.cursorPosition, !cursor.filePath.isEmpty {
                    HStack(spacing: 5) {
                        ProgrammingLanguageIconView(fileName: (cursor.filePath as NSString).lastPathComponent, size: 11)
                        Text("\((cursor.filePath as NSString).lastPathComponent) · Ln \(cursor.line)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Viewing workspace")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                
                if participant.isAIActive, let aiText = participant.aiStatusText, !aiText.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.primary.opacity(0.65))
                            .frame(width: 5, height: 5)
                        Text("AI Agent: \(aiText)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            if !isSelf, let onToggleFollow {
                Button(action: onToggleFollow) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isFollowing ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
            
            Circle()
                .fill(participant.isOnline ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)
        }
        .padding(10)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
