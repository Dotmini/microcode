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

private struct CollabContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 640
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 10 { value = next }
    }
}

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
    @State private var copiedRoomCode: Bool = false
    @State private var copiedToken: Bool = false
    @State private var showQRPopover: Bool = false
    @State private var containerWidth: CGFloat = 640
    
    @Environment(\.dismiss) private var dismiss

    private var useStackedSplitLayout: Bool {
        containerWidth < 740
    }
    
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
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: CollabContainerWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(CollabContainerWidthKey.self) { width in
            if abs(containerWidth - width) > 2 {
                containerWidth = width
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
        VStack(alignment: .leading, spacing: 14) {
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
        .frame(minWidth: 860, idealWidth: 940, maxWidth: 1120, minHeight: 600, idealHeight: 680, maxHeight: 820)
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
                    Text("Team Collaboration")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    statusBadge
                }
                
                Text("Real-time P2P LAN & Dotmini Official HTTPS co-editing, live multiplayer cursors, and shared tasks.")
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
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
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
                    .padding(.horizontal, 6)
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
                .frame(width: 6, height: 6)
            Text(statusBadgeText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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
        case .connected: return Color.green
        case .connecting, .reconnecting: return Color.orange
        case .disconnected: return Color.secondary.opacity(0.45)
        case .error: return Color.red.opacity(0.8)
        }
    }
    
    private var statusBadgeText: String {
        if let session = collab.currentSession {
            if session.isHostingLocally {
                return "HOSTING · :\(collab.listeningPort)"
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
        VStack(alignment: .leading, spacing: 14) {
            identityProfileCard
            
            if containerWidth < 620 {
                VStack(alignment: .leading, spacing: 14) {
                    hostSessionCard
                    joinSessionCard
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    hostSessionCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    
                    joinSessionCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            
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
            
            Text("Starts an embedded collaboration host on a dedicated isolated port. Teammates on Wi-Fi discover it automatically, or join anywhere via Dotmini Official HTTPS Relay.")
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
                                .fixedSize(horizontal: true, vertical: false)
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
                Text("LAN / HTTPS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
            }
            
            Text("Paste an Invite Link (https://cloudai.dotmini.net/.../?code=ABCD12), LAN Join Token (192.168.1.x:8490#ABCD12), or 6-character Room Code.")
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
                TextField("https://cloudai.dotmini.net/... or Room Code", text: $joinInput)
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
    
    // MARK: - Active Session Banner & Credentials Card (Apple HIG, 100% Responsive)
    
    private var activeSessionBannerCard: some View {
        let session = collab.currentSession
        let roomCode = session?.shareCode ?? ""
        let link = collab.getShareLink() ?? ""
        let token = collab.getJoinToken()
        let isOnlineMode = (collab.transportMode == .online)
        let isConnectingOnline = (isOnlineMode && collab.tunnelStatus == .starting)
        let isRelayActive: Bool = {
            if case .active = collab.tunnelStatus { return true }
            return false
        }()
        
        return VStack(alignment: .leading, spacing: 12) {
            // Tier 1: Workspace Identity + Transport Mode + End/Leave Action
            HStack(spacing: 10) {
                ProgrammingLanguageIconView(fileName: session?.workspaceLang ?? "code", size: 17)
                
                Text(session?.workspaceName ?? "Workspace")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if isOnlineMode {
                    HStack(spacing: 5) {
                        if isConnectingOnline {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.75)
                        } else {
                            Circle()
                                .fill(isRelayActive ? Color(red: 0.22, green: 0.76, blue: 0.48) : Color.secondary.opacity(0.55))
                                .frame(width: 5.5, height: 5.5)
                        }
                        Text(
                            isConnectingOnline
                                ? "Connecting cloudai.dotmini.net…"
                                : (collab.isOfficialDotminiRelayActive ? "Dotmini Official Relay" : "Online HTTPS Relay")
                        )
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                    )
                    .cornerRadius(5)
                } else {
                    HStack(spacing: 4.5) {
                        Circle()
                            .fill(Color(red: 0.22, green: 0.76, blue: 0.48))
                            .frame(width: 5.5, height: 5.5)
                        Text("LAN · :\(collab.listeningPort)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                    )
                    .cornerRadius(5)
                }
                
                Spacer(minLength: 8)
                
                if session?.isHostingLocally == true {
                    HStack(spacing: 2) {
                        ForEach(CollaborationService.TransportMode.allCases) { mode in
                            let isSelected = (collab.transportMode == mode)
                            Button {
                                collab.setTransportMode(mode)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: mode == .lan ? "wifi" : "globe")
                                        .font(.system(size: 9.5, weight: .semibold))
                                    Text(mode.rawValue)
                                        .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .foregroundColor(isSelected ? .primary : .secondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4.5)
                                .background(isSelected ? Color.primary.opacity(0.10) : Color.clear)
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .cornerRadius(6)
                    .fixedSize(horizontal: true, vertical: false)
                }
                
                formalActionButton(
                    icon: "xmark",
                    label: session?.isHostingLocally == true ? "End" : "Leave"
                ) {
                    Task { await collab.leaveSession() }
                }
            }
            
            // Tier 2: Explicit Access Credentials (Room Access Code + Direct Invite Link — Zero Ambiguity)
            if containerWidth < 600 {
                VStack(alignment: .leading, spacing: 8) {
                    roomCodeCredentialBox(roomCode: roomCode)
                    directInviteLinkBox(link: link, roomCode: roomCode, token: token, isConnectingOnline: isConnectingOnline)
                }
            } else {
                HStack(spacing: 10) {
                    roomCodeCredentialBox(roomCode: roomCode)
                        .fixedSize(horizontal: true, vertical: false)
                    directInviteLinkBox(link: link, roomCode: roomCode, token: token, isConnectingOnline: isConnectingOnline)
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

    private func roomCodeCredentialBox(roomCode: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ROOM ACCESS CODE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 8) {
                Text(roomCode)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(roomCode, forType: .string)
                    copiedRoomCode = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedRoomCode = false }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copiedRoomCode ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(copiedRoomCode ? "Copied" : "Copy")
                            .font(.system(size: 10, weight: .semibold))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundColor(copiedRoomCode ? .green : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Copy 6-character Room Access Code (\(roomCode))")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        )
        .cornerRadius(7)
    }

    private func directInviteLinkBox(link: String, roomCode: String, token: String, isConnectingOnline: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("DIRECT INVITE LINK (ROOM CODE INCLUDED · NO EXTRA PASSWORD)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if collab.transportMode == .lan {
                    Button {
                        collab.copyJoinTokenToClipboard()
                        copiedToken = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedToken = false }
                    } label: {
                        Text(copiedToken ? "✓ IDE Token Copied" : "Copy IDE Token")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .help("Copy compact IDE Join Token (\(token))")
                }
            }

            HStack(spacing: 8) {
                Text(isConnectingOnline ? "Establishing Dotmini Official HTTPS Relay (cloudai.dotmini.net)…" : link)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundColor(isConnectingOnline ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    collab.copyShareLinkToClipboard()
                    copiedLink = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedLink = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedLink ? "checkmark" : "link")
                            .font(.system(size: 10, weight: .semibold))
                        Text(copiedLink ? "Copied Link" : "Copy Invite Link")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(Color.primary.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                    )
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(isConnectingOnline)

                formalActionButton(icon: "qrcode", label: "QR") {
                    showQRPopover.toggle()
                }
                .popover(isPresented: $showQRPopover) {
                    VStack(spacing: 10) {
                        Text("SCAN TO JOIN IN MICROCODE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        if let qr = collab.qrCodeImage {
                            Image(nsImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 156, height: 156)
                                .padding(8)
                                .background(Color.white)
                                .cornerRadius(8)
                        }
                        HStack(spacing: 6) {
                            Text("ROOM CODE:")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(roomCode)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(5)

                        Text(link)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                    .padding(14)
                    .frame(width: 248)
                }
            }

            if collab.currentSession?.isHostingLocally == true {
                Toggle(isOn: $collab.allowBrowserGuests) {
                    Text("Also allow editing in a web browser")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .toggleStyle(.checkbox)
                .help("Invite links open MicroCode. Turn this on to also offer the browser editor on the invite page.")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        )
        .cornerRadius(7)
    }
    
    private func formalActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
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
        .fixedSize(horizontal: true, vertical: false)
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
    
    @ViewBuilder
    private var overviewSplitCard: some View {
        if useStackedSplitLayout {
            VStack(alignment: .leading, spacing: 14) {
                participantsOverviewCard
                sharedWorkspaceFilesOverviewCard
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                participantsOverviewCard
                sharedWorkspaceFilesOverviewCard
            }
        }
    }

    private var participantsOverviewCard: some View {
        let isFollowingAI = collab.followingUserId == CollaborationService.aiTeammateUserId
        let isFollowingOtherPeer = (collab.followingUserId != nil && !isFollowingAI)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("PARTICIPANTS (\(collab.participants.count))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 6)

                Button {
                    collab.setAITeammateEnabled(!collab.isAITeammateEnabled)
                } label: {
                    HStack(spacing: 4.5) {
                        AIProviderBrandIcon(provider: "microcode", size: 11)
                        Text(collab.isAITeammateEnabled ? "Agent · ON" : "Agent · OFF")
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundColor(collab.isAITeammateEnabled ? .primary : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(collab.isAITeammateEnabled ? 0.09 : 0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary.opacity(collab.isAITeammateEnabled ? 0.16 : 0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("เปิด/ปิด MicroCode Agent เป็นผู้ร่วมงานในเซสชัน")

                if collab.isAITeammateEnabled {
                    Button {
                        collab.toggleFollow(userId: CollaborationService.aiTeammateUserId)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isFollowingAI ? "eye.fill" : "eye")
                                .font(.system(size: 9.5, weight: .medium))
                            Text(isFollowingAI ? "Following Agent" : "Follow Agent")
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundColor(isFollowingAI ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.primary.opacity(isFollowingAI ? 0.13 : 0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.primary.opacity(isFollowingAI ? 0.24 : 0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .help(isFollowingAI ? "คลิกเพื่อหยุดติดตามตำแหน่งไฟล์ของ Agent" : "ติดตามดูไฟล์และบรรทัดที่ Agent กำลังทำงานแบบ Real-Time")
                }

                if isFollowingOtherPeer {
                    Button {
                        collab.followingUserId = nil
                    } label: {
                        Text("Unfollow")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color.primary.opacity(0.07))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
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
    }

    private var prioritizedOverviewFiles: [SharedWorkspaceFile] {
        collab.sharedFiles.sorted { lhs, rhs in
            let lActive = (lhs.activeEditorName?.isEmpty == false) || lhs.isOpenOnHost
            let rActive = (rhs.activeEditorName?.isEmpty == false) || rhs.isOpenOnHost
            if lActive != rActive { return lActive && !rActive }
            return lhs.relativePath < rhs.relativePath
        }
    }

    private var sharedWorkspaceFilesOverviewCard: some View {
        let previewFiles = Array(prioritizedOverviewFiles.prefix(8))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("SHARED WORKSPACE FILES (\(collab.sharedFiles.count))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
                if collab.sharedFiles.count > 8 {
                    Button {
                        selectedTab = .files
                    } label: {
                        HStack(spacing: 3) {
                            Text("Browse all \(collab.sharedFiles.count)")
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    collab.indexLocalWorkspaceFiles(forceDiskScan: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Re-index workspace files")
            }
            
            Divider().opacity(0.4)
            
            if collab.sharedFiles.isEmpty {
                Text("Start or join a session to browse shared workspace files.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(previewFiles) { file in
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
                Text("\(collab.sharedDirectories.count) folders · \(filteredSharedFiles.count) files")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Button {
                    collab.indexLocalWorkspaceFiles(forceDiskScan: true)
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
                LazyVStack(spacing: 5) {
                    ForEach(filteredSharedFiles.prefix(300)) { file in
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
        let base = collab.sharedFiles.sorted { $0.relativePath < $1.relativePath }
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.relativePath.lowercased().contains(q) || $0.name.lowercased().contains(q)
        }
    }
    
    private func sharedFileRow(_ file: SharedWorkspaceFile) -> some View {
        let folderDir = (file.relativePath as NSString).deletingLastPathComponent
        let peerColor = CollaborationColorHelper.swiftUIColor(fromHex: file.activeEditorColor ?? "#3B82F6")
        return HStack(spacing: 10) {
            ProgrammingLanguageIconView(fileName: file.name, size: 15)
            
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if file.isOpenOnHost {
                        Text("OPEN")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(3)
                    }
                }
                if !folderDir.isEmpty {
                    Text(file.relativePath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.82))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            Spacer(minLength: 8)
            
            if let editor = file.activeEditorName, !editor.isEmpty {
                let isAIEditor = (editor == CollaborationService.aiTeammateDisplayName)
                HStack(spacing: 4.5) {
                    if isAIEditor {
                        AIProviderBrandIcon(provider: "microcode", size: 10)
                    } else {
                        Circle()
                            .fill(peerColor.opacity(0.85))
                            .frame(width: 5.5, height: 5.5)
                    }
                    Text(editor)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .cornerRadius(4)
                .fixedSize(horizontal: true, vertical: false)
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
    
    @ViewBuilder
    private var chatAndActivitySplitCard: some View {
        if useStackedSplitLayout {
            VStack(alignment: .leading, spacing: 14) {
                sessionChatCard
                realtimeActivityCard
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                sessionChatCard
                realtimeActivityCard
            }
        }
    }

    private var sessionChatCard: some View {
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
                Button {
                    if !chatInput.lowercased().hasPrefix("@ai ") {
                        chatInput = "@ai " + chatInput
                    }
                } label: {
                    HStack(spacing: 4) {
                        AIProviderBrandIcon(provider: "microcode", size: 11)
                        Text("@ai")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("สั่งงาน MicroCode Agent ร่วมกับทีมใน Session Chat (@ai ...)")

                TextField("Message collaborators or type @ai to command AI Agent…", text: $chatInput)
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
    }

    private var realtimeActivityCard: some View {
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
                                    .lineLimit(1)
                                Text(item.action)
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                if !item.target.isEmpty {
                                    Text(item.target)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
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
        let peerColor = CollaborationColorHelper.swiftUIColor(fromHex: participant.color)
        let isAITeammate = participant.userId == CollaborationService.aiTeammateUserId || participant.role == "AI Agent"
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.11), lineWidth: 1)
                    )
                if isAITeammate {
                    AIProviderBrandIcon(provider: "microcode", size: 15)
                } else {
                    Text(participant.displayName.prefix(1).uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
            
            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 6) {
                    Text(participant.displayName + (isSelf ? " (You)" : ""))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    
                    Text(isAITeammate ? "AGENT" : participant.role.uppercased())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.055))
                        .cornerRadius(3.5)
                }
                
                HStack(spacing: 5) {
                    if let cursor = participant.cursorPosition, !cursor.filePath.isEmpty {
                        ProgrammingLanguageIconView(fileName: (cursor.filePath as NSString).lastPathComponent, size: 11)
                    } else {
                        Circle()
                            .fill(peerColor.opacity(0.75))
                            .frame(width: 5, height: 5)
                    }
                    Text(participant.liveActivitySummary)
                        .font(.system(size: 10.5, weight: participant.cursorPosition?.isTyping == true ? .medium : .regular, design: .monospaced))
                        .foregroundColor(participant.cursorPosition?.isTyping == true ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                if participant.isAIActive, let aiText = participant.aiStatusText, !aiText.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.secondary.opacity(0.65))
                            .frame(width: 4.5, height: 4.5)
                        Text(aiText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            
            Spacer(minLength: 8)
            
            if !isSelf, participant.cursorPosition != nil {
                Button {
                    Task {
                        await CollaborationService.shared.jumpToParticipant(participant)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8.5, weight: .semibold))
                        Text("Jump")
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                    )
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
            }

            if !isSelf, let onToggleFollow {
                Button(action: onToggleFollow) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(isFollowing ? 0.13 : 0.045))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.primary.opacity(isFollowing ? 0.26 : 0.10), lineWidth: 1)
                        )
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
            }
            
            Circle()
                .fill(participant.isOnline ? Color(red: 0.22, green: 0.76, blue: 0.48) : Color.secondary.opacity(0.30))
                .frame(width: 6, height: 6)
        }
        .padding(10)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(isFollowing ? 0.22 : 0.07), lineWidth: 1)
        )
    }
}

// MARK: - Live Multiplayer Header Presence Bar (Compact Apple HIG Pill — Never Crushes Window Titlebar)

struct HeaderCollaborationPresenceBar: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var collab = CollaborationService.shared
    @State private var copiedFeedback = false

    var body: some View {
        if let session = collab.currentSession {
            let online = collab.onlineParticipants()
            let remotes = collab.remoteOnlineParticipants()
            let activeSummary: String = {
                if let peer = remotes.first {
                    return "Room \(session.shareCode) · \(peer.displayName): \(peer.liveActivitySummary)"
                }
                return "Room \(session.shareCode) · \(online.count) online"
            }()

            HStack(spacing: 5) {
                Button {
                    appState.showingCollaborationView = true
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(red: 0.22, green: 0.76, blue: 0.48))
                            .frame(width: 5.5, height: 5.5)

                        HStack(spacing: -4) {
                            ForEach(Array(online.prefix(3))) { peer in
                                let isAI = peer.userId == CollaborationService.aiTeammateUserId || peer.role == "AI Agent"
                                ZStack {
                                    Circle()
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .frame(width: 17, height: 17)
                                    if isAI {
                                        AIProviderBrandIcon(provider: "microcode", size: 10)
                                    } else {
                                        Text(peer.displayName.prefix(1).uppercased())
                                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.primary)
                                    }
                                }
                                .overlay(
                                    Circle().stroke(Color.primary.opacity(0.16), lineWidth: 1)
                                )
                            }
                        }

                        Text(session.shareCode)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.9))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .buttonStyle(.plain)
                .help(activeSummary)

                if let followingId = collab.followingUserId {
                    Button {
                        collab.toggleFollow(userId: followingId)
                    } label: {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Currently following collaborator — click to stop following")
                }

                Menu {
                    Section("Room \(session.shareCode) · \(online.count) Online") {
                        Button {
                            collab.copyShareLinkToClipboard()
                            copiedFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedFeedback = false }
                        } label: {
                            Label(copiedFeedback ? "Copied Direct Invite Link!" : "Copy Direct Invite Link (No Password)", systemImage: "link")
                        }
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(session.shareCode, forType: .string)
                        } label: {
                            Label("Copy Room Access Code (\(session.shareCode))", systemImage: "number")
                        }
                    }

                    Section("Multiplayer Cursors") {
                        Toggle(isOn: Binding(
                            get: { collab.showLocalCursorTag },
                            set: { collab.showLocalCursorTag = $0 }
                        )) {
                            Label("แสดงป้ายเมาส์ของฉัน (My Live Cursor)", systemImage: "cursorarrow.motionlines")
                        }

                        ForEach(remotes) { peer in
                            Button {
                                Task { await collab.jumpToParticipant(peer) }
                            } label: {
                                Label("Jump to \(peer.displayName) (\(peer.liveActivitySummary))", systemImage: "arrow.up.right")
                            }
                            Button {
                                collab.toggleFollow(userId: peer.userId)
                            } label: {
                                Label(
                                    collab.followingUserId == peer.userId ? "Stop Following \(peer.displayName)" : "Follow \(peer.displayName)",
                                    systemImage: collab.followingUserId == peer.userId ? "eye.slash" : "eye.fill"
                                )
                            }
                        }
                    }

                    Divider()
                    Button {
                        appState.showingCollaborationView = true
                    } label: {
                        Label("Open Team Collaboration Panel…", systemImage: "person.2")
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 18)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.11), lineWidth: 1)
            )
        }
    }
}

// MARK: - Real-Time Workspace Multiplayer Mouse Overlay (Ours + Teammates)

private struct CollaboratorPointerArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 1, y: rect.minY + 1))
        p.addLine(to: CGPoint(x: rect.minX + 1, y: rect.minY + 16.5))
        p.addLine(to: CGPoint(x: rect.minX + 5.4, y: rect.minY + 12.6))
        p.addLine(to: CGPoint(x: rect.minX + 8.6, y: rect.minY + 18.2))
        p.addLine(to: CGPoint(x: rect.minX + 10.9, y: rect.minY + 17.0))
        p.addLine(to: CGPoint(x: rect.minX + 7.7, y: rect.minY + 11.4))
        p.addLine(to: CGPoint(x: rect.minX + 13.4, y: rect.minY + 11.1))
        p.closeSubpath()
        return p
    }
}

private struct CollabMouseMonitorAnchorView: NSViewRepresentable {
    let isEnabled: Bool
    let onLocalMouseEvent: (_ normalizedX: Double, _ normalizedY: Double, _ localPoint: CGPoint, _ isInside: Bool, _ isPressing: Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLocalMouseEvent: onLocalMouseEvent)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.setEnabled(isEnabled)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.onLocalMouseEvent = onLocalMouseEvent
        context.coordinator.setEnabled(isEnabled)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.setEnabled(false)
    }

    final class Coordinator {
        weak var hostView: NSView?
        var onLocalMouseEvent: (_ normalizedX: Double, _ normalizedY: Double, _ localPoint: CGPoint, _ isInside: Bool, _ isPressing: Bool) -> Void
        private var eventMonitor: Any?
        private var lastDispatchedTimestamp: TimeInterval = 0
        private var lastDispatchedPressing: Bool = false

        init(onLocalMouseEvent: @escaping (_ normalizedX: Double, _ normalizedY: Double, _ localPoint: CGPoint, _ isInside: Bool, _ isPressing: Bool) -> Void) {
            self.onLocalMouseEvent = onLocalMouseEvent
        }

        deinit {
            if let monitor = eventMonitor {
                if Thread.isMainThread {
                    NSEvent.removeMonitor(monitor)
                } else {
                    DispatchQueue.main.async {
                        NSEvent.removeMonitor(monitor)
                    }
                }
            }
        }

        func setEnabled(_ enabled: Bool) {
            if enabled {
                guard eventMonitor == nil else { return }
                eventMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
                ) { [weak self] event in
                    guard let self,
                          let view = self.hostView,
                          let win = view.window,
                          win.attachedSheet == nil,
                          event.window === win else {
                        return event
                    }
                    let bounds = view.bounds
                    guard bounds.width > 1, bounds.height > 1 else { return event }
                    let pressing = NSEvent.pressedMouseButtons != 0 || event.type == .leftMouseDown || event.type == .leftMouseDragged
                    let now = ProcessInfo.processInfo.systemUptime
                    if pressing == self.lastDispatchedPressing && (now - self.lastDispatchedTimestamp) < 0.033 {
                        return event
                    }
                    self.lastDispatchedTimestamp = now
                    self.lastDispatchedPressing = pressing

                    let pt = view.convert(event.locationInWindow, from: nil)
                    let flippedY = view.isFlipped ? pt.y : (bounds.height - pt.y)
                    let inside = pt.x >= 0 && pt.x <= bounds.width && flippedY >= 0 && flippedY <= bounds.height
                    let nx = max(0.0, min(1.0, Double(pt.x / bounds.width)))
                    let ny = max(0.0, min(1.0, Double(flippedY / bounds.height)))
                    let localPt = CGPoint(x: pt.x, y: flippedY)

                    // Dispatch outside AppKit's synchronous NSWindow.sendEvent: to prevent SwiftUI AttributeGraph re-entrancy crashes
                    DispatchQueue.main.async { [weak self] in
                        self?.onLocalMouseEvent(nx, ny, localPt, inside, pressing)
                    }
                    return event
                }
            } else if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }
}

struct CollaborationWorkspaceMouseOverlay: View {
    let surface: String
    @ObservedObject private var collab = CollaborationService.shared
    @State private var localPointerPoint: CGPoint = .zero
    @State private var isPointerInside: Bool = false
    @State private var isPointerRecentlyActive: Bool = false
    @State private var localIsPressing: Bool = false
    @State private var idleFadeTask: Task<Void, Never>? = nil

    var body: some View {
        let sessionActive = (collab.currentSession != nil)
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                CollabMouseMonitorAnchorView(isEnabled: sessionActive) { nx, ny, pt, inside, pressing in
                    localPointerPoint = pt
                    isPointerInside = inside
                    localIsPressing = pressing
                    if inside {
                        isPointerRecentlyActive = true
                        collab.updateLocalMouse(
                            normalizedX: nx,
                            normalizedY: ny,
                            surface: surface,
                            isPressing: pressing
                        )
                        idleFadeTask?.cancel()
                        idleFadeTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 2_200_000_000)
                            if !Task.isCancelled {
                                isPointerRecentlyActive = false
                            }
                        }
                    } else {
                        isPointerRecentlyActive = false
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if sessionActive {
                    let now = Date()
                    let remotePeers = collab.remoteOnlineParticipants().filter { peer in
                        guard let m = peer.mousePresence else { return false }
                        return now.timeIntervalSince(m.updatedAt) < 18.0
                    }

                    // 1. Remote Collaborators' Smooth Live Cursors & Editing Badges
                    ForEach(remotePeers) { peer in
                        if let mouse = peer.mousePresence {
                            let peerColor = CollaborationColorHelper.swiftUIColor(fromHex: peer.color)
                            let targetX = CGFloat(mouse.normalizedX) * max(1, geo.size.width)
                            let targetY = CGFloat(mouse.normalizedY) * max(1, geo.size.height)

                            ZStack(alignment: .topLeading) {
                                if mouse.isPressing {
                                    Circle()
                                        .stroke(peerColor.opacity(0.65), lineWidth: 2)
                                        .frame(width: 24, height: 24)
                                        .offset(x: -10, y: -10)
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    CollaboratorPointerArrowShape()
                                        .fill(peerColor)
                                        .overlay(
                                            CollaboratorPointerArrowShape()
                                                .stroke(Color.white, lineWidth: 1.35)
                                        )
                                        .frame(width: 15, height: 19)
                                        .shadow(color: Color.black.opacity(0.42), radius: 3, x: 0, y: 1.5)

                                    HStack(spacing: 4.5) {
                                        Circle()
                                            .fill(peerColor)
                                            .frame(width: 5.5, height: 5.5)
                                        Text(peer.displayName)
                                            .font(.system(size: 10.5, weight: .semibold))
                                            .foregroundColor(Color(white: 0.94))
                                        Text("· \(peer.liveActivitySummary)")
                                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                                            .foregroundColor(Color(white: 0.72))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color(red: 0.11, green: 0.12, blue: 0.14).opacity(0.95))
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
                                    .offset(x: 11, y: -2)
                                }
                            }
                            .offset(x: targetX, y: targetY)
                            .animation(.interactiveSpring(response: 0.085, dampingFraction: 0.86), value: mouse.normalizedX)
                            .animation(.interactiveSpring(response: 0.085, dampingFraction: 0.86), value: mouse.normalizedY)
                        }
                    }

                    // 2. Local Live Cursor Tag ("เมาส์ realtime ของเรา")
                    if collab.showLocalCursorTag,
                       isPointerInside,
                       isPointerRecentlyActive,
                       collab.localEditorCursor?.isTyping != true {
                        let myColor = CollaborationColorHelper.swiftUIColor(fromHex: collab.localColor)
                        let myCursorSummary: String = {
                            if let cur = collab.localEditorCursor, !cur.filePath.isEmpty {
                                return "\((cur.filePath as NSString).lastPathComponent):Ln \(cur.line)"
                            }
                            return surface == "agent" ? "Agent" : "Editor"
                        }()
                        let pillX = min(max(8, localPointerPoint.x + 15), max(8, geo.size.width - 175))
                        let pillY = min(max(8, localPointerPoint.y + 16), max(8, geo.size.height - 28))

                        HStack(spacing: 4.5) {
                            Circle()
                                .fill(myColor)
                                .frame(width: 5.5, height: 5.5)
                            Text("\(collab.localDisplayName) (You)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(white: 0.94))
                            Text("· \(myCursorSummary)")
                                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                                .foregroundColor(Color(white: 0.70))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(red: 0.11, green: 0.12, blue: 0.14).opacity(localIsPressing ? 0.98 : 0.93))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.28), radius: 3, x: 0, y: 1.5)
                        .offset(x: pillX, y: pillY)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
