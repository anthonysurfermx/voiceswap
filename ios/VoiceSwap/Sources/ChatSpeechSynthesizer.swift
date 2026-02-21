/**
 * ChatSpeechSynthesizer.swift
 * VoiceSwap - TTS for BetWhisper chat responses
 *
 * Lightweight AVSpeechSynthesizer wrapper that:
 * - Auto-detects language (EN/ES) based on text content
 * - Routes audio through Bluetooth (glasses speakers) when connected
 * - Can be interrupted when user starts talking
 */

import Foundation
import AVFoundation

class ChatSpeechSynthesizer {

    private let synthesizer = AVSpeechSynthesizer()

    /// Speak text aloud. Auto-detects language.
    func speak(_ text: String) {
        // Stop any current speech first
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Auto language detection based on content
        let lang = detectLanguage(text)
        utterance.voice = AVSpeechSynthesisVoice(language: lang)

        synthesizer.speak(utterance)
    }

    /// Stop speaking immediately (e.g., when user starts talking)
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    // MARK: - Private

    private func detectLanguage(_ text: String) -> String {
        // Simple heuristic: check for common Spanish words/patterns
        let lower = text.lowercased()
        let spanishIndicators = [
            "mercado", "apuesta", "confirmad", "encontr", "escane",
            "probabilidad", "detectad", "analiz", "precio", "agente",
            "holders", "actividad", "invertir", "exito", "cuanto",
            "apostar", "busca", "resultado"
        ]
        let spanishCount = spanishIndicators.filter { lower.contains($0) }.count
        return spanishCount >= 2 ? "es-MX" : "en-US"
    }
}
