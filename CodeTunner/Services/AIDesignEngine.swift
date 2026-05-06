//
//  AIDesignEngine.swift
//  CodeTunner
//
//  AI Design Generator — Universal AI Provider Support
//  Converts natural language prompts to Figma-like design layouts.
//  Works with ChatGPT, Gemini, Claude, DeepSeek, and more.
//
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import SwiftUI
import Foundation

// MARK: - AI Design Engine

@MainActor
class AIDesignEngine: ObservableObject {
    static let shared = AIDesignEngine()
    
    @Published var isGenerating = false
    @Published var status: String = ""
    @Published var chatHistory: [AIDesignMessage] = []
    
    // API Keys (loaded from UserDefaults)
    @AppStorage("ai_design_provider") var selectedProvider: String = "gemini"
    @AppStorage("ai_design_openai_key") var openaiKey: String = ""
    @AppStorage("ai_design_gemini_key") var geminiKey: String = ""
    @AppStorage("ai_design_claude_key") var claudeKey: String = ""
    @AppStorage("ai_design_deepseek_key") var deepseekKey: String = ""
    
    // MARK: - System Prompt
    
    private let systemPrompt = """
    You are an expert UI/UX designer. Generate design layouts as JSON arrays of elements.
    
    RULES:
    1. Output ONLY valid JSON — no markdown, no explanation, just the JSON array.
    2. Each element must have: type, name, x, y, width, height, and style properties.
    3. Use realistic spacing, padding (16-24px), and professional proportions.
    4. Start the first element at x:50, y:50 and work downward.
    5. For mobile designs, use 393x852 viewport (iPhone 16 Pro).
    6. For web designs, use 1440x900 viewport.
    
    AVAILABLE TYPES:
    "rectangle", "roundedRect", "ellipse", "text", "button", "card", "textField",
    "image", "navigationBar", "tabBar", "avatar", "badge", "divider", "label",
    "Device Frame", "line"
    
    STYLE PROPERTIES:
    - fill: {r, g, b, a} (0-1 range)
    - cornerRadius: number
    - fontSize: number (for text/button/label)
    - textContent: string (for text/button/label)
    - fontWeight: "Regular", "Medium", "Semibold", "Bold"
    - textAlignment: "left", "center", "right"
    - shadow: {x, y, blur, spread, isEnabled: true, color: {r,g,b,a}}
    - stroke: {r, g, b, a}
    - strokeWidth: number
    
    COLOR GUIDE:
    - Primary blue: {r:0.0, g:0.47, b:1.0, a:1.0}
    - Dark text: {r:0.1, g:0.1, b:0.1, a:1.0}
    - Subtle text: {r:0.5, g:0.5, b:0.5, a:1.0}
    - Light bg: {r:0.96, g:0.96, b:0.96, a:1.0}
    - Card white: {r:1.0, g:1.0, b:1.0, a:1.0}
    - Separator: {r:0.9, g:0.9, b:0.9, a:1.0}
    
    EXAMPLE OUTPUT for "Create a login form":
    [
      {"type":"card","name":"Login Card","x":46,"y":200,"width":300,"height":340,
       "style":{"fill":{"r":1,"g":1,"b":1,"a":1},"cornerRadius":16,
       "shadow":{"x":0,"y":8,"blur":24,"spread":0,"isEnabled":true,"color":{"r":0,"g":0,"b":0,"a":0.1}}}},
      {"type":"text","name":"Title","x":66,"y":230,"width":260,"height":36,
       "style":{"textContent":"Welcome Back","fontSize":28,"fontWeight":"Bold",
       "fill":{"r":0.1,"g":0.1,"b":0.1,"a":1},"textAlignment":"center"}},
      {"type":"textField","name":"Email","x":66,"y":290,"width":260,"height":44,
       "style":{"fill":{"r":0.96,"g":0.96,"b":0.96,"a":1},"cornerRadius":8,
       "textContent":"Email","fontSize":14}},
      {"type":"textField","name":"Password","x":66,"y":350,"width":260,"height":44,
       "style":{"fill":{"r":0.96,"g":0.96,"b":0.96,"a":1},"cornerRadius":8,
       "textContent":"Password","fontSize":14}},
      {"type":"button","name":"Login Button","x":66,"y":420,"width":260,"height":48,
       "style":{"fill":{"r":0,"g":0.47,"b":1,"a":1},"cornerRadius":12,
       "textContent":"Sign In","fontSize":16,"fontWeight":"Semibold"}}
    ]
    """
    
