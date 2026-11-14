//
//  TextToSpeechService.swift
//  MicroCode
//
//  Native macOS Text-to-Speech (TTS) Service using NSSpeechSynthesizer
//  Supports multi-language speech output (Thai, English, Japanese, etc.)
//  with adjustable voice, rate, and pitch, completely independent of browser TTS.
//  Created by Dotmini Software.
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation
import AppKit
import AVFoundation

@MainActor
final class TextToSpeechService: NSObject, ObservableObject, NSSpeechSynthesizerDelegate {
    static let shared = TextToSpeechService()

    @Published var isSpeaking: Bool = false
    @Published var currentSpokenText: String = ""
    @Published var selectedVoiceIdentifier: String {
        didSet {
            UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "microcode.tts.voiceIdentifier")
            updateSynthesizerVoice()
        }
    }
    @Published var speakingRate: Float {
        didSet {
            UserDefaults.standard.set(speakingRate, forKey: "microcode.tts.rate")
            synthesizer.rate = speakingRate
        }
    }

    private let synthesizer = NSSpeechSynthesizer()

    private override init() {
        let savedVoice = UserDefaults.standard.string(forKey: "microcode.tts.voiceIdentifier") ?? NSSpeechSynthesizer.defaultVoice.rawValue
        let savedRate = UserDefaults.standard.float(forKey: "microcode.tts.rate")
        self.selectedVoiceIdentifier = savedVoice
        self.speakingRate = savedRate > 0 ? savedRate : 180.0 // Default 180 words per minute

        super.init()

        synthesizer.delegate = self
        synthesizer.rate = self.speakingRate
        updateSynthesizerVoice()
    }

    private func updateSynthesizerVoice() {
        let voiceID = NSSpeechSynthesizer.VoiceName(rawValue: selectedVoiceIdentifier)
        if NSSpeechSynthesizer.availableVoices.contains(voiceID) {
            synthesizer.setVoice(voiceID)
        } else if let fallback = NSSpeechSynthesizer.availableVoices.first {
            synthesizer.setVoice(fallback)
        }
    }

    func speak(_ text: String, languageCode: String? = nil) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking()
        }

        // Auto-select best voice matching requested language code if provided
        if let langCode = languageCode, !langCode.isEmpty {
            let matchingVoice = NSSpeechSynthesizer.availableVoices.first { voiceName in
                let attrs = NSSpeechSynthesizer.attributes(forVoice: voiceName)
                if let locale = attrs[.localeIdentifier] as? String, locale.localizedCaseInsensitiveContains(langCode) {
                    return true
                }
                return voiceName.rawValue.localizedCaseInsensitiveContains(langCode)
            }
            if let voice = matchingVoice {
                synthesizer.setVoice(voice)
            }
        }

        currentSpokenText = cleaned
        isSpeaking = true
        synthesizer.startSpeaking(cleaned)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking()
        }
        isSpeaking = false
        currentSpokenText = ""
    }

    func toggle(text: String) {
        if isSpeaking {
            stop()
        } else {
            speak(text)
        }
    }

    // MARK: - NSSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentSpokenText = ""
        }
    }

    // MARK: - Available Voices

    struct VoiceInfo: Identifiable, Hashable {
        let id: String // voice identifier
        let name: String
        let localeCode: String
        let localizedName: String
    }

    static func availableVoices() -> [VoiceInfo] {
        return NSSpeechSynthesizer.availableVoices.map { voiceName in
            let attrs = NSSpeechSynthesizer.attributes(forVoice: voiceName)
            let name = (attrs[.name] as? String) ?? voiceName.rawValue
            let localeCode = (attrs[.localeIdentifier] as? String) ?? "en_US"
            return VoiceInfo(
                id: voiceName.rawValue,
                name: name,
                localeCode: localeCode,
                localizedName: "\(name) (\(localeCode))"
            )
        }
    }
}
