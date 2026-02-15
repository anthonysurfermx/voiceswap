import Foundation

enum GeminiConfig {
    /// Load API key from Secrets.plist (not tracked in git)
    private static let bundledKey: String = {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key = dict["GEMINI_API_KEY"] as? String else {
            return ""
        }
        return key
    }()

    static var apiKey: String {
        get {
            // 1. Check UserDefaults (override)
            if let saved = UserDefaults.standard.string(forKey: "gemini_api_key"), !saved.isEmpty {
                return saved
            }
            // 2. Use bundled key from Secrets.plist
            return bundledKey
        }
        set { UserDefaults.standard.set(newValue, forKey: "gemini_api_key") }
    }

    static var isConfigured: Bool { !apiKey.isEmpty }

    static let websocketBaseURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    static let model = "models/gemini-2.5-flash-native-audio-latest"

    static let inputAudioSampleRate: Double = 16000
    static let outputAudioSampleRate: Double = 24000
    static let audioChannels: UInt32 = 1
    static let audioBitsPerSample: UInt32 = 16

    static let videoFrameInterval: TimeInterval = 1.0
    static let videoJPEGQuality: CGFloat = 0.5

    static func websocketURL() -> URL? {
        guard isConfigured else { return nil }
        return URL(string: "\(websocketBaseURL)?key=\(apiKey)")
    }
}
