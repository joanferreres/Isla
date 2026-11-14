import Foundation
import IslandCore

/// Asks Claude (preferred) or ChatGPT what kind of music is playing and maps that to Music EQ.
actor MusicClaudeEQService {
    struct Advice: Sendable, Equatable {
        var genre: String
        var preset: String?
        var bass: Double
        var mid: Double
        var treble: Double
        var note: String?
        var provider: String = "Claude"
    }

    enum Failure: LocalizedError {
        case auth(String)
        case network(String)
        case decode

        var errorDescription: String? {
            switch self {
            case .auth(let message): message
            case .network(let message): message
            case .decode: "La IA no devolvió un consejo de EQ usable."
            }
        }
    }

    private let reader = AICredentialReader()
    /// Per track+output (exact repeats).
    private var cache: [String: Advice] = [:]
    /// Per Music/Claude genre+output — skips API when the next track shares the genre.
    private var genreCache: [String: Advice] = [:]
    private let claudeModel = "claude-haiku-4-5-20251001"
    private let openAIModel = "gpt-4o-mini"

    /// Normalize library / model genre labels for cheap equality checks.
    static func normalizeGenre(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    func hasClaudeAPIKey() async -> Bool { await reader.hasStoredAnthropicAPIKey() }
    func hasOpenAIAPIKey() async -> Bool { await reader.hasStoredOpenAIAPIKey() }
    func saveClaudeAPIKey(_ key: String) async throws { try await reader.saveAnthropicAPIKey(key) }
    func saveOpenAIAPIKey(_ key: String) async throws { try await reader.saveOpenAIAPIKey(key) }
    func clearClaudeAPIKey() async { await reader.clearAnthropicAPIKey() }
    func clearOpenAIAPIKey() async { await reader.clearOpenAIAPIKey() }

    /// Backward-compatible aliases used by older call sites.
    func hasAPIKey() async -> Bool { await hasClaudeAPIKey() }
    func saveAPIKey(_ key: String) async throws { try await saveClaudeAPIKey(key) }
    func clearAPIKey() async { await clearClaudeAPIKey() }

    /// Reuse a prior EQ decision when Music (or Claude) already labeled this genre for this output.
    func cachedAdvice(genre: String, output: MusicAudioOutput) -> Advice? {
        let key = Self.normalizeGenre(genre)
        guard !key.isEmpty else { return nil }
        return genreCache[genreOutputKey(key, output: output)]
    }

    func advise(
        title: String,
        artist: String,
        presets: [String],
        output: MusicAudioOutput,
        musicGenre: String = "",
        interactiveAuth: Bool = false
    ) async throws -> Advice {
        let key = cacheKey(title: title, artist: artist, output: output)
        if let cached = cache[key] {
            rememberGenre(cached, musicGenre: musicGenre, output: output)
            return cached
        }
        if let byGenre = cachedAdvice(genre: musicGenre, output: output) {
            cache[key] = byGenre
            return byGenre
        }

        let prompt = advicePrompt(title: title, artist: artist, presets: presets, output: output, musicGenre: musicGenre)
        var lastAuth: String?
        var lastNetwork: String?

        // 1) Claude — OAuth or Anthropic API key.
        do {
            let auth = try await reader.claudeAPIAuth(interactive: interactiveAuth)
            var advice = try await askClaude(auth: auth, system: prompt.system, user: prompt.user, presets: presets)
            advice.provider = "Claude"
            advice = output.adapted(advice)
            remember(advice, key: key, musicGenre: musicGenre, output: output)
            return advice
        } catch let failure as Failure {
            switch failure {
            case .auth(let message): lastAuth = message
            case .network(let message): lastNetwork = message
            case .decode: lastNetwork = failure.localizedDescription
            }
        } catch {
            lastAuth = error.localizedDescription
        }

        // 2) ChatGPT — OpenAI API key from keychain / env.
        do {
            let openAIKey = try await reader.openAIAPIKey()
            var advice = try await askOpenAI(apiKey: openAIKey, system: prompt.system, user: prompt.user, presets: presets)
            advice.provider = "ChatGPT"
            advice = output.adapted(advice)
            remember(advice, key: key, musicGenre: musicGenre, output: output)
            return advice
        } catch let failure as Failure {
            throw failure
        } catch {
            if let lastNetwork {
                throw Failure.network(lastNetwork)
            }
            throw Failure.auth(lastAuth ?? error.localizedDescription)
        }
    }

    private func advicePrompt(
        title: String,
        artist: String,
        presets: [String],
        output: MusicAudioOutput,
        musicGenre: String
    ) -> (system: String, user: String) {
        let presetList = presets.filter { !$0.isEmpty && $0.caseInsensitiveCompare("Manual") != .orderedSame }
            .prefix(40)
            .joined(separator: ", ")
        let system = """
        You pick Apple Music equalizer settings for better listening on the current output device.
        Reply with ONLY compact JSON (no markdown):
        {"genre":"short genre","preset":"Exact Factory Name or null","bass":-12..12,"mid":-12..12,"treble":-12..12,"note":"optional short reason"}
        Prefer a factory preset from this list when it fits: [\(presetList)].
        If none fits, set preset to null and use bass/mid/treble in dB (integers).
        Keep gains subtle (−6…+6) unless the genre clearly needs more.
        Adapt the curve to this output: \(output.promptHint)
        """
        let genreHint = musicGenre.trimmingCharacters(in: .whitespacesAndNewlines)
        let user: String
        if genreHint.isEmpty {
            user = "Track: \"\(title)\" by \"\(artist.isEmpty ? "unknown" : artist)\". Output: \(output.shortLabel)."
        } else {
            user = "Track: \"\(title)\" by \"\(artist.isEmpty ? "unknown" : artist)\". Library genre: \"\(genreHint)\". Output: \(output.shortLabel)."
        }
        return (system, user)
    }

    private func askClaude(auth: ClaudeAPIAuth, system: String, user: String, presets: [String]) async throws -> Advice {
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
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": claudeModel,
            "max_tokens": 200,
            "temperature": 0,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ] as [String: Any])

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(180) ?? ""
            if [401, 403].contains(code) {
                throw Failure.auth("Claude rechazó la autenticación (\(code)). Revisa la key o «claude auth login».")
            }
            throw Failure.network("Claude API \(code): \(snippet)")
        }
        guard let advice = parseAdvice(text: claudeText(from: data), presets: presets) else { throw Failure.decode }
        return advice
    }

    private func askOpenAI(apiKey: String, system: String, user: String, presets: [String]) async throws -> Advice {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": openAIModel,
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ] as [String: Any])

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(180) ?? ""
            if [401, 403].contains(code) {
                throw Failure.auth("ChatGPT rechazó la API key (\(code)). Revisa Ajustes → Música.")
            }
            throw Failure.network("OpenAI API \(code): \(snippet)")
        }
        guard let advice = parseAdvice(text: openAIText(from: data), presets: presets) else { throw Failure.decode }
        return advice
    }

    private func remember(_ advice: Advice, key: String, musicGenre: String, output: MusicAudioOutput) {
        cache[key] = advice
        if cache.count > 80 {
            cache.removeValue(forKey: cache.keys.first ?? key)
        }
        rememberGenre(advice, musicGenre: musicGenre, output: output)
    }

    private func rememberGenre(_ advice: Advice, musicGenre: String, output: MusicAudioOutput) {
        let fromLibrary = Self.normalizeGenre(musicGenre)
        let fromModel = Self.normalizeGenre(advice.genre)
        for label in [fromLibrary, fromModel] where !label.isEmpty {
            let key = genreOutputKey(label, output: output)
            genreCache[key] = advice
        }
        if genreCache.count > 60 {
            genreCache.removeValue(forKey: genreCache.keys.first ?? "")
        }
    }

    private func cacheKey(title: String, artist: String, output: MusicAudioOutput) -> String {
        "\(title.lowercased())|\(artist.lowercased())|\(output.kind.rawValue)|\(output.uid.lowercased())"
    }

    private func genreOutputKey(_ normalizedGenre: String, output: MusicAudioOutput) -> String {
        "\(normalizedGenre)|\(output.kind.rawValue)|\(output.uid.lowercased())"
    }

    private func claudeText(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]] else { return nil }
        return content.compactMap { $0["text"] as? String }.joined()
    }

    private func openAIText(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content
    }

    private func parseAdvice(text: String?, presets: [String]) -> Advice? {
        guard let text, !text.isEmpty else { return nil }
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
