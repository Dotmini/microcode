//
//  AIDesignPanel.swift
//  CodeTunner
//
//  Floating AI Design Chat Panel — Claude Design Style
//  Type a prompt, AI generates the UI layout directly on canvas.
//
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import SwiftUI

struct AIDesignPanel: View {
    @EnvironmentObject var designStore: DesignStore
    @StateObject private var engine = AIDesignEngine.shared
    @State private var prompt: String = ""
    @State private var showSettings = false
    @FocusState private var isPromptFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Chat History
            chatHistory
            
            Divider()
            
            // Input Area
            inputArea
        }
        .frame(width: 340, height: 480)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 8) {
            // AI Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text("AI Design")
                    .font(.system(size: 13, weight: .semibold))
                
                Text(providerName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status
            if engine.isGenerating {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }
            
            // Provider Switcher
            Menu {
                ForEach(["gemini", "openai", "claude", "deepseek"], id: \.self) { p in
                    Button(action: { engine.selectedProvider = p }) {
                        HStack {
                            Text(providerLabel(p))
                            if engine.selectedProvider == p {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button("API Keys...") { showSettings = true }
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .popover(isPresented: $showSettings) {
                settingsPopover
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    // MARK: - Chat History
    
    private var chatHistory: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    // Welcome message
                    if engine.chatHistory.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 28))
                                .foregroundColor(.purple.opacity(0.6))
                            
                            Text("Describe a UI to design")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            // Quick actions
                            VStack(spacing: 6) {
                                quickAction("📱 Mobile login page")
                                quickAction("💳 Payment card form")
                                quickAction("📊 Dashboard with charts")
                                quickAction("🛒 Product listing grid")
                                quickAction("👤 User profile page")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                    }
                    
                    ForEach(engine.chatHistory) { message in
                        chatBubble(message)
                            .id(message.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: engine.chatHistory.count) { _ in
                if let last = engine.chatHistory.last {
                    withAnimation {
                        scrollProxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private func chatBubble(_ message: AIDesignMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                Circle()
                    .fill(LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "wand.and.sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.role == .user
                        ? Color.blue.opacity(0.15)
                        : Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    .foregroundColor(.primary)
                
                if message.elementCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 9))
                        Text("\(message.elementCount) elements")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                }
                
                Text(message.timestamp, style: .time)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .frame(maxWidth: 260, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .user {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
    
    private func quickAction(_ text: String) -> some View {
        Button(action: {
            prompt = String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            sendPrompt()
        }) {
            Text(text)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Input Area
    
    private var inputArea: some View {
        HStack(spacing: 8) {
            TextField("Describe your design...", text: $prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isPromptFocused)
                .onSubmit { sendPrompt() }
            
            Button(action: sendPrompt) {
                Image(systemName: engine.isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(prompt.isEmpty ? .secondary : .blue)
            }
            .buttonStyle(.plain)
            .disabled(prompt.isEmpty && !engine.isGenerating)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    // MARK: - Settings
    
    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("🔑 API Keys")
                .font(.system(size: 13, weight: .semibold))
            
            VStack(spacing: 10) {
                keyField("Gemini", key: $engine.geminiKey)
                keyField("OpenAI", key: $engine.openaiKey)
                keyField("Claude", key: $engine.claudeKey)
                keyField("DeepSeek", key: $engine.deepseekKey)
            }
            
            Text("Keys are stored locally in UserDefaults")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(width: 300)
    }
    
    private func keyField(_ label: String, key: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
            SecureField("API Key", text: key)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
        }
    }
    
    // MARK: - Actions
    
    private func sendPrompt() {
        guard !prompt.isEmpty else { return }
        let p = prompt
        prompt = ""
        Task {
            await engine.generateDesign(prompt: p, designStore: designStore)
        }
    }
    
    // MARK: - Helpers
    
    private var providerName: String { providerLabel(engine.selectedProvider) }
    
    private func providerLabel(_ id: String) -> String {
        switch id {
        case "openai": return "ChatGPT"
        case "gemini": return "Gemini"
        case "claude": return "Claude"
        case "deepseek": return "DeepSeek"
        default: return id
        }
    }
}
