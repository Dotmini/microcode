//
//  SubscriptionAuthManager.swift
//  MicroCode
//
//  Created and Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//
//  Description:
//  Manages web subscription connections (ChatGPT Plus/Team/Pro, Claude Pro, Gemini Advanced, DeepSeek, Copilot, Zhipu GLM)
//  without requiring per-token pay-as-you-go API keys.
//

import Foundation
import Combine
import AppKit
import Security
import WebKit

public struct SubscriptionModelInfo: Identifiable, Hashable, Codable {
    public var id: String { "\(provider.rawValue):\(modelID)" }
    public let modelID: String
    public let name: String
    public let provider: SubscriptionProviderType
    public let badge: String
    public let description: String
    public let aiProviderID: String // "openai", "anthropic", "gemini", "deepseek", "glm", "aipass"
    
    public init(modelID: String, name: String, provider: SubscriptionProviderType, badge: String, description: String, aiProviderID: String) {
        self.modelID = modelID
        self.name = name
        self.provider = provider
        self.badge = badge
        self.description = description
        self.aiProviderID = aiProviderID
    }
}

public enum SubscriptionProviderType: String, CaseIterable, Identifiable, Codable {
    case aipass = "aipass"
    case chatgpt = "chatgpt"
    case claude = "claude"
    case gemini = "gemini"
    case deepseek = "deepseek"
    case copilot = "copilot"
    case glm = "glm"
    case openrouter = "openrouter"
    case groq = "groq"
    case mistral = "mistral"
    case kimi = "kimi"
    case perplexity = "perplexity"
    case typhoon = "typhoon"
    case qwen = "qwen"
    case grok = "grok"
    case cerebras = "cerebras"
    case together = "together"
    case fireworks = "fireworks"
    case minimax = "minimax"
    case nvidia = "nvidia"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .aipass: return "TH-AI Passport (de.aipass.net)"
        case .chatgpt: return "ChatGPT Plus / Team / Pro"
        case .claude: return "Claude Pro / Team"
        case .gemini: return "Gemini Advanced (Google One)"
        case .deepseek: return "DeepSeek Web (Unlimited)"
        case .copilot: return "GitHub Copilot (CLI / Web)"
        case .glm: return "Zhipu GLM (BigModel)"
        case .openrouter: return "OpenRouter Web (Free & Pro)"
        case .groq: return "GroqCloud Developer (Free LPU)"
        case .mistral: return "Mistral Le Chat Pro / Console"
        case .kimi: return "Moonshot Kimi K2.5 Web"
        case .perplexity: return "Perplexity Pro / Sonar Web"
        case .typhoon: return "SCB 10X Typhoon Playground"
        case .qwen: return "Alibaba Qwen Chat / DashScope"
        case .grok: return "xAI SuperGrok / X Premium+"
        case .cerebras: return "Cerebras Cloud (Free Wafer-Scale)"
        case .together: return "Together AI Web Cloud"
        case .fireworks: return "Fireworks AI Web Console"
        case .minimax: return "MiniMax M2.7 / Hailuo Web"
        case .nvidia: return "NVIDIA NIM Developer (Free Credits)"
        }
    }
    
    public var providerIcon: String {
        switch self {
        case .aipass: return "aipass"
        case .chatgpt: return "openai"
        case .claude: return "anthropic"
        case .gemini: return "gemini"
        case .deepseek: return "deepseek"
        case .copilot: return "github"
        case .glm: return "glm"
        case .openrouter: return "openrouter"
        case .groq: return "groq"
        case .mistral: return "mistral"
        case .kimi: return "kimi"
        case .perplexity: return "perplexity"
        case .typhoon: return "typhoon"
        case .qwen: return "qwen"
        case .grok: return "grok"
        case .cerebras: return "cerebras"
        case .together: return "together"
        case .fireworks: return "fireworks"
        case .minimax: return "minimax"
        case .nvidia: return "nvidia"
        }
    }
    
    @MainActor
    public var defaultModel: String {
        if let firstLive = Self.liveModelInfos[self]?.first?.modelID {
            return firstLive
        }
        if let firstDefault = defaultModelInfos.first?.modelID {
            return firstDefault
        }
        if let firstCatalog = AIModelCatalog.shared.provider(aiProviderID)?.models.first?.id {
            return firstCatalog
        }
        switch self {
        case .aipass:
            return "gemini-3.5-flash-lite"
        case .chatgpt:
            return "gpt-6-luna"
        case .claude:
            return "claude-sonnet-5-5"
        case .gemini:
            return "gemini-2.5-flash"
        case .deepseek:
            return "deepseek-flash"
        case .copilot:
            return "auto"
        case .glm:
            return "glm-5.3-flash"
        case .openrouter:
            return "openrouter/auto"
        case .groq:
            return "llama-3.3-70b-versatile"
        case .mistral:
            return "codestral-latest"
        case .kimi:
            return "kimi-k2.5"
        case .perplexity:
            return "sonar-reasoning-pro"
        case .typhoon:
            return "typhoon-v2.5-30b-a3b-instruct"
        case .qwen:
            return "qwen3-coder-plus"
        case .grok:
            return "grok-4"
        case .cerebras:
            return "qwen-3-coder-480b"
        case .together:
            return "deepseek-ai/DeepSeek-V3"
        case .fireworks:
            return "accounts/fireworks/models/deepseek-v3"
        case .minimax:
            return "MiniMax-M2.7"
        case .nvidia:
            return "deepseek-ai/deepseek-r1"
        }
    }
    
    public var shortLabel: String {
        switch self {
        case .aipass: return "TH-AI Pass"
        case .chatgpt: return "ChatGPT Plus"
        case .claude: return "Claude Pro"
        case .gemini: return "Gemini Adv"
        case .deepseek: return "DeepSeek Web"
        case .copilot: return "Copilot"
        case .glm: return "GLM Member"
        case .openrouter: return "OpenRouter"
        case .groq: return "Groq Free"
        case .mistral: return "Mistral Pro"
        case .kimi: return "Kimi Web"
        case .perplexity: return "Perplexity Pro"
        case .typhoon: return "Typhoon TH"
        case .qwen: return "Qwen Chat"
        case .grok: return "SuperGrok"
        case .cerebras: return "Cerebras Free"
        case .together: return "Together AI"
        case .fireworks: return "Fireworks AI"
        case .minimax: return "MiniMax Web"
        case .nvidia: return "NVIDIA NIM"
        }
    }
    
    // MARK: - Live Model Store
    private static var liveModelInfos: [SubscriptionProviderType: [SubscriptionModelInfo]] = [:]

    public static func setLiveModels(for provider: SubscriptionProviderType, models: [SubscriptionModelInfo]) {
        liveModelInfos[provider] = models
    }

    public static func registerCustomSubscriptionModel(provider: SubscriptionProviderType, modelId: String) {
        let cleanId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return }
        
        let customKey = "microcode_sub_custom_models_\(provider.rawValue)"
        var saved = UserDefaults.standard.stringArray(forKey: customKey) ?? []
        if !saved.contains(cleanId) {
            saved.append(cleanId)
            UserDefaults.standard.set(saved, forKey: customKey)
        }
        
        let newInfo = SubscriptionModelInfo(
            modelID: cleanId,
            name: AIModelCatalog.formatModelName(cleanId),
            provider: provider,
            badge: "CUSTOM",
            description: "User registered custom model for \(provider.displayName)",
            aiProviderID: provider.aiProviderID
        )
        
        var current = liveModelInfos[provider] ?? provider.defaultModelInfos
        if !current.contains(where: { $0.modelID == cleanId }) {
            current.insert(newInfo, at: 0)
            liveModelInfos[provider] = current
        }
    }

    public var aiProviderID: String {
        switch self {
        case .aipass: return "aipass"
        case .chatgpt: return "openai"
        case .claude: return "anthropic"
        case .gemini: return "gemini"
        case .deepseek: return "deepseek"
        case .copilot: return "copilot"
        case .glm: return "glm"
        case .openrouter: return "openrouter"
        case .groq: return "groq"
        case .mistral: return "mistral"
        case .kimi: return "kimi"
        case .perplexity: return "perplexity"
        case .typhoon: return "typhoon"
        case .qwen: return "qwen"
        case .grok: return "grok"
        case .cerebras: return "cerebras"
        case .together: return "together"
        case .fireworks: return "fireworks"
        case .minimax: return "minimax"
        case .nvidia: return "nvidia"
        }
    }

    public var modelInfos: [SubscriptionModelInfo] {
        var res: [SubscriptionModelInfo] = []
        if let live = Self.liveModelInfos[self], !live.isEmpty {
            res = live
        } else {
            res = defaultModelInfos
        }
        let customKey = "microcode_sub_custom_models_\(rawValue)"
        let customs = UserDefaults.standard.stringArray(forKey: customKey) ?? []
        for cid in customs.reversed() {
            if !res.contains(where: { $0.modelID == cid }) {
                res.insert(SubscriptionModelInfo(
                    modelID: cid,
                    name: AIModelCatalog.formatModelName(cid),
                    provider: self,
                    badge: "CUSTOM",
                    description: "Custom model",
                    aiProviderID: self.aiProviderID
                ), at: 0)
            }
        }
        return res
    }

    public var defaultModelInfos: [SubscriptionModelInfo] {
        if let live = Self.liveModelInfos[self], !live.isEmpty {
            return live
        }
        switch self {
        case .aipass:
            return [
                SubscriptionModelInfo(modelID: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash Lite (Free)", provider: .aipass, badge: "FREE", description: "TH-AI Passport free unlimited credit model", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "claude-sonnet-5-5@default", name: "Claude Sonnet 5.5 (AiPASS)", provider: .aipass, badge: "AGENT", description: "Anthropic Claude Sonnet 5.5 via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "claude-opus-5-5@default", name: "Claude Opus 5.5 (AiPASS)", provider: .aipass, badge: "FLAGSHIP", description: "Anthropic Claude Opus 5.5 via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "claude-sonnet-5@azure", name: "Claude Sonnet 5 Azure (AiPASS)", provider: .aipass, badge: "AGENT", description: "Anthropic Claude Sonnet 5 via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "claude-opus-5@azure", name: "Claude Opus 5 Azure (AiPASS)", provider: .aipass, badge: "REASONING", description: "Anthropic Claude Opus 5 via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "claude-opus-4-8@default", name: "Claude Opus 4.8 (AiPASS)", provider: .aipass, badge: "REASONING", description: "Anthropic Claude Opus 4.8 via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "claude-sonnet-4-6", name: "Claude Sonnet 4.6 (AiPASS)", provider: .aipass, badge: "AGENT", description: "Anthropic Claude Sonnet 4.6 via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "claude-haiku-5-5@default", name: "Claude Haiku 5.5 (AiPASS)", provider: .aipass, badge: "FAST", description: "Anthropic Claude Haiku 5.5 via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gpt-6.1-sol", name: "GPT 6.1 Sol (AiPASS)", provider: .aipass, badge: "FLAGSHIP", description: "OpenAI GPT 6.1 Sol via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gpt-6-sol", name: "GPT 6 Sol (AiPASS)", provider: .aipass, badge: "FLAGSHIP", description: "OpenAI GPT 6 Sol via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gpt-6-luna", name: "GPT 6 Luna (AiPASS)", provider: .aipass, badge: "FAST", description: "OpenAI GPT 6 Luna via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gpt-6-astra", name: "GPT 6 Astra (AiPASS)", provider: .aipass, badge: "REASONING", description: "OpenAI GPT 6 Astra via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gpt-5.6-sol", name: "GPT 5.6 Sol (AiPASS)", provider: .aipass, badge: "FLAGSHIP", description: "OpenAI GPT 5.6 Sol via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gpt-5.6-luna", name: "GPT 5.6 Luna (AiPASS)", provider: .aipass, badge: "FAST", description: "OpenAI GPT 5.6 Luna via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gpt-5.5", name: "GPT 5.5 (AiPASS)", provider: .aipass, badge: "CHAT", description: "OpenAI GPT 5.5 via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gpt-5.4", name: "GPT 5.4 (AiPASS)", provider: .aipass, badge: "CHAT", description: "OpenAI GPT 5.4 via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gemini-4-argon", name: "Gemini 4 Argon (AiPASS)", provider: .aipass, badge: "FLAGSHIP", description: "Google Gemini 4 Argon via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gemini-3.8-flash", name: "Gemini 3.8 Flash (AiPASS)", provider: .aipass, badge: "FAST", description: "Google Gemini 3.8 Flash via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gemini-3.7-flash", name: "Gemini 3.7 Flash (AiPASS)", provider: .aipass, badge: "FAST", description: "Google Gemini 3.7 Flash via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gemini-3.6-flash", name: "Gemini 3.6 Flash (AiPASS)", provider: .aipass, badge: "FAST", description: "Google Gemini 3.6 Flash via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gemini-3.5-flash", name: "Gemini 3.5 Flash (AiPASS)", provider: .aipass, badge: "FAST", description: "Google Gemini 3.5 Flash via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gemini-3.1-pro-preview", name: "Gemini 3.1 Pro Preview (AiPASS)", provider: .aipass, badge: "PRO", description: "Google Gemini 3.1 Pro via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gemini-2.5-pro", name: "Gemini 2.5 Pro (AiPASS)", provider: .aipass, badge: "PRO", description: "Google Gemini 2.5 Pro via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gemini-2.5-flash", name: "Gemini 2.5 Flash (AiPASS)", provider: .aipass, badge: "FAST", description: "Google Gemini 2.5 Flash via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "DeepSeek-V4.1-Flash", name: "DeepSeek V4.1 Flash (AiPASS)", provider: .aipass, badge: "FAST", description: "DeepSeek V4.1 Flash via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "DeepSeek-V4-Pro", name: "DeepSeek V4 Pro (AiPASS)", provider: .aipass, badge: "FLAGSHIP", description: "DeepSeek V4 Pro via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "DeepSeek-V3.2", name: "DeepSeek V3.2 (AiPASS)", provider: .aipass, badge: "CHAT", description: "DeepSeek V3.2 via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "glm-5.3", name: "GLM 5.3 (AiPASS)", provider: .aipass, badge: "FLAGSHIP", description: "Zhipu GLM 5.3 via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "glm-5.3-flash", name: "GLM 5.3 Flash (AiPASS)", provider: .aipass, badge: "FAST", description: "Zhipu GLM 5.3 Flash via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "grok-4.7", name: "Grok 4.7 (AiPASS)", provider: .aipass, badge: "FLAGSHIP", description: "xAI Grok 4.7 via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "grok-4.6", name: "Grok 4.6 (AiPASS)", provider: .aipass, badge: "CHAT", description: "xAI Grok 4.6 via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "Kimi-K2.7-Code", name: "Kimi K2.7 Code (AiPASS)", provider: .aipass, badge: "CODE", description: "Moonshot Kimi K2.7 Code via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "kimi-k3", name: "Kimi K3 (AiPASS)", provider: .aipass, badge: "FLAGSHIP", description: "Moonshot Kimi K3 via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "qwen3-next-80b-a3b-instruct-maas", name: "Qwen3 Next 80B (AiPASS)", provider: .aipass, badge: "QWEN", description: "Alibaba Qwen3 Next 80B via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "typhoon2.5-qwen3-30b", name: "Typhoon 2.5 30B (AiPASS)", provider: .aipass, badge: "THAI", description: "SCB10X Typhoon 2.5 30B via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "pathumma-thaillm-8b", name: "Pathumma ThaiLLM 8B (AiPASS)", provider: .aipass, badge: "THAI", description: "NECTEC Pathumma ThaiLLM 8B via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "sonar-reasoning-pro", name: "Sonar Reasoning Pro (AiPASS)", provider: .aipass, badge: "SEARCH", description: "Perplexity Sonar Reasoning Pro via TH-AI Passport", aiProviderID: "aipass"),
                // Image Generation Models (TH-AI Passport)
                SubscriptionModelInfo(modelID: "gemini-2.5-flash-image", name: "Nano Banana — Gemini 2.5 Flash Image (Free)", provider: .aipass, badge: "IMAGE", description: "Google Nano Banana fast image generation via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gemini-3.1-flash-lite-image", name: "Nano Banana 2 Lite — Gemini 3.1 Image (Free)", provider: .aipass, badge: "IMAGE", description: "Google Nano Banana 2 Lite image generation via TH-AI Passport", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gemini-3.1-flash-image", name: "Nano Banana 2 — Gemini 3.1 Flash Image (AiPASS)", provider: .aipass, badge: "IMAGE", description: "Google Nano Banana 2 high-fidelity image generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gemini-nano-banana-2.1", name: "Nano Banana 2.1 — Gemini Image (AiPASS)", provider: .aipass, badge: "IMAGE", description: "Google Nano Banana 2.1 studio image generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gemini-3-pro-image", name: "Nano Banana Pro — Gemini 3 Pro Image (AiPASS)", provider: .aipass, badge: "IMAGE", description: "Google Nano Banana Pro photorealistic image generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "FLUX.2-pro", name: "Flux 2 Pro — Studio Image (AiPASS)", provider: .aipass, badge: "IMAGE", description: "Black Forest Labs Flux 2 Pro image generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "flux2-klein-4b@jts", name: "Flux 2 Klein 4B — Image (AiPASS)", provider: .aipass, badge: "IMAGE", description: "Flux 2 Klein 4B JTS image generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gpt-image-2", name: "GPT-Image-2 (AiPASS)", provider: .aipass, badge: "IMAGE", description: "OpenAI GPT-Image-2 high-precision image generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gpt-image-2.5-flare", name: "GPT-Image-2.5 Flare (AiPASS)", provider: .aipass, badge: "IMAGE", description: "OpenAI GPT-Image-2.5 Flare studio image generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "gpt-image-2.5-sunburst", name: "GPT-Image-2.5 Sunburst (AiPASS)", provider: .aipass, badge: "IMAGE", description: "OpenAI GPT-Image-2.5 Sunburst flagship image generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "seedream-5.0-flash", name: "Seedream 5.0 Flash — Image (AiPASS)", provider: .aipass, badge: "IMAGE", description: "ByteDance Seedream 5.0 Flash image generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "seedream-5.0-pro", name: "Seedream 5.0 Pro — Image (AiPASS)", provider: .aipass, badge: "IMAGE", description: "ByteDance Seedream 5.0 Pro flagship image generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "seedream-4.5", name: "Seedream 4.5 — Image (AiPASS)", provider: .aipass, badge: "IMAGE", description: "ByteDance Seedream 4.5 image generation", aiProviderID: "aipass"),
                // Video Generation Models (TH-AI Passport)
                SubscriptionModelInfo(modelID: "veo-3.1-fast-generate-001", name: "Veo 3.1 Fast — Video Gen (AiPASS)", provider: .aipass, badge: "VIDEO", description: "Google Veo 3.1 Fast AI Video Generation (16:9 / 9:16)", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "veo-3.1-generate-001", name: "Veo 3.1 — Cinema Video Gen (AiPASS)", provider: .aipass, badge: "VIDEO", description: "Google Veo 3.1 Flagship AI Video Generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "veo-3.0-generate-001", name: "Veo 3.0 — Video Gen (AiPASS)", provider: .aipass, badge: "VIDEO", description: "Google Veo 3.0 AI Video Generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "seedance-2.0-fast", name: "Seedance 2.0 Fast — Video Gen (AiPASS)", provider: .aipass, badge: "VIDEO", description: "ByteDance Seedance 2.0 Fast AI Video Generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "seedance-2.0", name: "Seedance 2.0 — Video Gen (AiPASS)", provider: .aipass, badge: "VIDEO", description: "ByteDance Seedance 2.0 AI Video Generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "wan2.2@jts", name: "Wan 2.2 — Video Gen (AiPASS)", provider: .aipass, badge: "VIDEO", description: "Alibaba Wan 2.2 AI Video Generation", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "sora-2", name: "Sora 2 — Video Gen (AiPASS)", provider: .aipass, badge: "VIDEO", description: "OpenAI Sora 2 AI Video Generation", aiProviderID: "aipass"),
                // Music & Audio Generation Models (TH-AI Passport)
                SubscriptionModelInfo(modelID: "lyria-3-clip-preview", name: "Lyria 3 Clip — 30s Music Gen (AiPASS)", provider: .aipass, badge: "MUSIC", description: "Google DeepMind Lyria 3 Clip (30-second AI Music Generation)", aiProviderID: "aipass"),
                SubscriptionModelInfo(modelID: "lyria-3-pro-preview", name: "Lyria 3 Pro — Full Song + Vocals (AiPASS)", provider: .aipass, badge: "MUSIC", description: "Google DeepMind Lyria 3 Pro (Full-length AI Song & Vocal Generation)", aiProviderID: "aipass")
            ]
        case .chatgpt:
            return [
                SubscriptionModelInfo(modelID: "gpt-6-luna", name: "GPT 6 Luna", provider: .chatgpt, badge: "FAST", description: "ChatGPT Plus / Pro Codex high-speed model", aiProviderID: "openai"),
                SubscriptionModelInfo(modelID: "gpt-6.1-sol", name: "GPT 6.1 Sol", provider: .chatgpt, badge: "FLAGSHIP", description: "ChatGPT Plus / Pro flagship reasoning model", aiProviderID: "openai"),
                SubscriptionModelInfo(modelID: "gpt-6-astra", name: "GPT 6 Astra", provider: .chatgpt, badge: "REASONING", description: "ChatGPT Plus / Pro deep reasoning model", aiProviderID: "openai"),
                SubscriptionModelInfo(modelID: "gpt-6-sol", name: "GPT 6 Sol", provider: .chatgpt, badge: "FLAGSHIP", description: "ChatGPT Plus / Pro coding & architecture model", aiProviderID: "openai"),
                SubscriptionModelInfo(modelID: "gpt-5.3-codex", name: "GPT 5.3 Codex", provider: .chatgpt, badge: "AGENT", description: "ChatGPT Codex agentic coding model", aiProviderID: "openai"),
                SubscriptionModelInfo(modelID: "gpt-5.4", name: "GPT 5.4", provider: .chatgpt, badge: "CHAT", description: "ChatGPT Plus general model", aiProviderID: "openai"),
                SubscriptionModelInfo(modelID: "gpt-5.4-mini", name: "GPT 5.4 Mini", provider: .chatgpt, badge: "FAST", description: "ChatGPT Plus fast lightweight model", aiProviderID: "openai")
            ]
        case .claude:
            return [
                SubscriptionModelInfo(modelID: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", provider: .claude, badge: "AGENT", description: "Anthropic Claude Sonnet 5.5 coding & agent model", aiProviderID: "anthropic"),
                SubscriptionModelInfo(modelID: "claude-opus-5-5", name: "Claude Opus 5.5", provider: .claude, badge: "REASONING", description: "Anthropic Claude Opus 5.5 frontier reasoning model", aiProviderID: "anthropic"),
                SubscriptionModelInfo(modelID: "claude-sonnet-5-5-high", name: "Claude Sonnet 5.5 (High Thinking)", provider: .claude, badge: "THINKING", description: "Anthropic Claude Sonnet 5.5 with extended thinking", aiProviderID: "anthropic"),
                SubscriptionModelInfo(modelID: "claude-opus-5-5-high", name: "Claude Opus 5.5 (High Thinking)", provider: .claude, badge: "THINKING", description: "Anthropic Claude Opus 5.5 with extended thinking", aiProviderID: "anthropic"),
                SubscriptionModelInfo(modelID: "claude-haiku-5-5", name: "Claude Haiku 5.5", provider: .claude, badge: "FAST", description: "Anthropic Claude Haiku 5.5 high-speed model", aiProviderID: "anthropic")
            ]
        case .gemini:
            return [
                SubscriptionModelInfo(modelID: "gemini-3.8-flash-tiered", name: "Gemini 3.8 Flash (Ultra)", provider: .gemini, badge: "FLAGSHIP", description: "Google AI Ultra Gemini 3.8 Flash high-speed agent model", aiProviderID: "gemini"),
                SubscriptionModelInfo(modelID: "gemini-3-flash", name: "Gemini 3 Flash", provider: .gemini, badge: "FAST", description: "Google Gemini 3 Flash subscription model", aiProviderID: "gemini"),
                SubscriptionModelInfo(modelID: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash Lite", provider: .gemini, badge: "FAST", description: "Google Gemini 3.5 Flash Lite subscription model", aiProviderID: "gemini"),
                SubscriptionModelInfo(modelID: "gemini-2.5-flash", name: "Gemini 2.5 Flash", provider: .gemini, badge: "FAST", description: "Google Gemini 2.5 Flash high-speed agent model", aiProviderID: "gemini"),
                SubscriptionModelInfo(modelID: "gemini-2.5-flash-lite", name: "Gemini 2.5 Flash Lite", provider: .gemini, badge: "FAST", description: "Google Gemini 2.5 Flash Lite high-quota model", aiProviderID: "gemini"),
                SubscriptionModelInfo(modelID: "gemini-2.5-pro", name: "Gemini 2.5 Pro", provider: .gemini, badge: "PRO", description: "Google Gemini 2.5 Pro reasoning model", aiProviderID: "gemini")
            ]
        case .deepseek:
            return [
                SubscriptionModelInfo(modelID: "deepseek-flash", name: "DeepSeek V4.1 Flash", provider: .deepseek, badge: "FAST", description: "DeepSeek V4.1 Flash high-speed model", aiProviderID: "deepseek"),
                SubscriptionModelInfo(modelID: "deepseek-v4-pro", name: "DeepSeek V4 Pro", provider: .deepseek, badge: "FLAGSHIP", description: "DeepSeek V4 Pro flagship model", aiProviderID: "deepseek"),
                SubscriptionModelInfo(modelID: "deepseek-chat", name: "DeepSeek V3 Chat", provider: .deepseek, badge: "CHAT", description: "DeepSeek V3 general coding & chat model", aiProviderID: "deepseek"),
                SubscriptionModelInfo(modelID: "deepseek-reasoner", name: "DeepSeek R1 Reasoner", provider: .deepseek, badge: "REASONING", description: "DeepSeek R1 deep reasoning model", aiProviderID: "deepseek")
            ]
        case .copilot:
            return [
                SubscriptionModelInfo(modelID: "auto", name: "Copilot Auto", provider: .copilot, badge: "AUTO", description: "GitHub Copilot dynamic model routing", aiProviderID: "copilot"),
                SubscriptionModelInfo(modelID: "claude-sonnet-4.5", name: "Claude Sonnet 4.5 (Copilot)", provider: .copilot, badge: "AGENT", description: "Anthropic Claude Sonnet via GitHub Copilot", aiProviderID: "copilot"),
                SubscriptionModelInfo(modelID: "gpt-5", name: "GPT-5 (Copilot)", provider: .copilot, badge: "FLAGSHIP", description: "OpenAI GPT-5 via GitHub Copilot", aiProviderID: "copilot"),
                SubscriptionModelInfo(modelID: "gpt-4o", name: "GPT-4o (Copilot)", provider: .copilot, badge: "FAST", description: "OpenAI GPT-4o via GitHub Copilot", aiProviderID: "copilot")
            ]
        case .glm:
            return [
                SubscriptionModelInfo(modelID: "glm-5.3-flash", name: "GLM 5.3 Flash", provider: .glm, badge: "FAST", description: "Zhipu GLM-5.3 Flash high-speed model", aiProviderID: "glm"),
                SubscriptionModelInfo(modelID: "glm-5.3", name: "GLM 5.3", provider: .glm, badge: "FLAGSHIP", description: "Zhipu GLM-5.3 flagship model", aiProviderID: "glm"),
                SubscriptionModelInfo(modelID: "glm-5.2", name: "GLM 5.2", provider: .glm, badge: "FLAGSHIP", description: "Zhipu GLM-5.2 coding & reasoning model", aiProviderID: "glm"),
                SubscriptionModelInfo(modelID: "glm-5", name: "GLM 5", provider: .glm, badge: "CHAT", description: "Zhipu GLM-5 model", aiProviderID: "glm"),
                SubscriptionModelInfo(modelID: "glm-4.7", name: "GLM 4.7", provider: .glm, badge: "CHAT", description: "Zhipu GLM-4.7 model", aiProviderID: "glm"),
                SubscriptionModelInfo(modelID: "glm-4.5-air", name: "GLM 4.5 Air", provider: .glm, badge: "BALANCED", description: "Zhipu GLM-4.5 Air balanced model", aiProviderID: "glm")
            ]
        case .openrouter:
            return [
                SubscriptionModelInfo(modelID: "openrouter/auto", name: "OpenRouter Auto Router", provider: .openrouter, badge: "AUTO", description: "OpenRouter smart routing across 300+ models", aiProviderID: "openrouter"),
                SubscriptionModelInfo(modelID: "deepseek/deepseek-chat-v3-0324:free", name: "DeepSeek V3 (Free)", provider: .openrouter, badge: "FREE", description: "Free DeepSeek V3 via OpenRouter", aiProviderID: "openrouter"),
                SubscriptionModelInfo(modelID: "deepseek/deepseek-r1:free", name: "DeepSeek R1 (Free)", provider: .openrouter, badge: "FREE", description: "Free DeepSeek R1 reasoning via OpenRouter", aiProviderID: "openrouter"),
                SubscriptionModelInfo(modelID: "qwen/qwen3-coder:free", name: "Qwen3 Coder (Free)", provider: .openrouter, badge: "FREE", description: "Free Qwen3 Coder via OpenRouter", aiProviderID: "openrouter"),
                SubscriptionModelInfo(modelID: "anthropic/claude-sonnet-4", name: "Claude Sonnet 4 (OpenRouter)", provider: .openrouter, badge: "AGENT", description: "Anthropic Claude Sonnet 4 via OpenRouter", aiProviderID: "openrouter"),
                SubscriptionModelInfo(modelID: "google/gemini-2.5-pro", name: "Gemini 2.5 Pro (OpenRouter)", provider: .openrouter, badge: "PRO", description: "Google Gemini 2.5 Pro via OpenRouter", aiProviderID: "openrouter")
            ]
        case .groq:
            return [
                SubscriptionModelInfo(modelID: "llama-3.3-70b-versatile", name: "Llama 3.3 70B Versatile (LPU)", provider: .groq, badge: "FAST", description: "Groq LPU ultra-fast Llama 3.3 70B", aiProviderID: "groq"),
                SubscriptionModelInfo(modelID: "deepseek-r1-distill-llama-70b", name: "DeepSeek R1 Distill Llama 70B (LPU)", provider: .groq, badge: "REASONING", description: "Groq LPU DeepSeek R1 reasoning", aiProviderID: "groq"),
                SubscriptionModelInfo(modelID: "qwen-qwq-32b", name: "Qwen QwQ 32B Reasoning (LPU)", provider: .groq, badge: "REASONING", description: "Groq LPU Qwen QwQ 32B reasoning", aiProviderID: "groq"),
                SubscriptionModelInfo(modelID: "llama-3.1-8b-instant", name: "Llama 3.1 8B Instant (LPU)", provider: .groq, badge: "FAST", description: "Groq LPU 1000+ tok/s Llama 3.1 8B", aiProviderID: "groq")
            ]
        case .mistral:
            return [
                SubscriptionModelInfo(modelID: "codestral-latest", name: "Codestral (Latest)", provider: .mistral, badge: "CODE", description: "Mistral Codestral code generation & FIM model", aiProviderID: "mistral"),
                SubscriptionModelInfo(modelID: "devstral-medium-latest", name: "Devstral Medium (SWE Agent)", provider: .mistral, badge: "AGENT", description: "Mistral Devstral autonomous software engineering model", aiProviderID: "mistral"),
                SubscriptionModelInfo(modelID: "mistral-large-latest", name: "Mistral Large (Latest)", provider: .mistral, badge: "FLAGSHIP", description: "Mistral Large flagship reasoning model", aiProviderID: "mistral"),
                SubscriptionModelInfo(modelID: "magistral-medium-latest", name: "Magistral Medium (Reasoning)", provider: .mistral, badge: "REASONING", description: "Mistral Magistral chain-of-thought reasoning", aiProviderID: "mistral")
            ]
        case .kimi:
            return [
                SubscriptionModelInfo(modelID: "kimi-k2.5", name: "Kimi K2.5 Flagship", provider: .kimi, badge: "FLAGSHIP", description: "Moonshot Kimi K2.5 256K context model", aiProviderID: "kimi"),
                SubscriptionModelInfo(modelID: "kimi-k2-0905-preview", name: "Kimi K2 Coding Preview", provider: .kimi, badge: "CODE", description: "Moonshot Kimi K2 agentic coding model", aiProviderID: "kimi"),
                SubscriptionModelInfo(modelID: "kimi-thinking-preview", name: "Kimi Thinking Preview", provider: .kimi, badge: "REASONING", description: "Moonshot Kimi deep reasoning model", aiProviderID: "kimi")
            ]
        case .perplexity:
            return [
                SubscriptionModelInfo(modelID: "sonar-reasoning-pro", name: "Sonar Reasoning Pro (Live Web)", provider: .perplexity, badge: "SEARCH", description: "Perplexity Sonar Pro with real-time web search & citations", aiProviderID: "perplexity"),
                SubscriptionModelInfo(modelID: "sonar-pro", name: "Sonar Pro (Live Web)", provider: .perplexity, badge: "SEARCH", description: "Perplexity Sonar Pro grounded web search", aiProviderID: "perplexity"),
                SubscriptionModelInfo(modelID: "sonar-deep-research", name: "Sonar Deep Research", provider: .perplexity, badge: "REASONING", description: "Perplexity multi-step autonomous web research", aiProviderID: "perplexity")
            ]
        case .typhoon:
            return [
                SubscriptionModelInfo(modelID: "typhoon-v2.5-30b-a3b-instruct", name: "Typhoon v2.5 30B A3B Instruct", provider: .typhoon, badge: "THAI", description: "SCB 10X Typhoon v2.5 30B sovereign Thai LLM", aiProviderID: "typhoon"),
                SubscriptionModelInfo(modelID: "typhoon-v2.1-12b-instruct", name: "Typhoon v2.1 12B Instruct", provider: .typhoon, badge: "THAI", description: "SCB 10X Typhoon v2.1 12B Instruct", aiProviderID: "typhoon"),
                SubscriptionModelInfo(modelID: "typhoon-v2-r1-70b-preview", name: "Typhoon v2 R1 70B Reasoning", provider: .typhoon, badge: "REASONING", description: "SCB 10X Typhoon R1 70B Thai reasoning model", aiProviderID: "typhoon")
            ]
        case .qwen:
            return [
                SubscriptionModelInfo(modelID: "qwen3-coder-plus", name: "Qwen3 Coder Plus", provider: .qwen, badge: "CODE", description: "Alibaba Qwen3 Coder Plus flagship coding agent", aiProviderID: "qwen"),
                SubscriptionModelInfo(modelID: "qwen3-235b-a22b", name: "Qwen3 235B A22B Flagship", provider: .qwen, badge: "FLAGSHIP", description: "Alibaba Qwen3 235B MoE flagship model", aiProviderID: "qwen"),
                SubscriptionModelInfo(modelID: "qwq-plus", name: "QwQ Plus (Reasoning)", provider: .qwen, badge: "REASONING", description: "Alibaba QwQ Plus deep reasoning model", aiProviderID: "qwen"),
                SubscriptionModelInfo(modelID: "qwen-max-latest", name: "Qwen Max (Latest)", provider: .qwen, badge: "PRO", description: "Alibaba Qwen Max model", aiProviderID: "qwen")
            ]
        case .grok:
            return [
                SubscriptionModelInfo(modelID: "grok-4", name: "Grok 4 Flagship", provider: .grok, badge: "FLAGSHIP", description: "xAI Grok 4 frontier reasoning & coding model", aiProviderID: "grok"),
                SubscriptionModelInfo(modelID: "grok-3", name: "Grok 3", provider: .grok, badge: "PRO", description: "xAI Grok 3 model", aiProviderID: "grok"),
                SubscriptionModelInfo(modelID: "grok-3-mini", name: "Grok 3 Mini (Reasoning)", provider: .grok, badge: "REASONING", description: "xAI Grok 3 Mini fast reasoning model", aiProviderID: "grok")
            ]
        case .cerebras:
            return [
                SubscriptionModelInfo(modelID: "qwen-3-coder-480b", name: "Qwen 3 Coder 480B (Wafer-Scale)", provider: .cerebras, badge: "CODE", description: "Cerebras 2,000+ tok/s Qwen 3 Coder 480B", aiProviderID: "cerebras"),
                SubscriptionModelInfo(modelID: "qwen-3-235b-a22b", name: "Qwen 3 235B A22B (Wafer-Scale)", provider: .cerebras, badge: "FLAGSHIP", description: "Cerebras Wafer-Scale Qwen 3 235B", aiProviderID: "cerebras"),
                SubscriptionModelInfo(modelID: "llama-3.3-70b", name: "Llama 3.3 70B (Wafer-Scale)", provider: .cerebras, badge: "FAST", description: "Cerebras Wafer-Scale Llama 3.3 70B", aiProviderID: "cerebras")
            ]
        case .together:
            return [
                SubscriptionModelInfo(modelID: "deepseek-ai/DeepSeek-V3", name: "DeepSeek V3 (Together)", provider: .together, badge: "FLAGSHIP", description: "DeepSeek V3 on Together AI Cloud", aiProviderID: "together"),
                SubscriptionModelInfo(modelID: "deepseek-ai/DeepSeek-R1", name: "DeepSeek R1 (Together)", provider: .together, badge: "REASONING", description: "DeepSeek R1 on Together AI Cloud", aiProviderID: "together"),
                SubscriptionModelInfo(modelID: "Qwen/Qwen3-235B-A22B-fp8-tput", name: "Qwen3 235B FP8 (Together)", provider: .together, badge: "FAST", description: "Qwen3 235B high-throughput on Together AI", aiProviderID: "together")
            ]
        case .fireworks:
            return [
                SubscriptionModelInfo(modelID: "accounts/fireworks/models/deepseek-v3", name: "DeepSeek V3 (Fireworks)", provider: .fireworks, badge: "FLAGSHIP", description: "DeepSeek V3 on Fireworks FireAttention", aiProviderID: "fireworks"),
                SubscriptionModelInfo(modelID: "accounts/fireworks/models/deepseek-r1", name: "DeepSeek R1 (Fireworks)", provider: .fireworks, badge: "REASONING", description: "DeepSeek R1 on Fireworks FireAttention", aiProviderID: "fireworks"),
                SubscriptionModelInfo(modelID: "accounts/fireworks/models/qwen3-235b-a22b", name: "Qwen3 235B A22B (Fireworks)", provider: .fireworks, badge: "CODE", description: "Qwen3 235B on Fireworks AI", aiProviderID: "fireworks")
            ]
        case .minimax:
            return [
                SubscriptionModelInfo(modelID: "MiniMax-M2.7", name: "MiniMax M2.7 Flagship", provider: .minimax, badge: "FLAGSHIP", description: "MiniMax M2.7 1M-context coding & agent model", aiProviderID: "minimax"),
                SubscriptionModelInfo(modelID: "MiniMax-M1", name: "MiniMax M1 Reasoning (1M Context)", provider: .minimax, badge: "REASONING", description: "MiniMax M1 hybrid-attention reasoning model", aiProviderID: "minimax"),
                SubscriptionModelInfo(modelID: "MiniMax-Text-01", name: "MiniMax Text 01 (4M Context)", provider: .minimax, badge: "CHAT", description: "MiniMax Text 01 ultra-long context model", aiProviderID: "minimax")
            ]
        case .nvidia:
            return [
                SubscriptionModelInfo(modelID: "deepseek-ai/deepseek-r1", name: "DeepSeek R1 (NVIDIA NIM)", provider: .nvidia, badge: "REASONING", description: "DeepSeek R1 on NVIDIA NIM TensorRT-LLM", aiProviderID: "nvidia"),
                SubscriptionModelInfo(modelID: "nvidia/llama-3.1-nemotron-ultra-253b-v1", name: "Nemotron Ultra 253B (NVIDIA NIM)", provider: .nvidia, badge: "FLAGSHIP", description: "NVIDIA Llama 3.1 Nemotron Ultra 253B", aiProviderID: "nvidia"),
                SubscriptionModelInfo(modelID: "qwen/qwen3-235b-a22b", name: "Qwen3 235B A22B (NVIDIA NIM)", provider: .nvidia, badge: "CODE", description: "Qwen3 235B on NVIDIA NIM", aiProviderID: "nvidia")
            ]
        }
    }

    public var availableModels: [String] {
        return modelInfos.map(\.modelID)
    }
    
    public var webLoginURL: URL {
        switch self {
        case .aipass: return URL(string: "https://de.aipass.net/sign-in?redirect_to=%2Fchat")!
        case .chatgpt: return URL(string: "https://chatgpt.com")!
        case .claude: return URL(string: "https://claude.ai/login")!
        case .gemini: return URL(string: "https://gemini.google.com")!
        case .deepseek: return URL(string: "https://chat.deepseek.com")!
        case .copilot: return URL(string: "https://github.com/login/device")!
        case .glm: return URL(string: "https://bigmodel.cn/login")!
        case .openrouter: return URL(string: "https://openrouter.ai/settings/keys")!
        case .groq: return URL(string: "https://console.groq.com/keys")!
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")!
        case .kimi: return URL(string: "https://platform.moonshot.ai/console/api-keys")!
        case .perplexity: return URL(string: "https://www.perplexity.ai/settings/api")!
        case .typhoon: return URL(string: "https://opentyphoon.ai/app/api-key")!
        case .qwen: return URL(string: "https://bailian.console.aliyun.com/?apiKey=1")!
        case .grok: return URL(string: "https://console.x.ai")!
        case .cerebras: return URL(string: "https://cloud.cerebras.ai")!
        case .together: return URL(string: "https://api.together.xyz/settings/api-keys")!
        case .fireworks: return URL(string: "https://fireworks.ai/account/api-keys")!
        case .minimax: return URL(string: "https://platform.minimax.io/user-center/basic-information/interface-key")!
        case .nvidia: return URL(string: "https://build.nvidia.com")!
        }
    }
    
    public var tokenHelpTitle: String {
        switch self {
        case .aipass: return "How to get TH-AI Passport Session Cookie"
        case .chatgpt: return "How to get ChatGPT Token"
        case .claude: return "How to get Claude Token"
        case .gemini: return "How to get Gemini Cookie"
        case .deepseek: return "How to get DeepSeek Token"
        case .copilot: return "How to get Copilot Token"
        case .glm: return "How to get GLM Token"
        case .openrouter: return "How to connect OpenRouter Web / Free Tier"
        case .groq: return "How to connect GroqCloud Developer Tier"
        case .mistral: return "How to connect Mistral Le Chat Pro / Console"
        case .kimi: return "How to connect Moonshot Kimi Web / Console"
        case .perplexity: return "How to connect Perplexity Pro / Sonar"
        case .typhoon: return "How to connect SCB 10X Typhoon Playground"
        case .qwen: return "How to connect Alibaba Qwen / DashScope"
        case .grok: return "How to connect xAI SuperGrok Console"
        case .cerebras: return "How to connect Cerebras Cloud Free Tier"
        case .together: return "How to connect Together AI Web Cloud"
        case .fireworks: return "How to connect Fireworks AI Web Console"
        case .minimax: return "How to connect MiniMax M2.7 / Hailuo Web"
        case .nvidia: return "How to connect NVIDIA NIM Developer Program"
        }
    }
    
    public var tokenGuideSteps: [String] {
        switch self {
        case .aipass:
            return [
                "1. Click '1-Click Sign In (Auto-Detect)' to log in at de.aipass.net/chat (captures HttpOnly cookie automatically).",
                "2. Or open DevTools (⌥⌘I) on de.aipass.net → Application → Cookies → copy '__Secure-ai_passport_auth.session_token'.",
                "3. Or right-click any request in Network tab → 'Copy as cURL' and paste directly below."
            ]
        case .chatgpt:
            return [
                "1. Click 'Open Web Portal' to sign in to chatgpt.com",
                "2. Press ⌥⌘I (DevTools) → Application → Cookies (chatgpt.com)",
                "3. Copy value of '__Secure-next-auth.session-token' or run `codex login` in Terminal and click 'Auto-detect CLI Auth'."
            ]
        case .claude:
            return [
                "1. Log in to claude.ai in browser or install Claude Code (`npm i -g @anthropic-ai/claude-code`)",
                "2. If using Claude Code, run `claude login` in Terminal then click 'Auto-detect CLI Auth'.",
                "3. Or in browser DevTools → Application → Cookies → copy 'sessionKey'."
            ]
        case .gemini:
            return [
                "1. Go to gemini.google.com with active Google One AI Premium subscription.",
                "2. Open DevTools (⌥⌘I) → Application → Cookies (gemini.google.com).",
                "3. Copy '__Secure-1PSID' cookie value and paste below."
            ]
        case .deepseek:
            return [
                "1. Go to chat.deepseek.com and sign in with your phone or email.",
                "2. Open DevTools (⌥⌘I) → Application → Local Storage (chat.deepseek.com).",
                "3. Copy 'userToken' value and paste below."
            ]
        case .copilot:
            return [
                "1. Open Terminal and run `gh auth login` with GitHub Copilot access.",
                "2. Click 'Auto-detect CLI Auth' above to import automatically.",
                "3. Or paste your personal access token (PAT) with copilot scopes."
            ]
        case .glm:
            return [
                "1. Go to bigmodel.cn/usercenter/proj-mgmt/apikeys",
                "2. Sign in with your subscription account.",
                "3. Copy your User/Authorization Token and paste below."
            ]
        case .openrouter:
            return [
                "1. Click '1-Click Sign In' to open openrouter.ai/settings/keys and sign in with Google/GitHub.",
                "2. Create a key (free models require 0 credits) — MicroCode auto-detects `sk-or-v1-...` on screen or you can paste it below."
            ]
        case .groq:
            return [
                "1. Click '1-Click Sign In' to open console.groq.com/keys.",
                "2. Generate a free GroqCloud key (`gsk_...`) — MicroCode auto-captures it or you can paste it below."
            ]
        case .mistral:
            return [
                "1. Click '1-Click Sign In' to open console.mistral.ai/api-keys.",
                "2. Copy your La Plateforme / Codestral token and paste it below."
            ]
        case .kimi:
            return [
                "1. Click '1-Click Sign In' to open platform.moonshot.ai/console/api-keys.",
                "2. Generate a Kimi key (`sk-...`) and paste it below."
            ]
        case .perplexity:
            return [
                "1. Click '1-Click Sign In' to open perplexity.ai/settings/api (Perplexity Pro includes $5/mo free Sonar credits).",
                "2. Copy your `pplx-...` token — MicroCode auto-detects it or you can paste it below."
            ]
        case .typhoon:
            return [
                "1. Click '1-Click Sign In' to open opentyphoon.ai/app/api-key.",
                "2. Sign in and copy your SCB 10X Typhoon token into the field below."
            ]
        case .qwen:
            return [
                "1. Click '1-Click Sign In' to open Alibaba Cloud ModelStudio / DashScope.",
                "2. Copy your `sk-...` DashScope token and paste it below."
            ]
        case .grok:
            return [
                "1. Click '1-Click Sign In' to open console.x.ai and sign in with your X / SuperGrok account.",
                "2. Create an `xai-...` token — MicroCode auto-detects it or you can paste it below."
            ]
        case .cerebras:
            return [
                "1. Click '1-Click Sign In' to open cloud.cerebras.ai (Free 1M tokens/day tier).",
                "2. Copy your `csk-...` token — MicroCode auto-detects it or you can paste it below."
            ]
        case .together:
            return [
                "1. Click '1-Click Sign In' to open api.together.xyz/settings/api-keys.",
                "2. Copy your Together AI token and paste it below."
            ]
        case .fireworks:
            return [
                "1. Click '1-Click Sign In' to open fireworks.ai/account/api-keys.",
                "2. Copy your `fw_...` token — MicroCode auto-detects it or you can paste it below."
            ]
        case .minimax:
            return [
                "1. Click '1-Click Sign In' to open platform.minimax.io.",
                "2. Copy your MiniMax Coding Plan / Interface key and paste it below."
            ]
        case .nvidia:
            return [
                "1. Click '1-Click Sign In' to open build.nvidia.com and click 'Get API Key'.",
                "2. Copy your `nvapi-...` token — MicroCode auto-detects it or you can paste it below."
            ]
        }
    }
    
    public var consoleExtractionSnippet: String {
        switch self {
        case .aipass:
            return "__Secure-ai_passport_auth.session_token (Application → Cookies → https://de.aipass.net)"
        case .chatgpt:
            return "(() => { const c = document.cookie.split('; '); const d = c.find(r => r.startsWith('__Secure-next-auth.session-token='))?.split('=')[1]; if (d) return d; const chunks = c.filter(r => r.trim().startsWith('__Secure-next-auth.session-token.')).sort().map(r => r.split('=')[1]).join(''); return chunks || localStorage.getItem('accessToken') || ''; })()"
        case .claude:
            return "document.cookie.split('; ').find(r => r.startsWith('sessionKey='))?.split('=')[1] || ''"
        case .gemini:
            return "document.cookie.split('; ').find(r => r.startsWith('__Secure-1PSID='))?.split('=')[1] || ''"
        case .deepseek:
            return "JSON.parse(localStorage.getItem('userToken') || '{}')?.value || localStorage.getItem('userToken') || ''"
        case .copilot:
            return "gh auth token"
        case .glm:
            return "localStorage.getItem('token') || ''"
        case .openrouter:
            return "https://openrouter.ai/settings/keys (sk-or-v1-...)"
        case .groq:
            return "https://console.groq.com/keys (gsk_...)"
        case .mistral:
            return "https://console.mistral.ai/api-keys"
        case .kimi:
            return "https://platform.moonshot.ai/console/api-keys"
        case .perplexity:
            return "https://www.perplexity.ai/settings/api (pplx-...)"
        case .typhoon:
            return "https://opentyphoon.ai/app/api-key"
        case .qwen:
            return "https://bailian.console.aliyun.com/?apiKey=1"
        case .grok:
            return "https://console.x.ai (xai-...)"
        case .cerebras:
            return "https://cloud.cerebras.ai (csk-...)"
        case .together:
            return "https://api.together.xyz/settings/api-keys"
        case .fireworks:
            return "https://fireworks.ai/account/api-keys (fw_...)"
        case .minimax:
            return "https://platform.minimax.io/user-center/basic-information/interface-key"
        case .nvidia:
            return "https://build.nvidia.com (nvapi-...)"
        }
    }
    
    public var helpInstruction: String {
        switch self {
        case .aipass:
            return "Uses your TH-AI Passport (de.aipass.net) account to access 35+ frontier models (Claude 5.5, GPT-6, Gemini 4/3.8, DeepSeek V4, GLM 5.3, Grok 4.7, Typhoon 2.5)."
        case .chatgpt:
            return "Uses your ChatGPT Plus/Pro session or Codex CLI token. Zero API per-token charges."
        case .claude:
            return "Uses Claude Code CLI auth (~/.claude) or session token from claude.ai."
        case .gemini:
            return "Uses Gemini Advanced (Google One AI Premium) session cookie."
        case .deepseek:
            return "Uses DeepSeek Web chat session (DeepSeek V3 & R1 reasoning free/unlimited)."
        case .copilot:
            return "Uses GitHub Copilot CLI session (~/.config/gh) or token."
        case .glm:
            return "Uses Zhipu BigModel GLM-4 Plus membership token."
        case .openrouter:
            return "Uses OpenRouter Web account (includes free `:free` models + 300+ frontier models)."
        case .groq:
            return "Uses GroqCloud Developer account (free high-speed LPU tier for Llama 3.3, QwQ, DeepSeek R1)."
        case .mistral:
            return "Uses Mistral Le Chat Pro / La Plateforme account (Codestral & Devstral SWE Agent)."
        case .kimi:
            return "Uses Moonshot AI Kimi K2.5 Web / Developer console account."
        case .perplexity:
            return "Uses Perplexity Pro ($5/mo included Sonar credits) for real-time web-grounded reasoning."
        case .typhoon:
            return "Uses SCB 10X OpenTyphoon Playground account for Thai sovereign LLMs (Typhoon v2.5 & R1)."
        case .qwen:
            return "Uses Alibaba Cloud Qwen / DashScope account (Qwen3-Coder-Plus, Qwen3-235B, QwQ-Plus)."
        case .grok:
            return "Uses xAI SuperGrok / X Premium+ Developer console account (Grok 4 & Grok 3)."
        case .cerebras:
            return "Uses Cerebras Cloud Free Tier (1M free tokens/day at 2,000+ tok/sec on Wafer-Scale Engine)."
        case .together:
            return "Uses Together AI Web Cloud account for open-weights clusters (DeepSeek V3/R1, Qwen3, Llama 4)."
        case .fireworks:
            return "Uses Fireworks AI Web Console account for low-latency FireAttention models."
        case .minimax:
            return "Uses MiniMax Coding Plan / Open Platform account (MiniMax M2.7 & M1 1M-context)."
        case .nvidia:
            return "Uses NVIDIA NIM Developer Program (1,000+ free credits at build.nvidia.com)."
        }
    }
}

public struct SubscriptionAccount: Identifiable, Codable {
    public var id: String
    public var provider: SubscriptionProviderType
    public var emailOrUser: String
    public var sessionToken: String
    public var isValid: Bool
    public var source: String
    public var expiresAt: Date?
    public var lastVerified: Date
    
    public init(id: String = UUID().uuidString,
                provider: SubscriptionProviderType,
                emailOrUser: String,
                sessionToken: String,
                isValid: Bool = true,
                source: String = "Manual",
                expiresAt: Date? = nil,
                lastVerified: Date = Date()) {
        self.id = id
        self.provider = provider
        self.emailOrUser = emailOrUser
        self.sessionToken = sessionToken
        self.isValid = isValid
        self.source = source
        self.expiresAt = expiresAt
        self.lastVerified = lastVerified
    }
}

public class SubscriptionAuthManager: ObservableObject {
    public static let shared = SubscriptionAuthManager()
    
    @Published public var activeProvider: SubscriptionProviderType = .chatgpt
    @Published public var accounts: [SubscriptionProviderType: SubscriptionAccount] = [:]
    @Published public var isVerifying: Bool = false
    @Published public var detectedSessionCount: Int = 0
    @Published public var lastDetectionMessage: String = ""
    
    private let userDefaultsKey = "microcode_subscription_accounts_v1"
    
    private init() {
        loadSavedAccounts()
        Task {
            await self.detectLocalCLISessions()
        }
    }
    
    public func isConnected(_ provider: SubscriptionProviderType) -> Bool {
        guard let acc = accounts[provider] else { return false }
        return acc.isValid && !acc.sessionToken.isEmpty && (acc.expiresAt.map { $0 > Date() } ?? true)
    }
    
    public var hasAnyConnected: Bool {
        return SubscriptionProviderType.allCases.contains { isConnected($0) }
    }
    
    public func connectedProviders() -> [SubscriptionProviderType] {
        return SubscriptionProviderType.allCases.filter { isConnected($0) }
    }
    
    public func connectedModelInfos() -> [SubscriptionModelInfo] {
        return connectedProviders().flatMap { $0.modelInfos }
    }
    
    public func allModelInfos() -> [SubscriptionModelInfo] {
        return SubscriptionProviderType.allCases.flatMap { $0.modelInfos }
    }
    
    public func findModel(id: String, provider: SubscriptionProviderType? = nil) -> SubscriptionModelInfo? {
        if let provider = provider {
            return provider.modelInfos.first(where: { $0.modelID == id })
        }
        if let active = connectedModelInfos().first(where: { $0.modelID == id && $0.provider == activeProvider }) {
            return active
        }
        return connectedModelInfos().first(where: { $0.modelID == id }) ?? allModelInfos().first(where: { $0.modelID == id })
    }
    
    public func getAccount(_ provider: SubscriptionProviderType) -> SubscriptionAccount? {
        return accounts[provider]
    }
    
    public func token(for provider: SubscriptionProviderType) -> String? {
        return accounts[provider]?.sessionToken
    }
    
    /// Subscription mode strictly uses MicroCode's Native Agent (`AgentService` + `AIClient`) and never spawns an external ACP CLI agent.
    @MainActor
    public func preferredCLIEngine(for provider: SubscriptionProviderType, model: String) -> String? {
        return nil
    }
    
    public static func setLiveModels(for provider: SubscriptionProviderType, models: [SubscriptionModelInfo]) {
        SubscriptionProviderType.setLiveModels(for: provider, models: models)
    }

    public static func registerCustomSubscriptionModel(provider: SubscriptionProviderType, modelId: String) {
        SubscriptionProviderType.registerCustomSubscriptionModel(provider: provider, modelId: modelId)
    }

    // MARK: - Live Model Fetching & Sync
    @MainActor
    public func fetchLiveModels(for provider: SubscriptionProviderType) async {
        if provider == .copilot {
            await AIModelCatalog.shared.fetchLiveCopilotModels()
        } else if provider == .aipass {
            await AIModelCatalog.shared.fetchLiveAiPassModels()
            syncLiveModelsFromCatalog(for: .aipass)
        } else {
            await AIModelCatalog.shared.fetchLiveModelsForProvider(provider.aiProviderID)
            syncLiveModelsFromCatalog(for: provider)
        }
    }

    @MainActor
    public func syncLiveModelsFromCatalog(for provider: SubscriptionProviderType) {
        let catalogProviderId = provider.aiProviderID
        if let catalogProv = AIModelCatalog.shared.provider(catalogProviderId) {
            var subModels: [SubscriptionModelInfo] = []
            var seenIds = Set<String>()
            
            // For ChatGPT Plus/Pro OAuth accounts (~/.codex/auth.json), keep Codex Backend models at the top
            if provider == .chatgpt {
                let token = accounts[.chatgpt]?.sessionToken ?? ""
                if !token.hasPrefix("sk-") {
                    for m in SubscriptionProviderType.chatgpt.defaultModelInfos {
                        if seenIds.insert(m.modelID).inserted {
                            subModels.append(m)
                        }
                    }
                }
            } else if provider == .gemini || provider == .claude {
                let token = accounts[provider]?.sessionToken ?? ""
                if token.hasPrefix("codeassist_oauth:") || token.hasPrefix("1//") {
                    for m in provider.defaultModelInfos {
                        if seenIds.insert(m.modelID).inserted {
                            subModels.append(m)
                        }
                    }
                }
            } else if provider == .aipass {
                for m in SubscriptionProviderType.aipass.defaultModelInfos {
                    if seenIds.insert(m.modelID).inserted {
                        subModels.append(m)
                    }
                }
            }
            
            for m in catalogProv.models {
                guard seenIds.insert(m.id).inserted else { continue }
                subModels.append(SubscriptionModelInfo(
                    modelID: m.id,
                    name: m.name,
                    provider: provider,
                    badge: m.badge,
                    description: "\(provider.displayName) live model: \(m.id)",
                    aiProviderID: provider.aiProviderID
                ))
            }
            if !subModels.isEmpty {
                Self.setLiveModels(for: provider, models: subModels)
            }
        }
    }
    
    /// Normalizes any pasted TH-AI Passport credential (raw session token, Cookie header, or Chrome DevTools Copy as cURL)
    /// into a ready-to-send Cookie header string containing `__Secure-ai_passport_auth.session_token=...`.
    public static func normalizeAiPassToken(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        
        // 1. Handle Chrome DevTools "Copy as cURL"
        if s.contains("curl ") || s.contains("-H ") || s.contains("-b ") {
            let patterns = [
                #"(?i)-H\s+['"]cookie:\s*([^'"]+)['"]"#,
                #"-b\s+['"]([^'"]+)['"]"#
            ]
            for pat in patterns {
                if let regex = try? NSRegularExpression(pattern: pat),
                   let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                   match.numberOfRanges > 1,
                   let r = Range(match.range(at: 1), in: s) {
                    s = String(s[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }
        
        // 2. Strip leading "Cookie:" or surrounding quotes
        if s.lowercased().hasPrefix("cookie:") {
            s = String(s.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 3. If it already contains `__Secure-ai_passport_auth.session_token=`, keep the full cookie string
        if s.contains("__Secure-ai_passport_auth.session_token=") {
            return s
        }
        if s.hasPrefix("ai_passport_auth.session_token=") {
            return "__Secure-" + s
        }
        
        // 4. Otherwise treat as raw value of `__Secure-ai_passport_auth.session_token`
        return "__Secure-ai_passport_auth.session_token=\(s)"
    }
    
    public static func isCorruptedToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "null" || trimmed == "undefined" || trimmed == "{}" {
            return true
        }
        if trimmed.contains("\"value\":null") || trimmed.contains("\"value\": null") {
            return true
        }
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            return true
        }
        if trimmed.hasPrefix("cli-oauth:") || trimmed.hasPrefix("eyJhbGciOiJkaXIi") || trimmed.hasPrefix("g.a000") {
            return true
        }
        return false
    }

    public func saveAccount(provider: SubscriptionProviderType, emailOrUser: String, sessionToken: String, source: String = "Manual") {
        let rawTrimmed = sessionToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = provider == .aipass ? Self.normalizeAiPassToken(rawTrimmed) : rawTrimmed
        guard !Self.isCorruptedToken(trimmedToken) else { return }
        
        // Also mirror direct API keys to BYOK storage so both modes stay in sync
        if trimmedToken.hasPrefix("sk-ant-api") {
            UserDefaults.standard.set(trimmedToken, forKey: "anthropic_api_key")
        } else if trimmedToken.hasPrefix("AIzaSy") {
            UserDefaults.standard.set(trimmedToken, forKey: "gemini_api_key")
        } else if trimmedToken.hasPrefix("sk-") && !trimmedToken.hasPrefix("sk-ant-") && provider == .chatgpt {
            UserDefaults.standard.set(trimmedToken, forKey: "openai_api_key")
        } else if trimmedToken.hasPrefix("sk-") && provider == .deepseek {
            UserDefaults.standard.set(trimmedToken, forKey: "deepseek_api_key")
        } else if provider == .aipass {
            UserDefaults.standard.set(trimmedToken, forKey: "aipass_api_key")
        } else if [.openrouter, .groq, .mistral, .kimi, .perplexity, .typhoon, .qwen, .grok, .cerebras, .together, .fireworks, .minimax, .nvidia].contains(provider) {
            UserDefaults.standard.set(trimmedToken, forKey: "\(provider.aiProviderID)_api_key")
        }
        
        let account = SubscriptionAccount(
            provider: provider,
            emailOrUser: emailOrUser.isEmpty ? "Active Subscriber" : emailOrUser,
            sessionToken: trimmedToken,
            isValid: true,
            source: source,
            lastVerified: Date()
        )
        guard saveTokenToKeychain(provider: provider.rawValue, token: trimmedToken) else {
            lastDetectionMessage = "Could not save the credential to Keychain. Please reconnect."
            return
        }
        accounts[provider] = account
        persistAccounts()
        
        if provider == .aipass {
            Task {
                await self.verifyAndFetchAiPassProfileAndModels(cookieHeader: trimmedToken)
            }
        } else if provider != .copilot {
            Task { @MainActor in
                await self.fetchLiveModels(for: provider)
            }
        }
    }
    
    /// Verifies TH-AI Passport session against `/lms/api/v1/session/session-tier` and `/loaders/list-models`
    public func verifyAndFetchAiPassProfileAndModels(cookieHeader: String) async {
        let normalizedCookie = Self.normalizeAiPassToken(cookieHeader)
        guard !normalizedCookie.isEmpty else { return }
        
        if let url = URL(string: "https://de.aipass.net/lms/api/v1/session/session-tier") {
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.setValue(normalizedCookie, forHTTPHeaderField: "Cookie")
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            req.setValue("https://de.aipass.net/chat", forHTTPHeaderField: "Referer")
            req.setValue("https://de.aipass.net", forHTTPHeaderField: "Origin")
            req.setValue("*/*", forHTTPHeaderField: "Accept")
            
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataObj = json["data"] as? [String: Any] {
                var displayParts: [String] = []
                if let userObj = dataObj["user"] as? [String: Any] {
                    if let email = userObj["email"] as? String, !email.isEmpty {
                        displayParts.append(email)
                    } else if let name = userObj["name"] as? String, !name.isEmpty {
                        displayParts.append(name)
                    }
                }
                if let memberObj = dataObj["member"] as? [String: Any],
                   let tierName = memberObj["tierName"] as? String, !tierName.isEmpty {
                    displayParts.append("(\(tierName))")
                }
                let finalUser = displayParts.joined(separator: " ")
                if !finalUser.isEmpty {
                    await MainActor.run {
                        if var acc = self.accounts[.aipass] {
                            acc.emailOrUser = finalUser
                            acc.lastVerified = Date()
                            self.accounts[.aipass] = acc
                            self.persistAccounts()
                        }
                    }
                }
            }
        }
        await AIModelCatalog.shared.fetchLiveAiPassModels()
    }
    
    public func disconnect(provider: SubscriptionProviderType) {
        if provider == .copilot {
            copilotLock.lock()
            cachedCopilotSessionToken = nil
            cachedCopilotSourceToken = nil
            copilotTokenExpiresAt = nil
            copilotLock.unlock()
        }
        accounts.removeValue(forKey: provider)
        deleteTokenFromKeychain(provider: provider.rawValue)
        persistAccounts()
    }
    
    /// Scans local CLI tools and verifies authentication with provider before registering
    public func detectLocalCLISessions() async {
        var detected = 0
        let home = FileManager.default.homeDirectoryForCurrentUser
        
        // 1. Check for Codex / OpenAI CLI auth (~/.codex/auth.json)
        let codexAuth = home.appendingPathComponent(".codex/auth.json")
        if FileManager.default.fileExists(atPath: codexAuth.path) {
            if let data = try? Data(contentsOf: codexAuth),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var email = "Codex Subscriber"
                var token = ""
                
                if let tokens = json["tokens"] as? [String: Any] {
                    if let access = tokens["access_token"] as? String, !access.isEmpty {
                        token = access
                    }
                }
                if token.isEmpty, let directToken = (json["access_token"] ?? json["token"] ?? json["OPENAI_API_KEY"]) as? String {
                    token = directToken
                }
                
                // Read email from id_token if available
                if let tokens = json["tokens"] as? [String: Any],
                   let idToken = tokens["id_token"] as? String {
                    let parts = idToken.components(separatedBy: ".")
                    if parts.count > 1, let payloadData = Data(base64Encoded: base64Padded(parts[1])),
                       let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                        if let mail = payload["email"] as? String, !mail.isEmpty {
                            email = mail
                        }
                    }
                }
                
                if !token.isEmpty {
                    let finalEmail = email.isEmpty ? "Codex CLI User" : email
                    let finalToken = token
                    if finalToken.hasPrefix("sk-") {
                        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
                        req.setValue("Bearer \(finalToken)", forHTTPHeaderField: "Authorization")
                        req.timeoutInterval = 5
                        if let (_, resp) = try? await URLSession.shared.data(for: req),
                           let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                            await MainActor.run {
                                self.saveAccount(provider: .chatgpt, emailOrUser: finalEmail, sessionToken: finalToken, source: "Codex CLI")
                            }
                            detected += 1
                        }
                    } else {
                        // OAuth token from Codex CLI (~/.codex/auth.json)
                        await MainActor.run {
                            self.saveAccount(provider: .chatgpt, emailOrUser: finalEmail, sessionToken: finalToken, source: "Codex CLI")
                        }
                        detected += 1
                    }
                }
            }
        }
        
        // 2. Check for Claude credentials (~/.claude.json, ~/.claude/config.json, or configured Anthropic key)
        let claudeHomeJson = home.appendingPathComponent(".claude.json")
        let claudeConfig = home.appendingPathComponent(".claude/config.json")
        var claudeToken: String?
        var claudeEmail = "Claude Pro / Max"
        if FileManager.default.fileExists(atPath: claudeHomeJson.path),
           let data = try? Data(contentsOf: claudeHomeJson),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let oauthAccount = json["oauthAccount"] as? [String: Any],
               let mail = (oauthAccount["emailAddress"] ?? oauthAccount["displayName"]) as? String, !mail.isEmpty {
                claudeEmail = mail
            }
            if let token = (json["apiKey"] ?? json["oauthToken"] ?? json["sessionKey"]) as? String,
               token.hasPrefix("sk-ant-api") {
                claudeToken = token
            }
        }
        if claudeToken == nil, FileManager.default.fileExists(atPath: claudeConfig.path) {
            if let data = try? Data(contentsOf: claudeConfig),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = (json["apiKey"] ?? json["oauthToken"] ?? json["sessionKey"]) as? String,
               token.hasPrefix("sk-ant-api") {
                claudeToken = token
            }
        }
        if claudeToken == nil {
            let resolved = await MainActor.run {
                ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
                    ?? ProcessInfo.processInfo.environment["CLAUDE_API_KEY"]
                    ?? AIModelCatalog.resolveKey("anthropic")
            }
            if resolved.hasPrefix("sk-ant-api") {
                claudeToken = resolved
            }
        }
        
        if let token = claudeToken, token.hasPrefix("sk-ant-api") {
            let finalClaudeEmail = claudeEmail
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
            req.setValue(token, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.timeoutInterval = 5
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                UserDefaults.standard.set(token, forKey: "anthropic_api_key")
                await MainActor.run {
                    self.saveAccount(provider: .claude, emailOrUser: finalClaudeEmail, sessionToken: token, source: "Anthropic Direct")
                }
                detected += 1
            }
        }
        
        // 3. Check for Google AI Ultra / Code Assist OAuth (~/.gemini/jetski-standalone-oauth-token) or Gemini API Key
        if let codeAssistCreds = await MainActor.run(body: { AIClient.loadGoogleCodeAssistCredentials(fallbackToken: "") }) {
            let oauthToken = "codeassist_oauth:\(codeAssistCreds.refreshToken)"
            await MainActor.run {
                self.saveAccount(provider: .gemini, emailOrUser: "\(codeAssistCreds.email) (Google AI Ultra)", sessionToken: oauthToken, source: "Google AI Ultra OAuth")
                if claudeToken == nil {
                    self.saveAccount(provider: .claude, emailOrUser: "\(codeAssistCreds.email) (Claude 5.5 Ultra)", sessionToken: oauthToken, source: "Vertex Claude 5.5 OAuth")
                }
            }
            detected += (claudeToken == nil ? 2 : 1)
        } else {
            let geminiKey: String = await MainActor.run {
                ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
                    ?? ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]
                    ?? AIModelCatalog.resolveKey("gemini")
            }
            if geminiKey.hasPrefix("AIzaSy") {
                await MainActor.run {
                    self.saveAccount(provider: .gemini, emailOrUser: "Google Gemini Advanced", sessionToken: geminiKey, source: "Google AI")
                }
                detected += 1
            }
        }
        
        // 4. Check for GitHub Copilot CLI session (~/.config/gh/hosts.yml or environment)
        let ghHosts = home.appendingPathComponent(".config/gh/hosts.yml")
        var ghToken: String?
        if FileManager.default.fileExists(atPath: ghHosts.path),
           let content = try? String(contentsOf: ghHosts, encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.starts(with: "oauth_token:") {
                    let parts = trimmed.split(separator: ":", maxSplits: 1)
                    if parts.count > 1 {
                        let tok = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !tok.isEmpty {
                            ghToken = tok
                            break
                        }
                    }
                }
            }
        }
        if ghToken == nil {
            ghToken = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ProcessInfo.processInfo.environment["GH_TOKEN"] ?? ProcessInfo.processInfo.environment["COPILOT_TOKEN"]
        }
        
        if let token = ghToken, !token.isEmpty {
            var req = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/v2/token")!)
            req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("vscode/1.95.0", forHTTPHeaderField: "Editor-Version")
            req.setValue("GitHubCopilot/1.155.0", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 5
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                await MainActor.run {
                    self.saveAccount(provider: .copilot, emailOrUser: "GitHub Copilot Active", sessionToken: token, source: "GitHub CLI")
                }
                detected += 1
            }
        }
        
        // 5. Check for DeepSeek
        let dsKey: String = await MainActor.run {
            ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? AIModelCatalog.resolveKey("deepseek")
        }
        if !dsKey.isEmpty {
            await MainActor.run {
                if !self.isConnected(.deepseek) {
                    self.saveAccount(provider: .deepseek, emailOrUser: "DeepSeek API", sessionToken: dsKey, source: "Direct / Env")
                }
            }
            detected += 1
        }
        
        // 6. Check for GLM / Zhipu / Z.AI International
        let glmKey: String = await MainActor.run {
            ProcessInfo.processInfo.environment["GLM_API_KEY"] ?? ProcessInfo.processInfo.environment["ZHIPU_API_KEY"] ?? AIModelCatalog.resolveKey("glm")
        }
        if !glmKey.isEmpty {
            await MainActor.run {
                self.saveAccount(provider: .glm, emailOrUser: "Z.AI GLM Coding Plan", sessionToken: glmKey, source: "Z.AI International")
            }
            detected += 1
        }
        
        // 7. Check for TH-AI Passport (de.aipass.net) in ~/.config/aipass-proxy/.env, environment, or WKWebView Cookie Store
        var aipassCookie: String? = ProcessInfo.processInfo.environment["AIPASS_SESSION_TOKEN"]
            ?? ProcessInfo.processInfo.environment["AIPASS_COOKIE"]
        if aipassCookie == nil {
            let envPaths = [
                home.appendingPathComponent(".config/aipass-proxy/.env"),
                home.appendingPathComponent(".aipass/.env")
            ]
            for envPath in envPaths where FileManager.default.fileExists(atPath: envPath.path) {
                if let content = try? String(contentsOf: envPath, encoding: .utf8) {
                    for line in content.components(separatedBy: .newlines) {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("AIPASS_SESSION_TOKEN=") || trimmed.hasPrefix("AIPASS_COOKIE=") {
                            let val = String(trimmed.split(separator: "=", maxSplits: 1).dropFirst().first ?? "")
                                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                            if !val.isEmpty {
                                aipassCookie = val
                                break
                            }
                        }
                    }
                }
                if aipassCookie != nil { break }
            }
        }
        if aipassCookie == nil {
            if let sharedCookies = HTTPCookieStorage.shared.cookies {
                let aipassList = sharedCookies.filter { $0.domain.contains("aipass.net") }
                if let sessionCookie = aipassList.first(where: { $0.name == "__Secure-ai_passport_auth.session_token" && !$0.value.isEmpty }) {
                    let header = aipassList.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                    aipassCookie = header.isEmpty ? "__Secure-ai_passport_auth.session_token=\(sessionCookie.value)" : header
                }
            }
        }
        if aipassCookie == nil {
            let wkCookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                        continuation.resume(returning: cookies)
                    }
                }
            }
            let aipassList = wkCookies.filter { $0.domain.contains("aipass.net") }
            if let sessionCookie = aipassList.first(where: { $0.name == "__Secure-ai_passport_auth.session_token" && !$0.value.isEmpty }) {
                let header = aipassList.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                aipassCookie = header.isEmpty ? "__Secure-ai_passport_auth.session_token=\(sessionCookie.value)" : header
            }
        }
        if let rawAiPass = aipassCookie, !rawAiPass.isEmpty {
            let normalized = Self.normalizeAiPassToken(rawAiPass)
            if !normalized.isEmpty {
                await MainActor.run {
                    self.saveAccount(provider: .aipass, emailOrUser: "TH-AI Passport Member", sessionToken: normalized, source: "TH-AI Passport Session")
                }
                detected += 1
            }
        }
        if self.isConnected(.aipass), let tok = self.token(for: .aipass) {
            await self.verifyAndFetchAiPassProfileAndModels(cookieHeader: tok)
        }
        
        // 8. Auto-detect additional Web / Developer Console Providers from Env or BYOK storage
        let additionalChecks: [(SubscriptionProviderType, [String], String)] = [
            (.openrouter, ["OPENROUTER_API_KEY"], "OpenRouter Web"),
            (.groq, ["GROQ_API_KEY"], "GroqCloud Developer"),
            (.mistral, ["MISTRAL_API_KEY", "CODESTRAL_API_KEY"], "Mistral Pro"),
            (.kimi, ["MOONSHOT_API_KEY", "KIMI_API_KEY"], "Moonshot Kimi Web"),
            (.perplexity, ["PERPLEXITY_API_KEY", "PPLX_API_KEY"], "Perplexity Pro"),
            (.typhoon, ["TYPHOON_API_KEY", "OPENTYPHOON_API_KEY"], "SCB 10X Typhoon"),
            (.qwen, ["DASHSCOPE_API_KEY", "QWEN_API_KEY"], "Alibaba Qwen"),
            (.grok, ["XAI_API_KEY", "GROK_API_KEY"], "xAI SuperGrok"),
            (.cerebras, ["CEREBRAS_API_KEY"], "Cerebras Cloud Free"),
            (.together, ["TOGETHER_API_KEY"], "Together AI Cloud"),
            (.fireworks, ["FIREWORKS_API_KEY"], "Fireworks AI"),
            (.minimax, ["MINIMAX_API_KEY"], "MiniMax Coding Plan"),
            (.nvidia, ["NVIDIA_API_KEY", "NGC_API_KEY"], "NVIDIA NIM Developer")
        ]
        for (subProv, envVars, label) in additionalChecks {
            let resolvedKey: String = await MainActor.run {
                for env in envVars {
                    if let val = ProcessInfo.processInfo.environment[env], !val.isEmpty {
                        return val
                    }
                }
                return AIModelCatalog.resolveKey(subProv.aiProviderID)
            }
            if !resolvedKey.isEmpty {
                await MainActor.run {
                    if !self.isConnected(subProv) {
                        self.saveAccount(provider: subProv, emailOrUser: label, sessionToken: resolvedKey, source: "Direct / Env")
                    }
                }
                detected += 1
            }
        }
        
        let finalDetected = detected
        await MainActor.run {
            AIModelCatalog.shared.syncAllSubscriptionModels()
            self.detectedSessionCount = finalDetected
            if finalDetected > 0 {
                self.lastDetectionMessage = "Detected \(finalDetected) active subscription session(s)."
            } else {
                self.lastDetectionMessage = "No verified subscriptions found. Please connect in settings or use Direct API Key."
            }
        }
    }
    
    private func fetchFromKeychainAsync(service: String) async -> String? {
        // Disabled: Spawning /usr/bin/security without user interaction triggers repeated
        // macOS system password dialogs ("MicroCode wants to access key in your keychain").
        return nil
    }
    
    private func fetchInternetPasswordFromKeychainAsync(server: String) async -> String? {
        // Disabled: Spawning /usr/bin/security without user interaction triggers repeated
        // macOS system password dialogs ("MicroCode wants to access key in your keychain").
        return nil
    }
    
    @discardableResult
    private func saveTokenToKeychain(provider: String, token: String) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.dotmini.microcode.subscription",
            kSecAttrAccount as String: provider
        ]
        let value = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func loadTokenFromKeychain(provider: String) -> String? {
        let service = "com.dotmini.microcode.subscription"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteTokenFromKeychain(provider: String) {
        let service = "com.dotmini.microcode.subscription"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    private func base64Padded(_ str: String) -> String {
        var base64 = str.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        return base64
    }
    
    // MARK: - Copilot Token Exchange
    private var cachedCopilotSessionToken: String?
    private var cachedCopilotSourceToken: String?
    private var copilotTokenExpiresAt: Date?
    private let copilotLock = NSLock()
    
    public func getCopilotSessionToken(githubToken: String) async throws -> String {
        copilotLock.lock()
        if cachedCopilotSourceToken == githubToken, let cached = cachedCopilotSessionToken,
           let expires = copilotTokenExpiresAt,
           expires > Date().addingTimeInterval(120) {
            copilotLock.unlock()
            return cached
        }
        copilotLock.unlock()
        
        let cleanToken = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            throw NSError(domain: "Copilot", code: 401, userInfo: [NSLocalizedDescriptionKey: "GitHub token is empty. Connect your GitHub Copilot subscription in Settings."])
        }
        
        // If the token is already a Copilot session token, return directly
        if cleanToken.contains(";") || cleanToken.contains("tid=") || cleanToken.contains("exp=") {
            return cleanToken.replacingOccurrences(of: "Bearer ", with: "")
        }
        
        var req = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/v2/token")!)
        let authPrefix = cleanToken.hasPrefix("gh") ? "token " : "Bearer "
        req.setValue("\(authPrefix)\(cleanToken)", forHTTPHeaderField: "Authorization")
        req.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        req.setValue("copilot-chat/0.24.0", forHTTPHeaderField: "Editor-Plugin-Version")
        req.setValue("GitHubCopilot/1.250.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Copilot", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response from GitHub Copilot auth."])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "Copilot", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub Copilot token exchange failed (HTTP \(http.statusCode)). Please verify that your GitHub account has an active Copilot subscription (Copilot Pro/Business/Enterprise)."])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionToken = json["token"] as? String, !sessionToken.isEmpty else {
            throw NSError(domain: "Copilot", code: 502, userInfo: [NSLocalizedDescriptionKey: "Could not parse Copilot session token from GitHub."])
        }
        
        let exp = (json["expires_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            ?? Date().addingTimeInterval(1800)
            
        copilotLock.lock()
        cachedCopilotSourceToken = githubToken
        cachedCopilotSessionToken = sessionToken
        copilotTokenExpiresAt = exp
        copilotLock.unlock()
        
        return sessionToken
    }
    
    // MARK: - Copilot Device Flow (Official VS Code Copilot OAuth)
    public func startCopilotDeviceFlow(
        onUserCode: @escaping (String, URL) -> Void,
        onSuccess: @escaping (SubscriptionAccount) -> Void,
        onError: @escaping (String) -> Void
    ) {
        Task {
            do {
                let clientId = "01ab8ac9400c4e429b23" // Official GitHub Copilot Client ID
                var req = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                let body = "client_id=\(clientId)&scope=read:user"
                req.httpBody = body.data(using: .utf8)
                
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let deviceCode = json["device_code"] as? String,
                      let userCode = json["user_code"] as? String,
                      let verifyUrlStr = json["verification_uri"] as? String,
                      let verifyUrl = URL(string: verifyUrlStr) else {
                    await MainActor.run { onError("Failed to request device authorization code from GitHub.") }
                    return
                }
                
                let interval = (json["interval"] as? Double) ?? 5.0
                let expiresIn = (json["expires_in"] as? Double) ?? 900.0
                
                // Copy user code to clipboard automatically
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(userCode, forType: .string)
                    onUserCode(userCode, verifyUrl)
                }
                
                // Poll for completion
                let startTime = Date()
                while Date().timeIntervalSince(startTime) < expiresIn {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    
                    var pollReq = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
                    pollReq.httpMethod = "POST"
                    pollReq.setValue("application/json", forHTTPHeaderField: "Accept")
                    pollReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    let pollBody = "client_id=\(clientId)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
                    pollReq.httpBody = pollBody.data(using: .utf8)
                    
                    if let (pollData, pollResp) = try? await URLSession.shared.data(for: pollReq),
                       let pollHttp = pollResp as? HTTPURLResponse, pollHttp.statusCode == 200,
                       let pollJson = try? JSONSerialization.jsonObject(with: pollData) as? [String: Any] {
                        
                        if let error = pollJson["error"] as? String {
                            if error == "authorization_pending" {
                                continue
                            } else if error == "slow_down" {
                                try? await Task.sleep(nanoseconds: 5_000_000_000)
                                continue
                            } else {
                                await MainActor.run { onError("GitHub authorization error: \(error)") }
                                return
                            }
                        }
                        
                        if let accessToken = pollJson["access_token"] as? String, !accessToken.isEmpty {
                            _ = try await self.getCopilotSessionToken(githubToken: accessToken)
                            let account = SubscriptionAccount(
                                provider: .copilot,
                                emailOrUser: "GitHub Copilot Active",
                                sessionToken: accessToken,
                                isValid: true,
                                source: "GitHub Device Auth"
                            )
                            await MainActor.run {
                                guard self.saveTokenToKeychain(provider: SubscriptionProviderType.copilot.rawValue, token: accessToken) else {
                                    onError("Could not save the Copilot credential to Keychain.")
                                    return
                                }
                                self.accounts[.copilot] = account
                                self.persistAccounts()
                                onSuccess(account)
                            }
                            return
                        }
                    }
                }
                
                await MainActor.run { onError("GitHub authorization timed out. Please try again.") }
            } catch {
                await MainActor.run { onError(error.localizedDescription) }
            }
        }
    }
    
    public func clearAllAccounts() {
        for provider in accounts.keys {
            deleteTokenFromKeychain(provider: provider.rawValue)
        }
        accounts.removeAll()
        copilotLock.lock()
        cachedCopilotSessionToken = nil
        cachedCopilotSourceToken = nil
        copilotTokenExpiresAt = nil
        copilotLock.unlock()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    private func persistAccounts() {
        // Only metadata leaves Keychain. Migrate older copies on every load.
        let metadata = accounts.mapValues { account in
            var copy = account
            copy.sessionToken = ""
            return copy
        }
        if let encoded = try? JSONEncoder().encode(metadata) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    private func loadSavedAccounts() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([SubscriptionProviderType: SubscriptionAccount].self, from: data) {
            var validAccounts: [SubscriptionProviderType: SubscriptionAccount] = [:]
            for (prov, acc) in decoded {
                var loadedToken = acc.sessionToken
                if let keychainToken = loadTokenFromKeychain(provider: prov.rawValue) {
                    loadedToken = keychainToken
                } else if !loadedToken.isEmpty {
                    guard saveTokenToKeychain(provider: prov.rawValue, token: loadedToken) else { continue }
                }
                let tok = loadedToken.trimmingCharacters(in: .whitespacesAndNewlines)
                if Self.isCorruptedToken(tok) {
                    deleteTokenFromKeychain(provider: prov.rawValue)
                    continue
                }
                if tok.hasPrefix("sk-ant-api") {
                    UserDefaults.standard.set(tok, forKey: "anthropic_api_key")
                } else if tok.hasPrefix("AIzaSy") {
                    UserDefaults.standard.set(tok, forKey: "gemini_api_key")
                }
                if acc.isValid && !tok.isEmpty {
                    var updatedAcc = acc
                    updatedAcc.sessionToken = tok
                    validAccounts[prov] = updatedAcc
                }
            }
            self.accounts = validAccounts
            persistAccounts()
        }
    }
}
