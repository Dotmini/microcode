//
//  VoiceCodingService.swift
//  MicroCode
//
//  Feature 10: Voice Coding — macOS Speech Recognition to agent chat.
//  Uses SFSpeechRecognizer for on-device/cloud voice-to-text transcription,
//  isolated safely from @MainActor on CoreAudio & Speech XPC callbacks,
//  and guarded with ExceptionCatcher against CoreAudio NSExceptions.
//  Tirawat Nantamas Founder and CEO of Dotmini Software.
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation
import Speech
import AVFoundation
import AppKit
import MicroCodeSupport

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
    @Published var isAvailable: Bool = true
    @Published var recentTranscriptions: [VoiceTranscription] = []
    @Published var errorMessage: String?

    struct VoiceTranscription: Identifiable {
        let id = UUID()
        let text: String
        let timestamp: Date
        let confidence: Float
        var sentToAgent: Bool = false
    }

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var audioConfigObserver: NSObjectProtocol?
    private var activeSessionID = UUID()

    // Configuration
    private static let localeDefaultsKey = "voiceCodingLocale"
    @Published var locale: Locale
    var autoSendToAgent: Bool = true
    var silenceTimeoutSeconds: Double = 2.8
    private var silenceTimer: Task<Void, Never>?

    private init() {
        self.locale = Self.resolveDefaultLocale()
    }

    private static func resolveDefaultLocale() -> Locale {
        if let saved = UserDefaults.standard.string(forKey: localeDefaultsKey), !saved.isEmpty {
            return Locale(identifier: saved)
        }
        // Prefer Thai when Thai is among user's preferred macOS languages or region is Thailand
        let preferred = Locale.preferredLanguages.map { $0.lowercased() }
        if preferred.contains(where: { $0.hasPrefix("th") }) || Locale.current.region?.identifier == "TH" {
            return Locale(identifier: "th-TH")
        }
        return Locale(identifier: Locale.current.identifier)
    }

    private static var hasRequiredInfoPlistKeys: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let hasMic = (info["NSMicrophoneUsageDescription"] as? String)?.isEmpty == false
        let hasSpeech = (info["NSSpeechRecognitionUsageDescription"] as? String)?.isEmpty == false
        return hasMic && hasSpeech
    }

    // MARK: - Nonisolated Callback Bridges (Prevents Swift 6 @MainActor Runtime Traps!)

    /// Requests Microphone TCC access outside @MainActor so AVFoundation's background XPC callback never triggers `_swift_task_checkIsolated`.
    nonisolated private static func requestMicrophoneAccessOffMain() async -> Bool {
        let current = AVCaptureDevice.authorizationStatus(for: .audio)
        if current == .authorized { return true }
        if current == .denied || current == .restricted { return false }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Requests Speech Recognition TCC access outside @MainActor so Speech.framework's XPC callback never triggers `_swift_task_checkIsolated`.
    nonisolated private static func requestSpeechAuthOffMain() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Builds the CoreAudio realtime tap block in a strictly `nonisolated` context so `com.apple.audio.IOThread.client`
    /// never executes a `@MainActor` thunk (`EXC_BREAKPOINT` / `SIGTRAP`).
    nonisolated private static func makeRealtimeAudioTap(
        for request: SFSpeechAudioBufferRecognitionRequest
    ) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            guard buffer.frameLength > 0 else { return }
            request.append(buffer)
        }
    }

    /// Starts `SFSpeechRecognitionTask` in a `nonisolated` context so background Speech XPC callbacks hop safely via `Task { @MainActor in }`.
    nonisolated private static func startRecognitionTaskOffMain(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onEvent: @escaping @Sendable (_ transcript: String?, _ confidence: Float, _ isFinal: Bool, _ nsErrorDomain: String?, _ nsErrorCode: Int?, _ errorDesc: String?) -> Void
    ) -> SFSpeechRecognitionTask {
        return recognizer.recognitionTask(with: request) { result, error in
            let transcript = result?.bestTranscription.formattedString
            let confidence = result?.bestTranscription.segments.first?.confidence ?? 0.8
            let isFinal = result?.isFinal ?? false
            let nsErr = error as NSError?
            onEvent(transcript, confidence, isFinal, nsErr?.domain, nsErr?.code, error?.localizedDescription)
        }
    }

    // MARK: - Permissions & Availability

    func checkAvailability() {
        guard Self.hasRequiredInfoPlistKeys else {
            isAvailable = false
            return
        }
        let rec = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer = rec
        isAvailable = rec?.isAvailable ?? false
    }

    func requestPermission() async -> Bool {
        guard Self.hasRequiredInfoPlistKeys else {
            state = .error
            isAvailable = false
            errorMessage = "App bundle Info.plist is missing NSMicrophoneUsageDescription or NSSpeechRecognitionUsageDescription. Rebuild via ./build_dev.sh."
            return false
        }

        let micGranted = await Self.requestMicrophoneAccessOffMain()
        guard micGranted else {
            state = .noPermission
            isAvailable = false
            errorMessage = "ไม่ได้รับสิทธิ์ไมโครโฟน — เปิดได้ที่ System Settings → Privacy & Security → Microphone"
            return false
        }

        let speechStatus = await Self.requestSpeechAuthOffMain()
        switch speechStatus {
        case .authorized:
            isAvailable = true
            if state == .noPermission { state = .idle }
            return true
        case .denied, .restricted:
            state = .noPermission
            isAvailable = false
            errorMessage = "ไม่ได้รับสิทธิ์รู้จำเสียงพูด — เปิดได้ที่ System Settings → Privacy & Security → Speech Recognition"
            return false
        case .notDetermined:
            state = .idle
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Start / Stop Listening

    func startListening() async throws {
        errorMessage = nil

        let granted = await requestPermission()
        guard granted else {
            throw VoiceCodingError.permissionDenied
        }

        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw VoiceCodingError.audioSetupFailed("ไม่พบอุปกรณ์ไมโครโฟนที่เชื่อมต่ออยู่")
        }

        // Stop any existing session cleanly before creating a fresh engine
        teardownActiveRecognition(finalizePartial: false)

        let recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale.current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        self.speechRecognizer = recognizer

        guard let recognizer, recognizer.isAvailable else {
            throw VoiceCodingError.notAvailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = false
            request.addsPunctuation = true
        }
        self.recognitionRequest = request

        let engine = AVAudioEngine()
        self.audioEngine = engine
        let tapBlock = Self.makeRealtimeAudioTap(for: request)

        // Guard every CoreAudio / AVAudioEngine Objective-C call with ExceptionCatcher
        // so broken hardware sample rates or Bluetooth route glitches NEVER crash the app!
        var audioFormatErrorMsg: String? = nil
        do {
            try ExceptionCatcher.catchException {
                let inputNode = engine.inputNode
                inputNode.removeTap(onBus: 0)
                let hwFormat = inputNode.inputFormat(forBus: 0)
                let outputFormat = inputNode.outputFormat(forBus: 0)
                let chosenFormat = (outputFormat.sampleRate > 0 && outputFormat.channelCount > 0) ? outputFormat : hwFormat
                guard chosenFormat.sampleRate > 0 && chosenFormat.channelCount > 0 else {
                    audioFormatErrorMsg = "Invalid microphone audio format (\(chosenFormat.sampleRate) Hz, \(chosenFormat.channelCount) ch)"
                    return
                }
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: chosenFormat, block: tapBlock)
                engine.prepare()
            }
        } catch {
            teardownActiveRecognition(finalizePartial: false)
            throw VoiceCodingError.audioSetupFailed(error.localizedDescription)
        }

        if let audioFormatErrorMsg {
            teardownActiveRecognition(finalizePartial: false)
            throw VoiceCodingError.audioSetupFailed(audioFormatErrorMsg)
        }

        do {
            try ExceptionCatcher.catchException {
                try? engine.start()
            }
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            teardownActiveRecognition(finalizePartial: false)
            throw VoiceCodingError.audioSetupFailed(error.localizedDescription)
        }

        let sessionID = UUID()
        self.activeSessionID = sessionID
        self.state = .listening
        self.currentTranscription = ""

        NotificationCenter.default.post(
            name: .voiceCodingSessionStateChanged,
            object: nil,
            userInfo: ["listening": true]
        )

        // Gracefully handle AirPods / USB mic hot-plugging without crashing
        audioConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .listening else { return }
                self.stopListening()
            }
        }

        recognitionTask = Self.startRecognitionTaskOffMain(recognizer: recognizer, request: request) { [weak self] transcript, confidence, isFinal, errDomain, errCode, errDesc in
            Task { @MainActor [weak self] in
                guard let self, self.activeSessionID == sessionID else { return }

                if let text = transcript {
                    self.currentTranscription = text
                    NotificationCenter.default.post(
                        name: .voiceCodingLiveUpdate,
                        object: nil,
                        userInfo: ["text": text, "isFinal": isFinal]
                    )
                    self.resetSilenceTimer()

                    if isFinal {
                        self.finishTranscription(text: text, confidence: confidence)
                        return
                    }
                }

                if let errDesc {
                    // Ignore expected cancellation codes (216 / 301 / 1110 "No speech detected" on manual stop)
                    let ignoredCodes: Set<Int> = [216, 301, 203]
                    if errDomain == "kAFAssistantErrorDomain", let code = errCode, ignoredCodes.contains(code) {
                        self.teardownActiveRecognition(finalizePartial: true)
                        return
                    }
                    if errDomain == "kAFAssistantErrorDomain", errCode == 1110 {
                        // Silence / no speech detected
                        self.teardownActiveRecognition(finalizePartial: true)
                        return
                    }
                    self.errorMessage = errDesc
                    self.teardownActiveRecognition(finalizePartial: false)
                    self.state = .error
                }
            }
        }
    }

    func stopListening() {
        teardownActiveRecognition(finalizePartial: true)
    }

    private func teardownActiveRecognition(finalizePartial: Bool) {
        let pendingText = currentTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasListening = (state == .listening)

        activeSessionID = UUID()
        silenceTimer?.cancel()
        silenceTimer = nil

        if let obs = audioConfigObserver {
            NotificationCenter.default.removeObserver(obs)
            audioConfigObserver = nil
        }

        stopAudioEngine()

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        if finalizePartial && wasListening && !pendingText.isEmpty {
            finishTranscription(text: pendingText, confidence: 0.75)
        } else {
            currentTranscription = ""
            if state == .listening || state == .processing {
                state = .idle
            }
            NotificationCenter.default.post(
                name: .voiceCodingSessionStateChanged,
                object: nil,
                userInfo: ["listening": false]
            )
        }
    }

    func toggleListening() async {
        if state == .listening {
            stopListening()
        } else {
            do {
                try await startListening()
            } catch {
                errorMessage = error.localizedDescription
                if state != .noPermission {
                    state = .error
                }
            }
        }
    }

    // MARK: - Transcription Processing

    private func finishTranscription(text: String, confidence: Float) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            currentTranscription = ""
            state = .idle
            NotificationCenter.default.post(
                name: .voiceCodingSessionStateChanged,
                object: nil,
                userInfo: ["listening": false]
            )
            return
        }

        state = .processing

        let transcription = VoiceTranscription(
            text: cleaned,
            timestamp: Date(),
            confidence: confidence
        )
        recentTranscriptions.insert(transcription, at: 0)
        if recentTranscriptions.count > 50 {
            recentTranscriptions = Array(recentTranscriptions.prefix(50))
        }

        currentTranscription = ""
        state = .idle

        // Ensure audio engine is cleanly stopped once finalized
        stopAudioEngine()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        NotificationCenter.default.post(
            name: .voiceCodingSessionStateChanged,
            object: nil,
            userInfo: ["listening": false]
        )

        if autoSendToAgent {
            sendToAgent(text: cleaned)
        }
    }

    // MARK: - Send to Agent

    func sendToAgent(text: String) {
        if let idx = recentTranscriptions.firstIndex(where: { $0.text == text && !$0.sentToAgent }) {
            recentTranscriptions[idx].sentToAgent = true
        }

        NotificationCenter.default.post(
            name: .voiceCodingInput,
            object: nil,
            userInfo: ["text": text]
        )
    }

    func sendLatestToAgent() {
        guard let latest = recentTranscriptions.first, !latest.sentToAgent else { return }
        sendToAgent(text: latest.text)
    }

    // MARK: - Silence Detection

    private func resetSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.silenceTimeoutSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if self.state == .listening && !self.currentTranscription.isEmpty {
                self.stopListening()
            }
        }
    }

    // MARK: - Audio Engine

    private func stopAudioEngine() {
        guard let engine = audioEngine else { return }
        audioEngine = nil
        _ = try? ExceptionCatcher.catchException {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
            engine.reset()
        }
    }

    // MARK: - Locale Management

    func setLocale(_ identifier: String) {
        let wasListening = (state == .listening)
        if wasListening {
            stopListening()
        }
        locale = Locale(identifier: identifier)
        UserDefaults.standard.set(identifier, forKey: Self.localeDefaultsKey)
        if wasListening {
            Task { try? await startListening() }
        }
    }

    func supportedLocales() -> [Locale] {
        return Array(SFSpeechRecognizer.supportedLocales())
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        }
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
            return "ไม่ได้รับสิทธิ์ไมโครโฟนหรือการรู้จำเสียงพูด — กรุณาอนุญาตใน System Settings → Privacy & Security"
        case .notAvailable:
            return "ระบบรู้จำเสียงพูดยังไม่พร้อมใช้งานสำหรับภาษาที่เลือก"
        case .requestCreationFailed:
            return "ไม่สามารถสร้างคำขอรู้จำเสียงพูดได้"
        case .audioSetupFailed(let detail):
            return "ตั้งค่าไมโครโฟนไม่สำเร็จ: \(detail)"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let voiceCodingInput = Notification.Name("VoiceCodingInput")
    static let voiceCodingLiveUpdate = Notification.Name("VoiceCodingLiveUpdate")
    static let voiceCodingSessionStateChanged = Notification.Name("VoiceCodingSessionStateChanged")
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
