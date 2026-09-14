//
//  VoiceCodingService.swift
//  MicroCode
//
//  Feature 10: Voice Coding — macOS Speech Recognition to agent chat.
//  Uses SFSpeechRecognizer for on-device voice-to-text transcription,
//  then feeds the result into the AI agent conversation.
//  Tirawat Nantamas Founder and CEO of Dotmini Software.
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import Foundation
import Speech
import AVFoundation

// MARK: - Voice Coding State

enum VoiceCodingState: String {
    case idle = "Idle"
    case listening = "Listening"
    case processing = "Processing"
    case error = "Error"
    case noPermission = "No Permission"
}

// MARK: - Voice Coding Service

@MainActor
class VoiceCodingService: ObservableObject {
    
    static let shared = VoiceCodingService()
    
    @Published var state: VoiceCodingState = .idle
    @Published var currentTranscription: String = ""
    @Published var isAvailable: Bool = false
    @Published var recentTranscriptions: [VoiceTranscription] = []
    @Published var errorMessage: String?
    
    struct VoiceTranscription: Identifiable {
        let id = UUID()
        let text: String
        let timestamp: Date
        let confidence: Float
        var sentToAgent: Bool = false
    }
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // Configuration
    var locale: Locale = Locale(identifier: "en-US")
    var autoSendToAgent: Bool = true
    var silenceTimeoutSeconds: Double = 3.0
    private var silenceTimer: Task<Void, Never>?
    
    private init() {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        checkAvailability()
    }
    
    // MARK: - Permissions & Availability
    
    func checkAvailability() {
        guard let recognizer = speechRecognizer else {
            isAvailable = false
            return
        }
        isAvailable = recognizer.isAvailable
    }
    
    func requestPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    switch status {
                    case .authorized:
                        self.isAvailable = true
                        self.state = .idle
                        continuation.resume(returning: true)
                    case .denied, .restricted:
                        self.state = .noPermission
                        self.isAvailable = false
                        self.errorMessage = "Speech recognition permission denied. Enable in System Settings → Privacy → Speech Recognition."
                        continuation.resume(returning: false)
                    case .notDetermined:
                        self.state = .idle
                        continuation.resume(returning: false)
                    @unknown default:
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }
    
    // MARK: - Start / Stop Listening
    
    func startListening() async throws {
        // Check permission
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus != .authorized {
            let granted = await requestPermission()
            if !granted {
                throw VoiceCodingError.permissionDenied
            }
        }
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw VoiceCodingError.notAvailable
        }
        
        // Stop any existing session
        stopListening()
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            throw VoiceCodingError.requestCreationFailed
        }
        
        request.shouldReportPartialResults = true
        
        // Enable on-device recognition if available (privacy + speed)
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = false // Fall back to server if needed
        }
        
        // Configure audio session
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Validate format
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw VoiceCodingError.audioSetupFailed("Invalid audio format: sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount)")
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()
        
        state = .listening
        currentTranscription = ""
        errorMessage = nil
        
        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.currentTranscription = text
                    
                    // Reset silence timer on new text
                    self.resetSilenceTimer()
                    
                    if result.isFinal {
                        self.finishTranscription(text: text, confidence: result.bestTranscription.segments.first?.confidence ?? 0)
                    }
                }
                
                if let error = error {
                    // Ignore cancellation errors (expected when stopping)
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        self.errorMessage = error.localizedDescription
                        self.state = .error
                        print("❌ [VoiceCoding] Recognition error: \(error)")
                    }
                    self.stopAudioEngine()
                }
            }
        }
        
        print("🎤 [VoiceCoding] Started listening...")
    }
    
    func stopListening() {
        silenceTimer?.cancel()
        silenceTimer = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        stopAudioEngine()
        
        // If we have partial transcription, finalize it
        if !currentTranscription.isEmpty && state == .listening {
            finishTranscription(text: currentTranscription, confidence: 0.5)
        }
        
        state = .idle
    }
    
    func toggleListening() async {
        if state == .listening {
            stopListening()
        } else {
            do {
                try await startListening()
            } catch {
                errorMessage = error.localizedDescription
                state = .error
            }
        }
    }
    
    // MARK: - Transcription Processing
    
    private func finishTranscription(text: String, confidence: Float) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        state = .processing
        
        let transcription = VoiceTranscription(
            text: text,
            timestamp: Date(),
            confidence: confidence
        )
        recentTranscriptions.insert(transcription, at: 0)
        
        // Keep max 50 transcriptions
        if recentTranscriptions.count > 50 {
            recentTranscriptions = Array(recentTranscriptions.prefix(50))
        }
        
        print("🎤 [VoiceCoding] Transcription: \"\(text)\" (confidence: \(String(format: "%.2f", confidence)))")
        
        currentTranscription = ""
        state = .idle
        
        if autoSendToAgent {
            sendToAgent(text: text)
        }
    }
    
    // MARK: - Send to Agent
    
    func sendToAgent(text: String) {
        // Mark as sent
        if let idx = recentTranscriptions.firstIndex(where: { $0.text == text && !$0.sentToAgent }) {
            recentTranscriptions[idx].sentToAgent = true
        }
        
        // Post notification for agent to pick up
        NotificationCenter.default.post(
            name: .voiceCodingInput,
            object: nil,
            userInfo: ["text": text]
        )
        
        print("🎤→🤖 [VoiceCoding] Sent to agent: \"\(text.prefix(60))...\"")
    }
    
    func sendLatestToAgent() {
        guard let latest = recentTranscriptions.first, !latest.sentToAgent else { return }
        sendToAgent(text: latest.text)
    }
    
    // MARK: - Silence Detection
    
    private func resetSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(silenceTimeoutSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            
            // Auto-stop after silence
            if self.state == .listening && !self.currentTranscription.isEmpty {
                self.stopListening()
            }
        }
    }
    
    // MARK: - Audio Engine
    
    private func stopAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }
    
    // MARK: - Locale Management
    
    func setLocale(_ identifier: String) {
        locale = Locale(identifier: identifier)
        // Must recreate recognizer for new locale — handled on next startListening
    }
    
    func supportedLocales() -> [Locale] {
        return Array(SFSpeechRecognizer.supportedLocales())
    }
}