    // MARK: - Generate Design
    
    func generateDesign(prompt: String, designStore: DesignStore) async {
        guard !prompt.isEmpty else { return }
        
        isGenerating = true
        status = "🎨 Designing..."
        
        // Add user message to chat
        chatHistory.append(AIDesignMessage(role: .user, content: prompt))
        
        do {
            let jsonResponse = try await callAI(prompt: prompt)
            status = "🔧 Building layout..."
            
            // Parse elements from JSON
            let elements = try parseDesignJSON(jsonResponse)
            
            // Add to canvas
            for element in elements {
                designStore.addElement(element)
            }
            
            // Add AI response to chat
            chatHistory.append(AIDesignMessage(
                role: .assistant,
                content: "✅ Created \(elements.count) elements on canvas.",
                elementCount: elements.count
            ))
            
            status = "✅ \(elements.count) elements created"
            
        } catch {
            status = "❌ \(error.localizedDescription)"
            chatHistory.append(AIDesignMessage(role: .assistant, content: "❌ Error: \(error.localizedDescription)"))
        }
        
        isGenerating = false
    }
    
    // MARK: - AI Provider Router
    
    private func callAI(prompt: String) async throws -> String {
        switch selectedProvider {
        case "openai":
            return try await callOpenAI(prompt)
        case "gemini":
            return try await callGemini(prompt)
        case "claude":
            return try await callClaude(prompt)
        case "deepseek":
            return try await callDeepSeek(prompt)
        default:
            return try await callGemini(prompt)
        }
    }
    
    // MARK: - OpenAI (ChatGPT)
    
