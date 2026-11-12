import Foundation
import IslandCore

/// Asks Claude what kind of music is playing and maps that to Music EQ (factory preset or bands).
actor MusicClaudeEQService {
    struct Advice: Sendable, Equatable {
        var genre: String
        var preset: String?
        var bass: Double
        var mid: Double
        var treble: Double
        var note: String?
    }

    enum Failure: LocalizedError {
        case auth(String)
        case network(String)
        case decode

        var errorDescription: String? {
            switch self {
            case .auth(let message): message
            case .network(let message): message
            case .decode: "Claude no devolvió un consejo de EQ usable."
            }
        }
    }

    private let reader = AICredentialReader()
    private var cache: [String: Advice] = [:]
    private let model = "claude-haiku-4-5-20251001"

    func hasAPIKey() async -> Bool { await reader.hasStoredAnthropicAPIKey() }
    func saveAPIKey(_ key: String) async throws { try await reader.saveAnthropicAPIKey(key) }
    func clearAPIKey() async { await reader.clearAnthropicAPIKey() }

    func advise(
        title: String,
        artist: String,
        presets: [String],
        interactiveAuth: Bool = false
    ) async throws -> Advice {
        let key = cacheKey(title: title, artist: artist)
        if let cached = cache[key] { return cached }

        let auth: ClaudeAPIAuth
        do {
            auth = try await reader.claudeAPIAuth(interactive: interactiveAuth)
        } catch {
            throw Failure.auth(error.localizedDescription)
        }

        let presetList = presets.filter { !$0.isEmpty && $0.caseInsensitiveCompare("Manual") != .orderedSame }
            .prefix(40)
            .joined(separator: ", ")
        let system = """
        You pick Apple Music equalizer settings for better listening.
        Reply with ONLY compact JSON (no markdown):
        {"genre":"short genre","preset":"Exact Factory Name or null","bass":-12..12,"mid":-12..12,"treble":-12..12,"note":"optional short reason"}
        Prefer a factory preset from this list when it fits: [\(presetList)].
        If none fits, set preset to null and use bass/mid/treble in dB (integers).
        Keep gains subtle (−6…+6) unless the genre clearly needs more.
        """
        let user = "Track: \"\(title)\" by \"\(artist.isEmpty ? "unknown" : artist)\"."

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        switch auth {
        case .oauth(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        case .apiKey(let key):
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 200,
            "temperature": 0,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(180) ?? ""
            if [401, 403].contains(code) {
                throw Failure.auth("Claude rechazó la autenticación (\(code)). Renueva «claude auth login» o la API key.")
            }
            throw Failure.network("Claude API \(code): \(snippet)")
        }

        guard let advice = parseAdvice(from: data, presets: presets) else { throw Failure.decode }
        cache[key] = advice
        if cache.count > 80 {
            cache.removeValue(forKey: cache.keys.first ?? key)
        }
        return advice
    }

    private func cacheKey(title: String, artist: String) -> String {
        "\(title.lowercased())|\(artist.lowercased())"
    }

    private func parseAdvice(from data: Data, presets: [String]) -> Advice? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let text: String
        if let content = root["content"] as? [[String: Any]] {
            text = content.compactMap { $0["text"] as? String }.joined()
        } else {
            return nil
        }
        let jsonText = extractJSONObject(from: text) ?? text
        guard let jsonData = jsonText.data(using: .utf8),
              let row = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }
        let genre = (row["genre"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        let note = (row["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bass = clampGain(row["bass"])
        let mid = clampGain(row["mid"])
        let treble = clampGain(row["treble"])
        var preset: String?
        if let raw = row["preset"] as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.lowercased() != "null",
               let match = presets.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                preset = match
            }
        }
        return Advice(genre: genre, preset: preset, bass: bass, mid: mid, treble: treble,
                      note: note?.isEmpty == true ? nil : note)
    }

    private func clampGain(_ value: Any?) -> Double {
        let number: Double
        if let n = value as? NSNumber { number = n.doubleValue }
        else if let s = value as? String, let n = Double(s) { number = n }
        else { number = 0 }
        return min(12, max(-12, number.rounded()))
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        return String(text[start...end])
    }
}