// MARK: - Errors

enum VoiceCodingError: LocalizedError {
    case permissionDenied
    case notAvailable
    case requestCreationFailed
    case audioSetupFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech recognition permission denied. Enable in System Settings → Privacy → Speech Recognition."
        case .notAvailable:
            return "Speech recognition is not available on this device."
        case .requestCreationFailed:
            return "Failed to create speech recognition request."
        case .audioSetupFailed(let detail):
            return "Audio setup failed: \(detail)"
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let voiceCodingInput = Notification.Name("VoiceCodingInput")
}

// MARK: - Agent Tool

struct VoiceCodingTool: AgentTool {
    let name = "voice_coding"
    let description = "Control voice coding: start/stop speech recognition, check status, send transcription to agent, or change language. Voice input is transcribed on-device and can be used as agent commands."
    let parameters = [
        ToolParameter(name: "action", type: "string", description: "Action: 'start', 'stop', 'toggle', 'status', 'send', 'locale'", required: true),
        ToolParameter(name: "text", type: "string", description: "Text to send to agent (for 'send' action)", required: false),
        ToolParameter(name: "locale_id", type: "string", description: "Locale identifier e.g. 'th-TH', 'en-US', 'ja-JP' (for 'locale' action)", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let action = params["action"] as? String else {
            throw ToolBoxError.invalidParams("Missing 'action'")
        }
        
        switch action.lowercased() {
        case "start":
            // startListening() is @MainActor async throws — auto-dispatches to MainActor
            try await VoiceCodingService.shared.startListening()
            return "🎤 Voice coding started. Listening for speech..."
            
        case "stop":
            await MainActor.run {
                VoiceCodingService.shared.stopListening()
            }
            return "🎤 Voice coding stopped."
            
        case "toggle":
            await VoiceCodingService.shared.toggleListening()
            let stateVal = await MainActor.run { VoiceCodingService.shared.state.rawValue }
            return "🎤 Voice coding: \(stateVal)"
            
        case "status":
            let output: String = await MainActor.run {
                let service = VoiceCodingService.shared
                var out = "Voice Coding Status:\n"
                out += "• State: \(service.state.rawValue)\n"
                out += "• Available: \(service.isAvailable)\n"
                out += "• Locale: \(service.locale.identifier)\n"
                out += "• Auto-send: \(service.autoSendToAgent)\n"
                
                if !service.currentTranscription.isEmpty {
                    out += "• Current: \"\(service.currentTranscription)\"\n"
                }
                
                if !service.recentTranscriptions.isEmpty {
                    out += "\nRecent Transcriptions:\n"
                    for t in service.recentTranscriptions.prefix(5) {
                        let sent = t.sentToAgent ? "✓" : "○"
                        out += "  \(sent) \"\(t.text.prefix(60))\"\n"
                    }
                }
                
                if let err = service.errorMessage {
                    out += "\n⚠️ Error: \(err)\n"
                }
                
                return out
            }
            return output
            
        case "send":
            if let text = params["text"] as? String, !text.isEmpty {
                await MainActor.run {
                    VoiceCodingService.shared.sendToAgent(text: text)
                }
                return "Sent to agent: \"\(text.prefix(60))\""
            } else {
                await MainActor.run {
                    VoiceCodingService.shared.sendLatestToAgent()
                }
                return "Sent latest transcription to agent."
            }
            
        case "locale":
            guard let localeId = params["locale_id"] as? String else {
                let locales: [String] = await MainActor.run {
                    VoiceCodingService.shared.supportedLocales().map { $0.identifier }.sorted()
                }
                return "Supported locales (\(locales.count)):\n\(locales.joined(separator: ", "))"
            }
            await MainActor.run {
                VoiceCodingService.shared.setLocale(localeId)
            }
            return "Voice coding locale set to: \(localeId)"
            
        default:
            throw ToolBoxError.invalidParams("Unknown action '\(action)'. Use: start, stop, toggle, status, send, locale")
        }
    }
}
