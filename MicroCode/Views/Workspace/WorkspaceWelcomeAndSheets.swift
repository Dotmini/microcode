//
//  WorkspaceWelcomeAndSheets.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2024 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - Welcome Screen

enum WelcomeTab {
    case projects
    case templates
    case aiArchitect
    case settings
}

struct WelcomeScreen: View {
    @EnvironmentObject var appState: AppState
    var surface: Binding<AgenticWorkspaceSurface>? = nil
    
    @State private var recentProjects: [URL] = []
    @State private var selectedTab: WelcomeTab = .projects
    @State private var aiPrompt: String = ""
    @State private var isHoveringAI: Bool = false
    
    // For Clone Repository
    @State private var showCloneSheet: Bool = false
    @State private var gitCloneUrl: String = ""
    @State private var isCloning: Bool = false
    @State private var cloneError: String? = nil
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left Sidebar Panel
                leftSidebarView
                
                Divider()
                    .background(Color.primary.opacity(0.1))
                
                // Right Main Panel
                rightMainView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                appState.appTheme.isGlass
                    ? AnyView(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
                    : AnyView(Color(nsColor: appState.appTheme.workspaceBackground))
            )
        }
        .onAppear {
            loadRecentProjects()
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == .settings {
                appState.checkDerivedDataSize()
            }
        }
        .sheet(isPresented: $showCloneSheet) {
            cloneSheetView
        }
    }
    
    private func loadRecentProjects() {
        recentProjects = AppState.getRecentWorkspaces()
    }
    
    private func createProject(_ type: String) {
        let prompt: String
        switch type {
        case "nextjs":
            prompt = "Please scaffold a new Next.js 14 App (TypeScript, Tailwind CSS, App Router) in this workspace. Initialize standard project structure and packages."
        case "vite":
            prompt = "Please scaffold a new Vite + React + TypeScript web app in this workspace with Tailwind CSS and standard config."
        case "fastapi":
            prompt = "Please scaffold a modern Python 3.12 FastAPI project in this workspace with main.py, requirements.txt, Pydantic models, and sample endpoints."
        case "rust-axum":
            prompt = "Please initialize a new Rust Axum asynchronous web microservice in this workspace with Cargo.toml and src/main.rs."
        case "swift":
            prompt = "Please create a new native Apple macOS/iOS SwiftUI application in this workspace with Package.swift or Xcode structure."
        case "ardium":
            prompt = "Please create a new Ardium v2.3 project with CoreUI in this workspace."
        case "express":
            prompt = "Please scaffold a TypeScript Express.js REST API in this workspace with package.json, src/index.ts, and routing."
        case "go":
            prompt = "Please initialize a new Go microservice with Gin in this workspace with go.mod and main.go."
        case "flutter":
            prompt = "Please scaffold a cross-platform Flutter app in this workspace with pubspec.yaml and lib/main.dart."
        case "spring":
            prompt = "Please scaffold a Java 21 Spring Boot 3 microservice in this workspace with pom.xml and Application.java."
        case "pytorch":
            prompt = "Please scaffold a Python PyTorch machine learning pipeline in this workspace with model definition, train.py, and requirements.txt."
        case "docker":
            prompt = "Please generate a Dockerized multi-service development stack with docker-compose.yml, PostgreSQL, Redis, and sample API."
        case "vue":
            prompt = "Please scaffold a Vue 3 + Vite + TypeScript application in this workspace with App.vue and main.ts."
        case "nestjs":
            prompt = "Please scaffold a NestJS enterprise TypeScript API in this workspace with nest-cli config, modules, and controllers."
        default:
            prompt = "Please initialize a new \(type) project in this workspace."
        }
        selectFolderAndRunAI(prompt: prompt)
    }
    
    private func selectFolderAndRunAI(prompt: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = "Select a folder for the new project"
        panel.prompt = "Select Workspace"
        
        if panel.runModal() == .OK, let url = panel.url {
            AppState.recordRecentWorkspace(url: url)
            loadRecentProjects()
            appState.showingWelcomeHome = false
            Task { @MainActor in
                await appState.openWorkspace(url: url)
            }
            surface?.wrappedValue = .agent
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                appState.aiChatVisible = true
                Task {
                    await AgentService.shared.sendMessage(prompt)
                }
            }
        }
    }
    
    private func openFolder() {
        appState.openFolder()
    }

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.3.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) · Build \(build)"
    }
    
    // MARK: - Left Sidebar View
    
    private var leftSidebarView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MicroCode")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(appVersionString)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal)
            .padding(.top, 30)
            
            // Sidebar Menu
            VStack(spacing: 6) {
                sidebarButton(title: "Projects", icon: "folder", tab: .projects)
                sidebarButton(title: "Templates", icon: "square.grid.2x2", tab: .templates)
                sidebarButton(title: "AI Architect", icon: "sparkles", tab: .aiArchitect)
                sidebarButton(title: "Settings", icon: "gearshape", tab: .settings)
            }
            .padding(.horizontal, 10)
            
            Spacer()
            
            // Footer Info
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Silicon Native")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: 6, height: 6)
                    Text("LSP Services Active")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 25)
        }
        .frame(width: 210)
        .background(
            appState.appTheme.isGlass
                ? AnyView(VisualEffectView(material: .sidebar, blendingMode: .behindWindow).opacity(0.5))
                : AnyView(Color(nsColor: appState.appTheme.panelBackground))
        )
    }
    
    private func sidebarButton(title: String, icon: String, tab: WelcomeTab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                selectedTab == tab
                ? Color.primary.opacity(0.1)
                : Color.clear
            )
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Right Main View
    
    private var rightMainView: some View {
        ZStack {
            if selectedTab == .aiArchitect {
                AIAgentView(allowsChatSidebar: true)
                    .environmentObject(appState)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        switch selectedTab {
                        case .projects:
                            projectsTabContent
                        case .templates:
                            templatesTabContent
                        case .settings:
                            settingsTabContent
                        case .aiArchitect:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 35)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            appState.appTheme.isGlass
                ? AnyView(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
                : AnyView(Color(nsColor: appState.appTheme.workspaceBackground))
        )
    }
    
    // MARK: - Projects Tab
    
    private var projectsTabContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to MicroCode")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Start a new project, run interactive scratchpads, or connect remote cloud instances.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 6)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ], spacing: 14) {
                QuickActionCard(
                    title: "New Project",
                    subtitle: "Choose from 14+ boilerplates",
                    icon: "plus.square"
                ) {
                    selectedTab = .templates
                }
                
                QuickActionCard(
                    title: "Open Folder",
                    subtitle: "Open an existing workspace",
                    icon: "folder"
                ) {
                    openFolder()
                }
                
                QuickActionCard(
                    title: "Clone Repo",
                    subtitle: "Checkout from Git remote",
                    icon: "arrow.down.circle"
                ) {
                    showCloneSheet = true
                }
                
                QuickActionCard(
                    title: "New Playground Mode",
                    subtitle: "Scratchpad & live code execution",
                    icon: "play.laptopcomputer",
                    badge: "Instant"
                ) {
                    surface?.wrappedValue = .editor
                    appState.showingWelcomeHome = false
                    appState.setEditorMode(.playground)
                }
                
                QuickActionCard(
                    title: "New Cell Mode",
                    subtitle: "Multi-language interactive notebook",
                    icon: "square.split.1x2.fill",
                    badge: "Cells"
                ) {
                    surface?.wrappedValue = .editor
                    appState.showingWelcomeHome = false
                    appState.setEditorMode(.notebook)
                }
                
                QuickActionCard(
                    title: "SSH Remote Browser",
                    subtitle: "Cloud instances & remote shell",
                    icon: "terminal.fill",
                    badge: "Remote"
                ) {
                    surface?.wrappedValue = .editor
                    appState.showingWelcomeHome = false
                    appState.setEditorMode(.remoteX)
                }
                
                QuickActionCard(
                    title: "Embed & IoT Studio",
                    subtitle: "Hardware flashing, serial & GPIO monitor",
                    icon: "cpu.fill",
                    badge: "IoT"
                ) {
                    surface?.wrappedValue = .editor
                    appState.showingWelcomeHome = false
                    appState.setEditorMode(.embedded)
                }
                
                QuickActionCard(
                    title: "AI Architect",
                    subtitle: "Chat & autonomous scaffolding",
                    icon: "sparkles",
                    badge: "Agent"
                ) {
                    selectedTab = .aiArchitect
                }
                
                QuickActionCard(
                    title: "IDE Web Browser",
                    subtitle: "Built-in live browser & previews",
                    icon: "globe"
                ) {
                    surface?.wrappedValue = .editor
                    appState.showingWelcomeHome = false
                    appState.setEditorMode(.browser)
                }
                
                QuickActionCard(
                    title: "Settings & Cache",
                    subtitle: "Manage DerivedData & disk quotas",
                    icon: "gearshape"
                ) {
                    selectedTab = .settings
                }
            }
            
            VStack(alignment: .leading, spacing: 14) {
                Text("Recent Workspaces")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                
                if recentProjects.isEmpty || appState.simulateUnconnectedAI {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.7))
                        Text("No recent projects found")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(recentProjects.prefix(8), id: \.self) { url in
                            RecentProjectRow(url: url) {
                                surface?.wrappedValue = .editor
                                appState.showingWelcomeHome = false
                                Task { @MainActor in
                                    await appState.openWorkspace(url: url)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 10)
        }
    }
    
    // MARK: - Templates Tab
    
    private var templatesTabContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Select a Template")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Bootstrap projects instantly with built-in presets. Conforms strictly to your active theme.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                TemplateDetailCard(title: "Next.js 14 App", subtitle: "Fullstack React framework with App Router, TypeScript, and Server Components.", icon: "n.square.fill", tag: "Fullstack") { createProject("nextjs") }
                TemplateDetailCard(title: "Vite + React", subtitle: "Blazing fast frontend SPA with TypeScript and Hot Module Replacement.", icon: "atom", tag: "Frontend") { createProject("vite") }
                TemplateDetailCard(title: "FastAPI Backend", subtitle: "High-performance async Python API with Pydantic v2 and OpenAPI docs.", icon: "bolt.fill", tag: "Python") { createProject("fastapi") }
                TemplateDetailCard(title: "Rust Axum Service", subtitle: "Ultra-fast asynchronous microservice powered by Tokio runtime.", icon: "gearshape.2.fill", tag: "Rust") { createProject("rust-axum") }
                TemplateDetailCard(title: "SwiftUI App", subtitle: "Native Apple platforms application using SwiftUI declarative framework.", icon: "swift", tag: "Apple Native") { createProject("swift") }
                TemplateDetailCard(title: "Ardium CoreUI", subtitle: "High-performance native GUI using Dotmini's Ardium v2.3 language.", icon: "cpu.fill", tag: "Ardium") { createProject("ardium") }
                TemplateDetailCard(title: "Express.js API", subtitle: "Lightweight, scalable Node.js microservice API with TypeScript.", icon: "server.rack", tag: "Node.js") { createProject("express") }
                TemplateDetailCard(title: "Go Gin Microservice", subtitle: "High-throughput compiled HTTP web API with minimal footprint.", icon: "speedometer", tag: "Go") { createProject("go") }
                TemplateDetailCard(title: "Flutter Multiplatform", subtitle: "Cross-platform mobile, desktop, and web application with Dart.", icon: "apps.iphone", tag: "Dart") { createProject("flutter") }
                TemplateDetailCard(title: "Spring Boot 3", subtitle: "Enterprise-grade Java service with Spring MVC and Virtual Threads.", icon: "leaf.fill", tag: "Java") { createProject("spring") }
                TemplateDetailCard(title: "PyTorch / ML Pipeline", subtitle: "Machine learning training and inference pipeline with Apple MPS.", icon: "brain.head.profile", tag: "AI / ML") { createProject("pytorch") }
                TemplateDetailCard(title: "Docker Microservices", subtitle: "Production Docker compose stack with PostgreSQL and Redis.", icon: "shippingbox.fill", tag: "DevOps") { createProject("docker") }
                TemplateDetailCard(title: "Vue 3 + Vite", subtitle: "Lightweight reactive frontend with Pinia and Vue Router.", icon: "v.circle.fill", tag: "Frontend") { createProject("vue") }
                TemplateDetailCard(title: "NestJS Enterprise", subtitle: "Structured TypeScript enterprise architecture with dependency injection.", icon: "shield.fill", tag: "TypeScript") { createProject("nestjs") }
            }
        }
    }
    
    // MARK: - Settings Tab
    
    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workspace & Cache Settings")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
            
            Text("Manage temporary data, purge build caches, and configure disk quotas.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
    
    private var settingsCacheSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Derived Data Cache Size")
                    .font(.system(size: 14, weight: .semibold))
                if let info = appState.derivedDataInfo {
                    Text("\(String(format: "%.2f", Double(info.size_bytes) / (1024*1024*1024))) GB (\(info.folder_count) projects)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Text("Calculating size...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: { appState.clearDerivedData() }) {
                Text("Purge Cache")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            
            Button(action: { appState.checkDerivedDataSize() }) {
                Image(systemName: "arrow.clockwise")
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var settingsQuotaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disk Quota Limits")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            
            HStack {
                Text("DerivedData Quota:")
                Spacer()
                Slider(value: $appState.derivedDataQuotaLimitGB, in: 1...50, step: 1)
                    .frame(width: 200)
                Text("\(Int(appState.derivedDataQuotaLimitGB)) GB")
                    .frame(width: 50, alignment: .trailing)
            }
            
            Toggle("Enable Auto-Purge when quota is exceeded", isOn: $appState.enableDerivedDataAutoPurge)
                .toggleStyle(.checkbox)
            
            Toggle("Show warning notification when quota is exceeded", isOn: $appState.enableDerivedDataAlert)
                .toggleStyle(.checkbox)
        }
    }
    
    private var settingsTabContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsHeader
            
            VStack(alignment: .leading, spacing: 16) {
                settingsCacheSection
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                settingsQuotaSection
            }
            .padding(18)
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Git Clone Modal Sheet View
    
    private var cloneSheetView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Clone Repository")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Git Repository URL")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                TextField("https://github.com/username/project.git", text: $gitCloneUrl)
                    .textFieldStyle(.roundedBorder)
            }
            
            if let error = cloneError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.system(size: 12))
            }
            
            HStack {
                Button("Cancel") {
                    showCloneSheet = false
                    gitCloneUrl = ""
                    cloneError = nil
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: performClone) {
                    if isCloning {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    } else {
                        Text("Clone")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(gitCloneUrl.isEmpty || isCloning)
            }
        }
        .padding()
        .frame(width: 450)
    }
    
    private func performClone() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = "Select parent directory for cloned repository"
        panel.prompt = "Clone Here"
        
        if panel.runModal() == .OK, let parentUrl = panel.url {
            isCloning = true
            cloneError = nil
            
            let repoUrlStr = gitCloneUrl
            Task {
                do {
                    let repoName = repoUrlStr.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "cloned_repo"
                    let destUrl = parentUrl.appendingPathComponent(repoName)
                    
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                    process.arguments = ["clone", repoUrlStr, destUrl.path]
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        DispatchQueue.main.async {
                            self.appState.workspaceFolder = destUrl
                            self.showCloneSheet = false
                            self.isCloning = false
                            self.gitCloneUrl = ""
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.cloneError = "Git clone failed with status \(process.terminationStatus)"
                            self.isCloning = false
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.cloneError = error.localizedDescription
                        self.isCloning = false
                    }
                }
            }
        }
    }
}

struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    var badge: String? = nil
    var gradient: Gradient? = nil
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(isHovering ? 0.12 : 0.06))
                            .frame(width: 38, height: 38)
                        
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    
                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(
                Color.primary.opacity(isHovering ? 0.06 : 0.025)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        Color.primary.opacity(isHovering ? 0.25 : 0.08),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovering ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct TemplateDetailCard: View {
    let title: String
    let subtitle: String
    let icon: String
    var tag: String? = nil
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(isHovering ? 0.08 : 0.04))
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if let tag = tag {
                            Text(tag)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.primary.opacity(isHovering ? 0.06 : 0.025))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(isHovering ? 0.22 : 0.06), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct RecentProjectRow: View {
    let url: URL
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .foregroundColor(.primary.opacity(0.8))
                    .font(.system(size: 15))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text(url.deletingLastPathComponent().path)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(isHovering ? 0.06 : 0.02))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Inspector View

struct InspectorView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("GIT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { appState.gitRefresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if let status = appState.gitStatus {
                GitStatusView(status: status)
            } else {
                VStack {
                    Spacer()
                    Text("Not a repository")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct GitStatusView: View {
    let status: GitStatus
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Branch
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundColor(.accentColor)
                    Text(status.branch)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                
                // Changes
                if !status.files.isEmpty {
                    ForEach(status.files, id: \.path) { file in
                        HStack(spacing: 8) {
                            statusBadge(file.status)
                            Text(file.path)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                    }
                }
                
                // Actions
                HStack(spacing: 8) {
                    Button("Commit") { appState.showCommitDialog() }
                        .disabled(status.files.isEmpty)
                    Button("Push") { appState.gitPush() }
                    Button("Pull") { appState.gitPull() }
                }
                .padding(12)
            }
        }
    }
    
    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        let (color, letter): (Color, String) = {
            switch status {
            case "modified": return (.orange, "M")
            case "added": return (.green, "A")
            case "deleted": return (.red, "D")
            default: return (.gray, "?")
            }
        }()
        
        Text(letter)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .frame(width: 16, height: 16)
            .background(color)
            .cornerRadius(3)
    }
}