    private func callOpenAI(_ prompt: String) async throws -> String {
        guard !openaiKey.isEmpty else { throw AIDesignError.missingKey("OpenAI") }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(openaiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Design: \(prompt). Output ONLY the JSON array."]
            ],
            "max_tokens": 4096,
            "temperature": 0.7
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let choices = json?["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        throw AIDesignError.invalidResponse
    }
    
    // MARK: - Google Gemini
    
    private func callGemini(_ prompt: String) async throws -> String {
        guard !geminiKey.isEmpty else { throw AIDesignError.missingKey("Gemini") }
        
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(geminiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        
        let body: [String: Any] = [
            "contents": [[
                "parts": [["text": "\(systemPrompt)\n\nDesign: \(prompt). Output ONLY the JSON array."]]
            ]],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 8192,
                "responseMimeType": "application/json"
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let candidates = json?["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let text = parts.first?["text"] as? String {
            return text
        }
        throw AIDesignError.invalidResponse
    }
    
    // MARK: - Anthropic Claude
    
    private func callClaude(_ prompt: String) async throws -> String {
        guard !claudeKey.isEmpty else { throw AIDesignError.missingKey("Claude") }
        
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(claudeKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": "Design: \(prompt). Output ONLY the JSON array."]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let content = json?["content"] as? [[String: Any]],
           let text = content.first?["text"] as? String {
            return text
        }
        throw AIDesignError.invalidResponse
    }
    
    // MARK: - DeepSeek
    
    private func callDeepSeek(_ prompt: String) async throws -> String {
        guard !deepseekKey.isEmpty else { throw AIDesignError.missingKey("DeepSeek") }
        
        let url = URL(string: "https://api.deepseek.com/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(deepseekKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        
        let body: [String: Any] = [
            "model": "deepseek-chat",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Design: \(prompt). Output ONLY the JSON array."]
            ],
            "max_tokens": 4096
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let choices = json?["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        throw AIDesignError.invalidResponse
    }
    
    // MARK: - JSON Parser
    
    private func parseDesignJSON(_ raw: String) throws -> [DesignElement] {
        // Extract JSON array from response (handle markdown wrapping)
        var jsonStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strip markdown code blocks
        if jsonStr.hasPrefix("```json") { jsonStr = String(jsonStr.dropFirst(7)) }
        if jsonStr.hasPrefix("```") { jsonStr = String(jsonStr.dropFirst(3)) }
        if jsonStr.hasSuffix("```") { jsonStr = String(jsonStr.dropLast(3)) }
        jsonStr = jsonStr.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find JSON array bounds
        if let start = jsonStr.firstIndex(of: "["),
           let end = jsonStr.lastIndex(of: "]") {
            jsonStr = String(jsonStr[start...end])
        }
        
        guard let data = jsonStr.data(using: .utf8),
              let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw AIDesignError.parseError
        }
        
        var elements: [DesignElement] = []
        
        for item in items {
            let typeStr = item["type"] as? String ?? "rectangle"
            let type = mapType(typeStr)
            let name = item["name"] as? String ?? typeStr
            let x = cgFloat(item["x"])
            let y = cgFloat(item["y"])
            let w = cgFloat(item["width"], default: 100)
            let h = cgFloat(item["height"], default: 100)
            
            var element = DesignElement.create(type: type, x: x, y: y)
            element.name = name
            element.width = w
            element.height = h
            
            // Parse style
            if let styleDict = item["style"] as? [String: Any] {
                if let fill = styleDict["fill"] as? [String: Any] {
                    element.style.fill = parseColor(fill)
                }
                if let stroke = styleDict["stroke"] as? [String: Any] {
                    element.style.stroke = parseColor(stroke)
                }
                if let sw = styleDict["strokeWidth"] as? Double {
                    element.style.strokeWidth = CGFloat(sw)
                }
                if let cr = styleDict["cornerRadius"] as? Double {
                    element.style.cornerRadius = CGFloat(cr)
                }
                if let fs = styleDict["fontSize"] as? Double {
                    element.style.fontSize = CGFloat(fs)
                }
                if let tc = styleDict["textContent"] as? String {
                    element.style.textContent = tc
                }
                if let fw = styleDict["fontWeight"] as? String {
                    element.style.fontWeight = fw
                }
                if let ta = styleDict["textAlignment"] as? String {
                    element.style.textAlignment = ta
                }
                if let op = styleDict["opacity"] as? Double {
                    element.style.opacity = op
                }
                if let shadowDict = styleDict["shadow"] as? [String: Any] {
                    element.style.shadow.isEnabled = shadowDict["isEnabled"] as? Bool ?? true
                    element.style.shadow.x = cgFloat(shadowDict["x"])
                    element.style.shadow.y = cgFloat(shadowDict["y"], default: 4)
                    element.style.shadow.blur = cgFloat(shadowDict["blur"], default: 8)
                    element.style.shadow.spread = cgFloat(shadowDict["spread"])
                    if let sc = shadowDict["color"] as? [String: Any] {
                        element.style.shadow.color = parseColor(sc)
                    }
                }
            }
            
            elements.append(element)
        }
        
        return elements
    }
    
    // MARK: - Helpers
    
    private func mapType(_ str: String) -> DesignElementType {
        switch str.lowercased() {
        case "rectangle", "rect": return .rectangle
        case "roundedrect", "rounded_rect", "rounded rectangle": return .roundedRect
        case "ellipse", "circle": return .ellipse
        case "text": return .text
        case "button": return .button
        case "card": return .card
        case "textfield", "input", "text_field": return .textField
        case "image", "img": return .image
        case "navigationbar", "navbar", "nav_bar", "navigation bar": return .navigationBar
        case "tabbar", "tab_bar", "tab bar": return .tabBar
        case "avatar": return .avatar
        case "badge": return .badge
        case "divider", "separator": return .divider
        case "label": return .label
        case "line": return .line
        case "device frame", "frame", "device_frame": return .deviceFrame
        case "star": return .star
        case "checkbox": return .checkbox
        case "switch", "toggle": return .switchToggle
        case "slider": return .slider
        case "progress", "progressbar", "progress bar": return .progress
        case "modal", "dialog": return .modal
        case "menu": return .menu
        case "list": return .list
        default: return .rectangle
        }
    }
    
    private func parseColor(_ dict: [String: Any]) -> DesignColor {
        DesignColor(
            r: (dict["r"] as? Double) ?? 0.5,
            g: (dict["g"] as? Double) ?? 0.5,
            b: (dict["b"] as? Double) ?? 0.5,
            a: (dict["a"] as? Double) ?? 1.0
        )
    }
    
    private func cgFloat(_ val: Any?, default d: CGFloat = 0) -> CGFloat {
        if let v = val as? Double { return CGFloat(v) }
        if let v = val as? Int { return CGFloat(v) }
        return d
    }
}

// MARK: - Models

struct AIDesignMessage: Identifiable {
    let id = UUID()
    let role: AIRole
    let content: String
    var elementCount: Int = 0
    let timestamp = Date()
    
    enum AIRole {
        case user, assistant
    }
}

enum AIDesignError: LocalizedError {
    case missingKey(String)
    case invalidResponse
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .missingKey(let provider): return "API Key for \(provider) is missing. Set it in AI Design settings."
        case .invalidResponse: return "Could not parse AI response"
        case .parseError: return "Failed to parse design JSON"
        }
    }
}
