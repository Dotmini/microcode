//
//  EmbeddedAIAgentPanel.swift
//  MicroCode
//
//  Dedicated Hardware & Firmware AI Agent for Embedded Studio
//  Context-aware: understands Target Board, Serial Ports, FreeRTOS, ESP-IDF, Pinouts, and Compiler Logs
//
//  Created by Dotmini Company Limited
//  Monochrome Minimalist Black & White Xcode Pro Style
//

import SwiftUI
import Combine

// MARK: - Models for Embedded AI

struct EmbeddedAIMessage: Identifiable, Equatable {
    let id: String
    let role: Role
    var content: String
    let timestamp: Date
    
    enum Role: String {
        case user
        case assistant
        case system
    }
    
    init(id: String = UUID().uuidString, role: Role, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
    
    static func == (lhs: EmbeddedAIMessage, rhs: EmbeddedAIMessage) -> Bool {
        lhs.id == rhs.id && lhs.role == rhs.role && lhs.content == rhs.content
    }
}

struct EmbeddedAISuggestion: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let prompt: String
}

// MARK: - Embedded AI View Model

@MainActor
final class EmbeddedAIAgentViewModel: ObservableObject {
    @Published var messages: [EmbeddedAIMessage] = []
    @Published var isLoading: Bool = false
    @Published var currentStatus: String = ""
    @Published var lastAppliedNotice: String? = nil
    
    func cancelStream() {
        AIClient.shared.cancelStream()
        isLoading = false
        currentStatus = ""
    }
    
    func clearMessages() {
        cancelStream()
        messages.removeAll()
    }
    
    func triggerNotice(_ text: String) {
        lastAppliedNotice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.lastAppliedNotice == text {
                self?.lastAppliedNotice = nil
            }
        }
    }
    
    func sendMessage(
        text: String,
        systemPrompt: String,
        provider: StreamableAIProvider,
        model: String,
        apiKey: String
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        messages.append(EmbeddedAIMessage(role: .user, content: trimmed))
        
        isLoading = true
        currentStatus = "Analyzing hardware architecture..."
        
        let responseId = UUID().uuidString
        messages.append(EmbeddedAIMessage(id: responseId, role: .assistant, content: ""))
        
        let history: [(role: String, content: String)] = messages.dropLast(2).map {
            (role: $0.role.rawValue, content: $0.content)
        }
        
        AIClient.shared.sendMessage(
            prompt: trimmed,
            attachments: [],
            systemPrompt: systemPrompt,
            conversationHistory: history,
            provider: provider,
            model: model,
            apiKey: apiKey,
            onToken: { [weak self] token in
                guard let self = self else { return }
                if let idx = self.messages.firstIndex(where: { $0.id == responseId }) {
                    let prev = self.messages[idx].content
                    self.messages[idx] = EmbeddedAIMessage(
                        id: responseId,
                        role: .assistant,
                        content: prev + token,
                        timestamp: self.messages[idx].timestamp
                    )
                }
                if self.isLoading && !self.currentStatus.isEmpty {
                    self.currentStatus = "Streaming response..."
                }
            },
            onComplete: { [weak self] _ in
                guard let self = self else { return }
                self.isLoading = false
                self.currentStatus = ""
            },
            onError: { [weak self] error in
                guard let self = self else { return }
                if let idx = self.messages.firstIndex(where: { $0.id == responseId }) {
                    self.messages[idx] = EmbeddedAIMessage(
                        id: responseId,
                        role: .assistant,
                        content: "❌ AI Error: \(error)\n\nPlease verify your API key or model configuration in MicroCode Settings.",
                        timestamp: self.messages[idx].timestamp
                    )
                }
                self.isLoading = false
                self.currentStatus = ""
            }
        )
    }
}

// MARK: - Embedded AI Agent Panel