// MARK: - Sheets

struct RefactorSheet: View {
    @EnvironmentObject var appState: AppState
    @State private var instructions = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Refactor with AI")
                .font(.headline)
            
            TextEditor(text: $instructions)
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Refactor") {
                    Task {
                        await appState.refactorCode(instructions: instructions)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(instructions.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

struct CommitSheet: View {
    @EnvironmentObject var appState: AppState
    @State private var message = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Commit Changes")
                .font(.headline)
            
            TextField("Commit message", text: $message)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Commit") {
                    Task {
                        await appState.commitChanges(message: message)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(message.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - New File Sheet

enum LanguageCategory: String, CaseIterable {
    case popular = "Popular"
    case web = "Web"
    case systems = "Systems"
    case data = "Data"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .popular: return "star.fill"
        case .web: return "globe"
        case .systems: return "cpu"
        case .data: return "chart.bar.doc.horizontal"
        case .other: return "ellipsis.circle"
        }
    }
}

struct LanguageInfo: Identifiable {
    let id: String
    let name: String
    let icon: String
    let ext: String
    let category: LanguageCategory
    let color: Color
}

struct NewFileSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var filename: String = ""
    @State private var selectedLanguage: String = "swift"
    @State private var selectedCategory: LanguageCategory = .popular
    @State private var saveLocation: SaveLocation = .workspaceRoot
    
    enum SaveLocation: String, CaseIterable {
        case workspaceRoot = "Workspace Root"
        case currentFolder = "Current Folder"
        case custom = "Choose Location..."
        
        var icon: String {
            switch self {
            case .workspaceRoot: return "folder.badge.gearshape"
            case .currentFolder: return "folder"
            case .custom: return "folder.badge.questionmark"
            }
        }
    }
    
    @State private var customLanguageName: String = ""
    @State private var customLanguageExt: String = ""
    @State private var showCustomInput: Bool = false
    
    private let languages: [LanguageInfo] = [
        // Popular
        LanguageInfo(id: "swift", name: "Swift", icon: "swift", ext: "swift", category: .popular, color: .orange),
        LanguageInfo(id: "python", name: "Python", icon: "text.word.spacing", ext: "py", category: .popular, color: Color(red: 0.2, green: 0.6, blue: 0.9)),
        LanguageInfo(id: "javascript", name: "JavaScript", icon: "j.square.fill", ext: "js", category: .popular, color: .yellow),
        LanguageInfo(id: "typescript", name: "TypeScript", icon: "t.square.fill", ext: "ts", category: .popular, color: Color(red: 0.2, green: 0.5, blue: 0.9)),
        LanguageInfo(id: "rust", name: "Rust", icon: "gearshape.2.fill", ext: "rs", category: .popular, color: Color(red: 0.85, green: 0.4, blue: 0.2)),
        LanguageInfo(id: "go", name: "Go", icon: "g.square.fill", ext: "go", category: .popular, color: .cyan),
        LanguageInfo(id: "java", name: "Java", icon: "cup.and.saucer.fill", ext: "java", category: .popular, color: Color(red: 0.9, green: 0.4, blue: 0.2)),
        LanguageInfo(id: "kotlin", name: "Kotlin", icon: "k.square.fill", ext: "kt", category: .popular, color: Color(red: 0.5, green: 0.3, blue: 0.9)),
        LanguageInfo(id: "csharp", name: "C#", icon: "number.square.fill", ext: "cs", category: .popular, color: Color(red: 0.4, green: 0.2, blue: 0.7)),
        LanguageInfo(id: "dart", name: "Dart", icon: "d.square.fill", ext: "dart", category: .popular, color: Color(red: 0.0, green: 0.7, blue: 0.8)),
        LanguageInfo(id: "ardium", name: "Ardium", icon: "a.square.fill", ext: "ar", category: .popular, color: Color(red: 0.9, green: 0.2, blue: 0.4)),
        
        // Web
        LanguageInfo(id: "html", name: "HTML", icon: "chevron.left.forwardslash.chevron.right", ext: "html", category: .web, color: .orange),
        LanguageInfo(id: "css", name: "CSS", icon: "paintbrush.fill", ext: "css", category: .web, color: Color(red: 0.2, green: 0.5, blue: 0.9)),
        LanguageInfo(id: "jsx", name: "React JSX", icon: "atom", ext: "jsx", category: .web, color: .cyan),
        LanguageInfo(id: "tsx", name: "React TSX", icon: "atom", ext: "tsx", category: .web, color: Color(red: 0.2, green: 0.5, blue: 0.9)),
        LanguageInfo(id: "vue", name: "Vue", icon: "v.square.fill", ext: "vue", category: .web, color: .green),
        LanguageInfo(id: "svelte", name: "Svelte", icon: "s.square.fill", ext: "svelte", category: .web, color: Color(red: 1.0, green: 0.25, blue: 0.0)),
        LanguageInfo(id: "php", name: "PHP", icon: "p.square.fill", ext: "php", category: .web, color: Color(red: 0.5, green: 0.4, blue: 0.7)),
        LanguageInfo(id: "sass", name: "SASS/SCSS", icon: "paintbrush.pointed.fill", ext: "scss", category: .web, color: Color(red: 0.8, green: 0.3, blue: 0.5)),
        LanguageInfo(id: "solidity", name: "Solidity", icon: "cube.fill", ext: "sol", category: .web, color: .gray),
        
        // Systems
        LanguageInfo(id: "c", name: "C", icon: "c.square.fill", ext: "c", category: .systems, color: .gray),
        LanguageInfo(id: "cpp", name: "C++", icon: "plus.square.fill", ext: "cpp", category: .systems, color: Color(red: 0.2, green: 0.5, blue: 0.8)),
        LanguageInfo(id: "objective-c", name: "Objective-C", icon: "m.square.fill", ext: "m", category: .systems, color: .blue),
        LanguageInfo(id: "zig", name: "Zig", icon: "z.square.fill", ext: "zig", category: .systems, color: Color(red: 0.95, green: 0.7, blue: 0.0)),
        LanguageInfo(id: "assembly", name: "Assembly", icon: "memorychip.fill", ext: "s", category: .systems, color: .gray),
        LanguageInfo(id: "metal", name: "Metal", icon: "cube.transparent.fill", ext: "metal", category: .systems, color: .purple),
        LanguageInfo(id: "vala", name: "Vala", icon: "v.circle.fill", ext: "vala", category: .systems, color: .purple),
        LanguageInfo(id: "nim", name: "Nim", icon: "n.square.fill", ext: "nim", category: .systems, color: .yellow),
        LanguageInfo(id: "haskell", name: "Haskell", icon: "h.square.fill", ext: "hs", category: .systems, color: Color(red: 0.4, green: 0.3, blue: 0.6)),
        
        // Data & Scripting
        LanguageInfo(id: "r", name: "R", icon: "r.square.fill", ext: "r", category: .data, color: Color(red: 0.2, green: 0.5, blue: 0.8)),
        LanguageInfo(id: "julia", name: "Julia", icon: "j.circle.fill", ext: "jl", category: .data, color: Color(red: 0.6, green: 0.2, blue: 0.8)),
        LanguageInfo(id: "lua", name: "Lua", icon: "moon.fill", ext: "lua", category: .data, color: Color(red: 0.0, green: 0.0, blue: 0.6)),
        LanguageInfo(id: "ruby", name: "Ruby", icon: "diamond.fill", ext: "rb", category: .data, color: .red),
        LanguageInfo(id: "perl", name: "Perl", icon: "p.circle.fill", ext: "pl", category: .data, color: Color(red: 0.2, green: 0.3, blue: 0.6)),
        LanguageInfo(id: "elixir", name: "Elixir", icon: "drop.fill", ext: "ex", category: .data, color: Color(red: 0.4, green: 0.2, blue: 0.6)),
        LanguageInfo(id: "sql", name: "SQL", icon: "cylinder.fill", ext: "sql", category: .data, color: Color(red: 0.2, green: 0.5, blue: 0.8)),
        LanguageInfo(id: "json", name: "JSON", icon: "curlybraces", ext: "json", category: .data, color: .gray),
        LanguageInfo(id: "yaml", name: "YAML", icon: "list.bullet.indent", ext: "yaml", category: .data, color: Color(red: 0.8, green: 0.2, blue: 0.2)),
        LanguageInfo(id: "xml", name: "XML", icon: "chevron.left.forwardslash.chevron.right", ext: "xml", category: .data, color: .green),
        LanguageInfo(id: "toml", name: "TOML", icon: "doc.plaintext.fill", ext: "toml", category: .data, color: .gray),
        LanguageInfo(id: "graphql", name: "GraphQL", icon: "point.3.connected.trianglepath.dotted", ext: "graphql", category: .data, color: .pink),
        LanguageInfo(id: "matlab", name: "MATLAB", icon: "function", ext: "m", category: .data, color: .orange),
        LanguageInfo(id: "prolog", name: "Prolog", icon: "questionmark.square.fill", ext: "pl", category: .data, color: .orange),
        
        // Other
        LanguageInfo(id: "scala", name: "Scala", icon: "s.circle.fill", ext: "scala", category: .other, color: .red),
        LanguageInfo(id: "fsharp", name: "F#", icon: "f.square.fill", ext: "fs", category: .other, color: .cyan),
        LanguageInfo(id: "ocaml", name: "OCaml", icon: "o.square.fill", ext: "ml", category: .other, color: .orange),
        LanguageInfo(id: "erlang", name: "Erlang", icon: "e.square.fill", ext: "erl", category: .other, color: Color(red: 0.6, green: 0.1, blue: 0.2)),
        LanguageInfo(id: "clojure", name: "Clojure", icon: "circle.grid.cross.fill", ext: "clj", category: .other, color: .green),
        LanguageInfo(id: "markdown", name: "Markdown", icon: "doc.richtext.fill", ext: "md", category: .other, color: .gray),
        LanguageInfo(id: "text", name: "Plain Text", icon: "doc.text.fill", ext: "txt", category: .other, color: .gray),
        LanguageInfo(id: "shell", name: "Shell Script", icon: "terminal.fill", ext: "sh", category: .other, color: .green),
        LanguageInfo(id: "dockerfile", name: "Dockerfile", icon: "shippingbox.fill", ext: "dockerfile", category: .other, color: Color(red: 0.2, green: 0.5, blue: 0.9)),
        LanguageInfo(id: "latex", name: "LaTeX", icon: "textformat", ext: "tex", category: .other, color: Color(red: 0.0, green: 0.4, blue: 0.3)),
        LanguageInfo(id: "makefile", name: "Makefile", icon: "wrench.and.screwdriver.fill", ext: "makefile", category: .other, color: .gray),
    ]
    
    private var filteredLanguages: [LanguageInfo] {
        languages.filter { $0.category == selectedCategory }
    }
    
    private var selectedLangInfo: LanguageInfo? {
        languages.first { $0.id == selectedLanguage }
    }
    
    private var fileExtension: String {
        if selectedLanguage.hasPrefix("custom_") {
            return customLanguageExt.isEmpty ? "txt" : customLanguageExt
        }
        return selectedLangInfo?.ext ?? "txt"
    }
    
    private var previewFilename: String {
        let name = filename.isEmpty ? "Untitled" : filename
        if name.contains(".") { return name }
        return "\(name).\(fileExtension)"
    }
    
    var body: some View {
        ToolWindowWrapper(
            title: "New File",
            subtitle: "Create a new source file",
            icon: "doc.badge.plus",
            iconColor: .blue
        ) {
            HStack(spacing: 0) {
                // Left: Language Selection
                VStack(alignment: .leading, spacing: 0) {
                    // Category Tabs
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(LanguageCategory.allCases, id: \.self) { category in
                                CategoryTab(
                                    category: category,
                                    isSelected: selectedCategory == category
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedCategory = category
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    
                    Divider()
                    
                    // Language Grid
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            ForEach(filteredLanguages) { lang in
                                NewFileLanguageCard(
                                    language: lang,
                                    isSelected: selectedLanguage == lang.id
                                ) {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedLanguage = lang.id
                                        showCustomInput = false
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        
                        // Custom Language
                        VStack(spacing: 8) {
                            Divider()
                                .padding(.horizontal, 4)
                            
                            if showCustomInput {
                                VStack(spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.square.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                        Text("Custom Language")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    
                                    HStack(spacing: 6) {
                                        TextField("Name", text: $customLanguageName)
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 11))
                                            .padding(6)
                                            .background(Color(white: 0.1))
                                            .cornerRadius(5)
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                                        
                                        TextField("ext", text: $customLanguageExt)
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 11, design: .monospaced))
                                            .padding(6)
                                            .background(Color(white: 0.1))
                                            .cornerRadius(5)
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 1))
                                            .frame(width: 60)
                                    }
                                    
                                    if !customLanguageName.isEmpty && !customLanguageExt.isEmpty {
                                        Button {
                                            selectedLanguage = "custom_\(customLanguageName.lowercased())"
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 9, weight: .bold))
                                                Text("Use \(customLanguageName)")
                                                    .font(.system(size: 10, weight: .medium))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color(white: 0.2))
                                            .cornerRadius(5)
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.12), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(10)
                                .background(Color(white: 0.08))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
                            } else {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showCustomInput = true
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 12))
                                        Text("Custom Language...")
                                            .font(.system(size: 11))
                                    }
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                }
                .frame(width: 340)
                .background(Color(white: 0.06))
                
                Divider()
                
                // Right: File Details & Preview
                VStack(alignment: .leading, spacing: 20) {
                    // Filename Input
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Filename", systemImage: "doc")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        HStack {
                            TextField("Untitled", text: $filename)
                                .textFieldStyle(.roundedBorder)
                            
                            Text(".\(fileExtension)")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                        }
                        
                        Text(previewFilename)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                    
                    Divider()
                    
                    // Save Location
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Location", systemImage: "folder")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $saveLocation) {
                            ForEach(SaveLocation.allCases, id: \.self) { loc in
                                Label(loc.rawValue, systemImage: loc.icon).tag(loc)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        
                        if let workspace = appState.workspaceFolder {
                            Text(workspace.lastPathComponent)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            Text("No workspace open")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Divider()
                    
                    // Template Preview
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Template Preview", systemImage: "doc.text")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if let lang = selectedLangInfo {
                                HStack(spacing: 4) {
                                    Image(systemName: lang.icon)
                                        .font(.system(size: 10))
                                    Text(lang.name)
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(lang.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(lang.color.opacity(0.1))
                                .cornerRadius(4)
                            }
                        }
                        
                        ScrollView {
                            Text(templatePreview)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .frame(maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    
                    Spacer(minLength: 0)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        } footer: {
            HStack {
                if let lang = selectedLangInfo {
                    HStack(spacing: 6) {
                        Image(systemName: lang.icon)
                            .foregroundColor(lang.color)
                        Text("\(lang.name) file")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Create File") {
                    appState.createNewFileWithLanguage(name: filename, language: selectedLanguage)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    private var templatePreview: String {
        switch selectedLanguage {
        case "swift":
            return "import Foundation\n\n// MARK: - Main\n\nfunc main() {\n    print(\"Hello, World!\")\n}\n\nmain()"
        case "python":
            return "#!/usr/bin/env python3\n\"\"\"Module description.\"\"\"\n\ndef main():\n    \"\"\"Main entry point.\"\"\"\n    print(\"Hello, World!\")\n\nif __name__ == \"__main__\":\n    main()"
        case "javascript":
            return "// @ts-check\n\"use strict\";\n\n/**\n * Main function\n */\nfunction main() {\n    console.log(\"Hello, World!\");\n}\n\nmain();"
        case "typescript":
            return "/**\n * Main function\n */\nfunction main(): void {\n    console.log(\"Hello, World!\");\n}\n\nmain();"
        case "rust":
            return "//! Module documentation\n\nfn main() {\n    println!(\"Hello, World!\");\n}"
        case "go":
            return "package main\n\nimport \"fmt\"\n\nfunc main() {\n    fmt.Println(\"Hello, World!\")\n}"
        case "html":
            return "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n    <meta charset=\"UTF-8\">\n    <title>Document</title>\n</head>\n<body>\n    <h1>Hello, World!</h1>\n</body>\n</html>"
        case "css":
            return "/* Styles */\n\n:root {\n    --primary: #007AFF;\n}\n\nbody {\n    font-family: system-ui;\n    margin: 0;\n    padding: 0;\n}"
        case "json":
            return "{\n    \"name\": \"project\",\n    \"version\": \"1.0.0\"\n}"
        case "markdown":
            return "# Title\n\nDescription of the document.\n\n## Section\n\nContent here."
        case "shell":
            return "#!/bin/bash\n\n# Script description\n\necho \"Hello, World!\""
        case "c":
            return "#include <stdio.h>\n\nint main() {\n    printf(\"Hello, World!\\n\");\n    return 0;\n}"
        case "cpp":
            return "#include <iostream>\n\nint main() {\n    std::cout << \"Hello, World!\" << std::endl;\n    return 0;\n}"
        case "java":
            return "public class Main {\n    public static void main(String[] args) {\n        System.out.println(\"Hello, World!\");\n    }\n}"
        case "kotlin":
            return "fun main() {\n    println(\"Hello, World!\")\n}"
        case "sql":
            return "-- SQL Query\n\nSELECT * FROM table_name\nWHERE condition = true;"
        case "yaml":
            return "# Configuration\n\nname: project\nversion: 1.0.0\n\nsettings:\n  debug: true"
        default:
            return "// New file"
        }
    }
}

// MARK: - Category Tab

struct CategoryTab: View {
    let category: LanguageCategory
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: category.icon)
                    .font(.system(size: 10))
                Text(category.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color(white: 0.2) : (isHovering ? Color(white: 0.12) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.15) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Language Card

struct NewFileLanguageCard: View {
    let language: LanguageInfo
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? language.color.opacity(0.2) : Color(white: 0.12))
                        .frame(width: 34, height: 34)
                    
                    Image(systemName: language.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isSelected ? language.color : language.color.opacity(0.8))
                }
                
                // Info
                VStack(alignment: .leading, spacing: 1) {
                    Text(language.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(".\(language.ext)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(language.color)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? language.color.opacity(0.08) : (isHovering ? Color(white: 0.14) : Color(white: 0.09)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? language.color.opacity(0.5) : (isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isHovering)
    }
}

// MARK: - AI Chat Panel

struct AIChatPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var inputMessage: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("AI Assistant")
                        .font(.system(size: 13, weight: .semibold))
                }
                
                Spacer()
                
                // Agent Mode Toggle
                Toggle(isOn: $appState.agentMode) {
                    Text(appState.agentMode ? "Agent Active" : "Agent Mode")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(appState.agentMode ? .primary : .secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Enable Agent Mode for autonomous coding assistance")
                
                // Divider
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: 16)
                
                // Model Selector Pill
                Menu {
                    let activeProviders = AIModelCatalog.shared.providers.filter { $0.id != "omni" && !(appState.apiKeys[$0.id]?.isEmpty ?? true) }
                    let providersToDisplay = activeProviders.isEmpty ? AIModelCatalog.shared.providers.filter { $0.id != "omni" } : activeProviders
                    ForEach(providersToDisplay) { prov in
                        Section(prov.name) {
                            ForEach(prov.models) { m in
                                Button(m.name) {
                                    setModel(m.id, provider: prov.id)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(modelDisplayName)
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .frame(width: 140, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(nsColor: .separatorColor).opacity(0.1)),
                alignment: .bottom
            )
            
            Divider()
            
            // Pending Actions
            if !appState.pendingActions.filter({ !$0.isApproved && !$0.isRejected }).isEmpty {
                VStack(spacing: 4) {
                    Text("PENDING ACTIONS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    ForEach(appState.pendingActions.filter({ !$0.isApproved && !$0.isRejected })) { action in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.description)
                                    .font(.system(size: 11, weight: .medium))
                                Text(action.filePath)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button {
                                appState.approveAction(action)
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                            .help("Apply changes")
                            
                            Button {
                                appState.rejectAction(action)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Reject changes")
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()
            }
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(appState.aiChatMessages) { message in
                            ChatMessageView(message: message)
                                .id(message.id)
                        }
                        
                        // Floating Thinking Indicator (New)
                        if appState.isLoading && appState.aiChatMessages.last?.role == .user {
                            ThinkingIndicatorView()
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: appState.aiChatMessages.count) { _ in
                    if let lastMessage = appState.aiChatMessages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: appState.aiChatMessages.last?.content) { _ in
                    if let lastMessage = appState.aiChatMessages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Input
            HStack(spacing: 8) {
                TextField("Ask AI anything...", text: $inputMessage)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    .onSubmit {
                        sendMessage()
                    }
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(inputMessage.isEmpty ? .secondary.opacity(0.5) : .accentColor)
                        .shadow(color: inputMessage.isEmpty ? .clear : .accentColor.opacity(0.3), radius: 2)
                }
                .buttonStyle(.plain)
                .disabled(inputMessage.isEmpty || appState.isLoading)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private var modelDisplayName: String {
        if let m = AIModelCatalog.shared.model(id: appState.aiModel) {
            return m.fullDisplayName
        }
        return AIModelCatalog.formatFullDisplayName(provider: appState.aiProvider, modelId: appState.aiModel)
    }
    
    private func setModel(_ model: String, provider: String) {
        appState.aiModel = model
        appState.aiProvider = provider
        UserDefaults.standard.set(model, forKey: "aiModel")
        UserDefaults.standard.set(provider, forKey: "aiProvider")
    }
    
    private func sendMessage() {
        guard !inputMessage.isEmpty else { return }
        let message = inputMessage
        inputMessage = ""
        appState.sendChatMessage(message)
    }
}

struct ChatMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer()
            } else {
                // Avatar for AI
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .padding(.top, 4)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Thinking indicator (inline for assistant)
                if message.isThinking {
                    HStack(spacing: 5) {
                        Text("Thinking...")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }

                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 13))
                        .compatTextSelection()
                        .padding(10)
                        .background(backgroundColor)
                        .foregroundColor(foregroundColor)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
                }
                
                // Enhanced Tool Calls display
                if !message.toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(message.toolCalls, id: \.id) { tool in
                            HStack {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                
                                Text("\(tool.name)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                
                                Spacer()
                                
                                if let result = message.toolResults.first(where: { $0.tool_call_id == tool.id }) {
                                    if result.success {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 10))
                                    } else {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.system(size: 10))
                                    }
                                } else if !message.isThinking {
                                     ProgressView().scaleEffect(0.4)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                    )
                            )
                        }
                    }
                }

                Text(timeString)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role != .user {
                Spacer()
            }
        }
    }
    
    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor
        case .assistant:
            return Color(nsColor: .controlBackgroundColor)
        case .system:
            return Color.orange.opacity(0.1)
        }
    }
    
    private var foregroundColor: Color {
        message.role == .user ? .white : .primary
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.timestamp)
    }
}

// MARK: - New Components

// AgentBrainDashboard and DashboardTabBtn removed — Task Windows deprecated

struct ThinkingIndicatorView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 6) {
            Text("Working.")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundColor(.secondary.opacity(0.75))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1))
        )
    }
}