struct EmbeddedAIAgentPanel: View {
    @Binding var isShowing: Bool
    @Binding var editorSourceCode: String
    let selectedBoard: HardwareBoardTarget
    let selectedPort: RealSerialPort?
    let editorLanguage: EmbeddedSourceLanguage
    let buildLogOutput: String
    let consoleEntries: [SerialConsoleEntry]
    @ObservedObject var envManager: EmbeddedEnvManager
    
    @EnvironmentObject var appState: AppState
    @ObservedObject private var modelCatalog = AIModelCatalog.shared
    @StateObject private var viewModel = EmbeddedAIAgentViewModel()
    
    @State private var inputText: String = ""
    @State private var attachHardwareContext: Bool = true
    @FocusState private var isInputFocused: Bool
    
    private var isDark: Bool { appState.appTheme.isDark }
    private var panelBg: Color { isDark ? Color.black : Color(white: 0.98) }
    private var headerBg: Color { isDark ? Color(white: 0.05) : Color(white: 0.93) }
    private var stripBg: Color { isDark ? Color(white: 0.03) : Color(white: 0.95) }
    private var cardBg: Color { isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04) }
    private var cardBorderColor: Color { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.10) }
    private var dividerLineColor: Color { isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08) }
    
    // Dynamic suggestions based on current hardware and compilation state
    private var suggestions: [EmbeddedAISuggestion] {
        var list: [EmbeddedAISuggestion] = []
        
        let hasBuildError = buildLogOutput.contains("error:") || buildLogOutput.contains("[ERROR]")
        let hasGuruMeditation = consoleEntries.contains(where: { $0.content.contains("Guru Meditation") || $0.content.contains("Backtrace:") })
        
        if hasBuildError {
            list.append(EmbeddedAISuggestion(
                icon: "wrench.and.screwdriver.fill",
                text: "Fix Compiler Error",
                prompt: "Please analyze my compilation error log and provide the exact fixed code for my current sketch."
            ))
        }
        
        if hasGuruMeditation {
            list.append(EmbeddedAISuggestion(
                icon: "stethoscope",
                text: "Decode Crash Backtrace",
                prompt: "My board encountered a Guru Meditation / Crash Backtrace in the serial log. Please decode what caused this crash and fix the sketch."
            ))
        }
        
        list.append(EmbeddedAISuggestion(
            icon: "cpu.fill",
            text: "FreeRTOS Dual-Core Tasks",
            prompt: "Write a complete \(editorLanguage.rawValue) FreeRTOS example for \(selectedBoard.rawValue) with two pinned tasks communicating via a FreeRTOS Queue."
        ))
        
        list.append(EmbeddedAISuggestion(
            icon: "wave.3.right.circle.fill",
            text: "I2C Sensor Driver",
            prompt: "Generate an I2C sensor reading routine for \(selectedBoard.rawValue) with error checking and timeout handling."
        ))
        
        list.append(EmbeddedAISuggestion(
            icon: "bolt.batteryblock.fill",
            text: "Deep Sleep & Low Power",
            prompt: "Show how to configure \(selectedBoard.rawValue) for ultra-low power deep sleep with timer and GPIO wakeup triggers."
        ))
        
        list.append(EmbeddedAISuggestion(
            icon: "network",
            text: "WiFi & MQTT Telemetry",
            prompt: "Provide a robust WiFi reconnection loop and MQTT publisher for \(selectedBoard.rawValue)."
        ))
        
        return list
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            panelHeader
            
            Rectangle().fill(dividerLineColor).frame(height: 1)
            
            // Live Hardware Context Strip
            hardwareContextStrip
            
            Rectangle().fill(dividerLineColor).frame(height: 1)
            
            // Notification pill (e.g. "Sketch Replaced!")
            if let notice = viewModel.lastAppliedNotice {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(isDark ? .white : .black)
                    Text(notice)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(isDark ? .white : .black)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                .transition(.opacity)
            }
            
            // Message Feed
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        Color.clear.frame(height: 1).id("TOP_AI_ANCHOR")
                        
                        if viewModel.messages.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(viewModel.messages) { msg in
                                EmbeddedAIMessageRow(
                                    message: msg,
                                    isLoading: viewModel.isLoading,
                                    isDark: isDark,
                                    onReplaceSketch: { code in
                                        editorSourceCode = code
                                        envManager.analyzeIncludes(code: code)
                                        envManager.autoResolveAndInstallDependencies(code: code)
                                        viewModel.triggerNotice("Code applied directly to Sketch!")
                                    },
                                    onAppendSketch: { code in
                                        editorSourceCode += "\n\n" + code
                                        envManager.analyzeIncludes(code: editorSourceCode)
                                        envManager.autoResolveAndInstallDependencies(code: editorSourceCode)
                                        viewModel.triggerNotice("Code appended to Sketch!")
                                    }
                                )
                                .id(msg.id)
                            }
                        }
                        
                        if viewModel.isLoading && (viewModel.messages.last?.role != .assistant || viewModel.messages.last?.content.isEmpty == false) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                                Text(viewModel.currentStatus.isEmpty ? "Generating embedded solution..." : viewModel.currentStatus)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(isDark ? Color(white: 0.7) : Color(white: 0.3))
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .id("AI_LOADING_INDICATOR")
                        }
                        
                        Color.clear.frame(height: 1).id("BOTTOM_AI_ANCHOR")
                    }
                    .padding(12)
                }
                .onChange(of: viewModel.messages.count) { count in
                    withAnimation {
                        if count == 0 {
                            proxy.scrollTo("TOP_AI_ANCHOR", anchor: .top)
                        } else {
                            proxy.scrollTo("BOTTOM_AI_ANCHOR", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.messages.last?.content) { _ in
                    proxy.scrollTo("BOTTOM_AI_ANCHOR", anchor: .bottom)
                }
                .onChange(of: viewModel.isLoading) { loading in
                    if loading {
                        withAnimation {
                            proxy.scrollTo("BOTTOM_AI_ANCHOR", anchor: .bottom)
                        }
                    }
                }
            }
            
            // Quick Suggestion Chips (horizontal scroll - only show when conversation has started)
            if !viewModel.messages.isEmpty {
                quickSuggestionsBar
                Rectangle().fill(dividerLineColor).frame(height: 1)
            }
            
            // Prompt Input Bar
            promptInputBar
        }
        .background(panelBg)
    }
    
    // MARK: - Header
    
    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile.fill")
                .font(.system(size: 12))
                .foregroundColor(isDark ? .white : .black)
            
            Text("EMBEDDED AI AGENT")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isDark ? .white : .black)
            
            if ProjectMemoryService.shared.isLoaded {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .help("Project Memory Loaded")
            }
            
            Spacer()
            
            // Model selector menu
            modelSelectorMenu
            
            // Clear Chat
            Button(action: {
                withAnimation {
                    viewModel.clearMessages()
                    inputText = ""
                }
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(isDark ? Color(white: 0.5) : Color(white: 0.5))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Clear Chat History")
            
            // Close Panel
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isShowing = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isDark ? Color(white: 0.6) : Color(white: 0.4))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Close AI Agent Panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(headerBg)
    }
    
    private var modelSelectorMenu: some View {
        Menu {
            let keyMode = UserDefaults.standard.string(forKey: "aiKeyMode") ?? "direct"
            
            if keyMode == "subscription" {
                if SubscriptionAuthManager.shared.hasAnyConnected {
                    let connectedProviders = SubscriptionAuthManager.shared.connectedProviders()
                    ForEach(connectedProviders) { prov in
                        Menu(prov.displayName) {
                            ForEach(prov.modelInfos) { subModel in
                                Button(action: {
                                    appState.aiProvider = subModel.aiProviderID
                                    appState.aiModel = subModel.modelID
                                    SubscriptionAuthManager.shared.activeProvider = subModel.provider
                                    UserDefaults.standard.set(subModel.provider.rawValue, forKey: "subscriptionActiveProvider")
                                    UserDefaults.standard.set("subscription", forKey: "aiKeyMode")
                                    appState.saveSettings()
                                }) {
                                    HStack {
                                        Text(subModel.name)
                                        if appState.aiModel == subModel.modelID {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Button(action: {
                        UserDefaults.standard.set("direct", forKey: "aiKeyMode")
                        appState.saveSettings()
                    }) {
                        Label("Switch to Direct API Key (BYOK)", systemImage: "key.fill")
                    }
                }
            } else {
                let byokProviders = modelCatalog.providers.filter { $0.id != "omni" && !(appState.apiKeys[$0.id]?.isEmpty ?? true) }
                let displayProviders = byokProviders.isEmpty ? modelCatalog.providers : byokProviders
                
                ForEach(displayProviders) { prov in
                    Menu(prov.name) {
                        ForEach(prov.models) { model in
                            Button(action: {
                                appState.aiProvider = prov.id
                                appState.aiModel = model.id
                                if prov.id == "omni" {
                                    UserDefaults.standard.set("cloud", forKey: "aiKeyMode")
                                } else {
                                    UserDefaults.standard.set("direct", forKey: "aiKeyMode")
                                }
                                appState.saveSettings()
                            }) {
                                HStack {
                                    Text(model.name)
                                    if appState.aiModel == model.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(shortModelName(currentModelName).uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(isDark ? Color(white: 0.8) : Color(white: 0.2))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(isDark ? Color(white: 0.5) : Color(white: 0.5))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(cardBg)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(cardBorderColor, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .help("Switch AI Model")
    }
    
    private func shortModelName(_ model: String) -> String {
        let parts = model.split(separator: "-")
        if parts.count > 2 {
            return parts.prefix(2).joined(separator: "-")
        }
        return model
    }
    
    private var currentModelName: String {
        let normalized = modelCatalog.normalizedSelection(provider: appState.aiProvider, model: appState.aiModel)
        if !normalized.model.isEmpty {
            return normalized.model
        }
        let provider = StreamableAIProvider(rawValue: appState.aiProvider) ?? .gemini
        return provider.defaultModel
    }
    
    // MARK: - Live Hardware Context Strip
    
    private var hardwareContextStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Board Target
                contextPill(icon: "cpu", text: selectedBoard.rawValue, highlight: true)
                
                // Serial Port
                if let port = selectedPort {
                    contextPill(icon: "cable.connector", text: port.name, highlight: false)
                } else {
                    contextPill(icon: "cable.connector.slash", text: "No USB Hardware", highlight: false)
                }
                
                // Language
                contextPill(icon: "chevron.left.forwardslash.chevron.right", text: editorLanguage.rawValue, highlight: false)
                
                // Auto-Deps
                contextPill(icon: "bolt.fill", text: "AUTO-DEPS: \(envManager.autoDepStatus)", highlight: false)
                
                // Errors
                if buildLogOutput.contains("error:") || buildLogOutput.contains("[ERROR]") {
                    contextPill(icon: "exclamationmark.triangle.fill", text: "Build Error", highlight: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(stripBg)
    }
    
    private func contextPill(icon: String, text: String, highlight: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(highlight ? (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.1)) : cardBg)
        .foregroundColor(highlight ? (isDark ? .white : .black) : (isDark ? Color(white: 0.7) : Color(white: 0.3)))
        .cornerRadius(3)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(cardBorderColor, lineWidth: 1))
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 20)
            
            ZStack {
                Circle()
                    .fill(cardBg)
                    .frame(width: 54, height: 54)
                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: 26))
                    .foregroundColor(isDark ? Color(white: 0.7) : Color(white: 0.3))
            }
            
            VStack(spacing: 4) {
                Text("Embedded Systems Copilot")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(isDark ? .white : .black)
                
                Text("Specialized firmware, FreeRTOS, and peripheral engineering for \(selectedBoard.rawValue)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(isDark ? Color(white: 0.5) : Color(white: 0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("POPULAR TASKS:")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(isDark ? Color(white: 0.4) : Color(white: 0.5))
                
                ForEach(suggestions.prefix(4)) { sug in
                    Button(action: {
                        sendSuggestion(sug)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: sug.icon)
                                .font(.system(size: 9))
                                .foregroundColor(isDark ? .white : .black)
                            Text(sug.text)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(isDark ? Color(white: 0.85) : Color(white: 0.15))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8))
                                .foregroundColor(isDark ? Color(white: 0.4) : Color(white: 0.5))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(cardBg)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(cardBorderColor, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
        }
        .padding(10)
    }
    
    // MARK: - Quick Suggestions Bar
    
    private var quickSuggestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions) { sug in
                    Button(action: {
                        sendSuggestion(sug)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: sug.icon)
                                .font(.system(size: 8))
                                .foregroundColor(isDark ? .white : .black)
                            Text(sug.text)
                                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(cardBg)
                        .foregroundColor(isDark ? Color(white: 0.85) : Color(white: 0.15))
                        .cornerRadius(3)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(cardBorderColor, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(stripBg)
    }
    
    // MARK: - Prompt Input Bar
    
    private var promptInputBar: some View {
        VStack(spacing: 0) {
            // Unified Input Card
            VStack(alignment: .leading, spacing: 6) {
                // Multiline text input with clear placeholder and Enter-to-send
                if #available(macOS 13.0, *) {
                    TextField("Ask Embedded Copilot (e.g. debug register, decode crash)...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(isDark ? .white : .black)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .onSubmit {
                            if !NSEvent.modifierFlags.contains(.shift) && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                sendMessage()
                            }
                        }
                } else {
                    TextField("Ask Embedded Copilot (e.g. debug register, decode crash)...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(isDark ? .white : .black)
                        .focused($isInputFocused)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .onSubmit {
                            if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                sendMessage()
                            }
                        }
                }
                
                // Bottom Toolbar inside the unified card
                HStack(spacing: 8) {
                    // Attach Context Pill Toggle
                    Button(action: {
                        attachHardwareContext.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: attachHardwareContext ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 8))
                                .foregroundColor(attachHardwareContext ? (isDark ? .white : .black) : (isDark ? Color(white: 0.4) : Color(white: 0.5)))
                            
                            Image(systemName: "paperclip")
                                .font(.system(size: 8))
                            
                            Text("Attach Context")
                                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(attachHardwareContext ? (isDark ? .white : .black) : (isDark ? Color(white: 0.5) : Color(white: 0.5)))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(attachHardwareContext ? (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)) : cardBg)
                        .cornerRadius(3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(cardBorderColor, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Include board hardware specs, active port, and sketch code in AI prompt")
                    
                    Spacer()
                    
                    // Keyboard hint
                    Text("↵ Send")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(isDark ? Color(white: 0.3) : Color(white: 0.6))
                    
                    // Send / Stop Button
                    if viewModel.isLoading {
                        Button(action: {
                            viewModel.cancelStream()
                        }) {
                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: 6, height: 6)
                                    .cornerRadius(1)
                                Text("STOP")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                        .help("Stop AI generation")
                    } else {
                        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        Button(action: {
                            sendMessage()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(hasText ? (isDark ? Color.white : Color.black) : (isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)))
                                    .frame(width: 22, height: 22)
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(hasText ? (isDark ? .black : .white) : (isDark ? Color(white: 0.35) : Color(white: 0.6)))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasText)
                        .help("Send Message (Return)")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
            .background(isDark ? Color(white: 0.07) : Color.white)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isInputFocused ? (isDark ? Color.white.opacity(0.35) : Color.black.opacity(0.35)) : cardBorderColor, lineWidth: 1)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(stripBg)
    }
    
    // MARK: - Actions
    
    private func sendSuggestion(_ suggestion: EmbeddedAISuggestion) {
        inputText = suggestion.prompt
        sendMessage()
    }
    
    // MARK: - Core AI Dispatch
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        inputText = ""
        
        let normalized = modelCatalog.normalizedSelection(provider: appState.aiProvider, model: appState.aiModel)
        let provider = StreamableAIProvider(rawValue: normalized.provider)
            ?? StreamableAIProvider.detect(from: normalized.model)
        var model = normalized.model
        let lower = model.lowercased()
        if lower == "deepseek-v4" || lower == "deepseek-chat-v4" || lower == "deepseek" {
            model = "deepseek-chat"
        } else if lower == "gemini-flash" || lower == "gemini" {
            model = "gemini-2.5-flash"
        }
        
        var apiKey = appState.apiKeys[provider.rawValue] ?? ""
        if apiKey.isEmpty {
            apiKey = UserDefaults.standard.string(forKey: "\(provider.rawValue)_api_key") ?? ""
        }
        if apiKey.isEmpty && provider == .openai {
            apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        }
        
        // Build Embedded System Prompt
        let systemPrompt = buildEmbeddedSystemPrompt()
        
        viewModel.sendMessage(
            text: text,
            systemPrompt: systemPrompt,
            provider: provider,
            model: model,
            apiKey: apiKey
        )
    }
    
    private func buildEmbeddedSystemPrompt() -> String {
        var context = """
        You are the MicroCode Embedded AI Agent — an expert embedded systems architect, hardware engineer, and firmware developer.
        
        ## TARGET ENVIRONMENT:
        - Board: \(selectedBoard.rawValue) (\(selectedBoard.mcuSummary))
        - Memory: \(selectedBoard.memorySpecs)
        - Bus/Peripherals: \(selectedBoard.busSummary)
        - Language: \(editorLanguage.rawValue)
        - Hardware Serial Port: \(selectedPort?.path ?? "None connected")
        
        ## EMBEDDED ENGINEERING RULES:
        1. Always produce clean, efficient, production-ready code blocks annotated with the language (e.g. ```cpp, ```c, or ```python).
        2. Strictly include all required headers (e.g. <Arduino.h>, <freertos/FreeRTOS.h>, <freertos/task.h>, <freertos/queue.h>, <Wire.h>, <SPI.h>, etc.).
        3. Never use blocking delays (`delay()`, `sleep()`) inside FreeRTOS tasks when non-blocking ticks (`vTaskDelay(pdMS_TO_TICKS(ms))`) or timers are appropriate.
        4. When explaining compilation errors or Guru Meditation crash traces, pinpoint the exact source line and explain the register dump or memory fault.
        5. Respond in Thai or English based on the language of the user's prompt.
        """
        
        if attachHardwareContext {
            context += "\n\n## CURRENT SKETCH SOURCE CODE:\n```\(editorLanguage.syntaxLanguageId)\n"
            if editorSourceCode.count > 4000 {
                context += String(editorSourceCode.prefix(4000)) + "\n// ... [truncated for context limit]\n"
            } else {
                context += editorSourceCode + "\n"
            }
            context += "```\n"
            
            if !buildLogOutput.isEmpty {
                let tail = String(buildLogOutput.suffix(1500))
                context += "\n## RECENT BUILD LOG / COMPILER OUTPUT:\n```\n\(tail)\n```\n"
            }
            
            let crashes = consoleEntries.filter { $0.content.contains("Guru Meditation") || $0.content.contains("Backtrace:") || $0.content.contains("abort()") || $0.isError }
            if !crashes.isEmpty {
                let crashDump = crashes.suffix(10).map { "[\($0.tag)] \($0.content)" }.joined(separator: "\n")
                context += "\n## RECENT SERIAL LOG / CRASH DUMP:\n```\n\(crashDump)\n```\n"
            }
        }
        
        return context
    }
}

// MARK: - Message Row

struct EmbeddedAIMessageRow: View {
    let message: EmbeddedAIMessage
    var isLoading: Bool = false
    var isDark: Bool = true
    let onReplaceSketch: (String) -> Void
    let onAppendSketch: (String) -> Void
    
    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 30)
                Text(message.content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isDark ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.15), lineWidth: 1))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 10))
                        .foregroundColor(isDark ? .white : .black)
                    Text("EMBEDDED COPILOT")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(isDark ? Color(white: 0.6) : Color(white: 0.4))
                    Spacer()
                }
                
                if message.content.isEmpty {
                    if isLoading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                            Text("Synthesizing hardware architecture & firmware...")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(isDark ? Color(white: 0.6) : Color(white: 0.4))
                        }
                        .padding(.vertical, 4)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 11))
                                .foregroundColor(isDark ? Color(white: 0.6) : Color(white: 0.4))
                            Text("No response received from AI model.")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(isDark ? Color(white: 0.6) : Color(white: 0.4))
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    let blocks = MessageContentParser.parse(message.content)
                    if blocks.isEmpty {
                        Text(message.content)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(isDark ? Color(white: 0.9) : Color(white: 0.1))
                            .textSelection(.enabled)
                    } else {
                        ForEach(blocks) { block in
                            switch block {
                            case .thought(let content, let duration):
                                AntigravityThoughtBlockView(content: content, durationSeconds: duration)
                            case .text(let text):
                                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(text)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(isDark ? Color(white: 0.9) : Color(white: 0.1))
                                        .textSelection(.enabled)
                                }
                            case .code(let lang, let code):
                                EmbeddedAICodeBlockView(
                                    language: lang,
                                    code: code,
                                    isDark: isDark,
                                    onReplace: { onReplaceSketch(code) },
                                    onAppend: { onAppendSketch(code) }
                                )
                            case .heading(let level, let content):
                                Text(content)
                                    .font(.system(size: level <= 2 ? 12 : 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(isDark ? .white : .black)
                            case .list(let items, _):
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(items, id: \.self) { item in
                                        HStack(alignment: .top, spacing: 5) {
                                            Text("•")
                                                .foregroundColor(isDark ? Color(white: 0.5) : Color(white: 0.5))
                                            Text(item)
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .foregroundColor(isDark ? Color(white: 0.85) : Color(white: 0.15))
                                        }
                                    }
                                }
                            default:
                                Text(message.content)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(isDark ? Color(white: 0.9) : Color(white: 0.1))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1))
        }
    }
}

// MARK: - Interactive Code Block View with 1-Click Replace

struct EmbeddedAICodeBlockView: View {
    let language: String
    let code: String
    var isDark: Bool = true
    let onReplace: () -> Void
    let onAppend: () -> Void
    
    @State private var isCopied: Bool = false
    @State private var isReplaced: Bool = false
    @State private var isAppended: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 6) {
                Text(language.isEmpty ? "C++" : language.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(isDark ? Color(white: 0.6) : Color(white: 0.4))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    .cornerRadius(2)
                
                Spacer()
                
                // 1. REPLACE SKETCH
                Button(action: {
                    onReplace()
                    isReplaced = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isReplaced = false }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: isReplaced ? "checkmark" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 8))
                        Text(isReplaced ? "REPLACED" : "REPLACE SKETCH")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isReplaced ? (isDark ? Color.white : Color.black) : (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)))
                    .foregroundColor(isReplaced ? (isDark ? .black : .white) : (isDark ? .white : .black))
                    .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .help("Replace current editor source code with this snippet")
                
                // 2. APPEND
                Button(action: {
                    onAppend()
                    isAppended = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isAppended = false }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: isAppended ? "checkmark" : "plus.circle")
                            .font(.system(size: 8))
                        Text(isAppended ? "APPENDED" : "APPEND")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                    .foregroundColor(isDark ? Color(white: 0.8) : Color(white: 0.2))
                    .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .help("Append snippet to the bottom of the sketch")
                
                // 3. COPY
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isCopied = false }
                }) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundColor(isCopied ? (isDark ? .white : .black) : (isDark ? Color(white: 0.5) : Color(white: 0.5)))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Copy code to clipboard")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            
            Rectangle().fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)).frame(height: 1)
            
            // Code text
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(isDark ? Color(white: 0.95) : Color(white: 0.1))
                    .textSelection(.enabled)
                    .padding(8)
            }
        }
        .background(isDark ? Color.black : Color(white: 0.95))
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1))
    }
}
