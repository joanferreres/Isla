import AppKit
import CryptoKit
import Foundation
import Network
import OSLog
import Security
import SwiftUI
import IslandCore

/// Which music app the playlist features should talk to right now (set from the player state).
enum PlaylistRoute {
    private static let flag = OSAllocatedUnfairLock(initialState: false)
    static var isSpotify: Bool {
        get { flag.withLock { $0 } }
        set { flag.withLock { $0 = newValue } }
    }
}

/// Spotify Web API access with the Authorization Code + PKCE flow (no client secret).
/// Every person registers their own free app at developer.spotify.com and pastes its Client ID:
/// Spotify's development mode only admits a handful of users per Client ID.
actor SpotifyWebAPI {
    static let shared = SpotifyWebAPI()
    static let redirectPort: UInt16 = 43821
    static let redirectURI = "http://127.0.0.1:43821/callback"
    static let clientIDKey = "spotifyClientID"
    private static let scopes = [
        "playlist-read-private", "playlist-read-collaborative", "playlist-modify-private",
        "playlist-modify-public", "user-read-playback-state", "user-modify-playback-state",
        "user-read-currently-playing",
    ].joined(separator: " ")

    struct Tokens: Codable, Sendable { var access: String; var refresh: String; var expires: Date }

    private let keychainService = "local.personal.isla.spotify-tokens"
    private var tokens: Tokens?
    private var loaded = false
    private var userID: String?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    // MARK: Client ID

    /// Client ID typed in Settings, or one bundled by the app owner (`IslaSpotifyClientID` in Info.plist).
    nonisolated static var clientID: String? {
        let typed = UserDefaults.standard.string(forKey: clientIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let typed, !typed.isEmpty { return typed }
        let bundled = (Bundle.main.object(forInfoDictionaryKey: "IslaSpotifyClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return bundled?.isEmpty == false ? bundled : nil
    }

    var isConnected: Bool {
        loadIfNeeded()
        return tokens != nil
    }

    // MARK: Sign in

    func connect() async throws {
        guard let clientID = Self.clientID else {
            throw MusicFailure(message: "Pega primero el Client ID de tu app de Spotify.")
        }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomString(16)
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: state),
        ]
        let receiver = try LoopbackReceiver(port: Self.redirectPort)
        let url = components.url!
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
        let query = try await receiver.waitForCallback(timeout: 180)
        guard query["state"] == state else { throw MusicFailure(message: "Spotify devolvió una respuesta no esperada. Vuelve a intentarlo.") }
        if let denied = query["error"] {
            throw MusicFailure(message: denied == "access_denied" ? "Cancelaste el acceso a Spotify." : "Spotify rechazó el acceso (\(denied)).")
        }
        guard let code = query["code"] else { throw MusicFailure(message: "Spotify no devolvió ningún código.") }
        try await tokenRequest([
            "client_id": clientID, "grant_type": "authorization_code", "code": code,
            "redirect_uri": Self.redirectURI, "code_verifier": verifier,
        ])
        userID = nil
    }

    func disconnect() {
        tokens = nil
        userID = nil
        loaded = true
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: "tokens"] as CFDictionary)
    }

    // MARK: Requests

    /// Raw response bytes (Sendable); callers parse them on their own side.
    func data(_ method: String = "GET", _ path: String, query: [String: String] = [:], body: Data? = nil) async throws -> Data {
        try await send(method, path, query: query, body: body)
    }

    func currentUserID() async throws -> String {
        if let userID { return userID }
        let me = try? JSONSerialization.jsonObject(with: try await send("GET", "/me", query: [:], body: nil)) as? [String: Any]
        guard let id = me?["id"] as? String else { throw MusicFailure(message: "Spotify no devolvió tu usuario.") }
        userID = id
        return id
    }

    private func send(_ method: String, _ path: String, query: [String: String], body: Data?, retried: Bool = false) async throws -> Data {
        let token = try await validAccessToken()
        var components = URLComponents(string: "https://api.spotify.com/v1" + path)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200...299: return data
        case 401 where !retried:
            tokens?.expires = .distantPast
            return try await send(method, path, query: query, body: body, retried: true)
        case 401:
            throw MusicFailure(message: "La sesión de Spotify caducó. Vuelve a conectar en Ajustes → Música.")
        case 403:
            throw MusicFailure(message: "Spotify no te deja usar esto: tu cuenta debe ser Premium y tu app de Spotify debe tenerte como usuario.")
        case 429:
            throw MusicFailure(message: "Spotify limita las consultas. Espera un momento.")
        case 404 where path.hasPrefix("/me/player"):
            throw MusicFailure(message: "Abre Spotify y ponlo a sonar en este Mac.")
        default:
            throw MusicFailure(message: "Spotify respondió con un error (\(code)).")
        }
    }

    // MARK: Tokens

    private func validAccessToken() async throws -> String {
        loadIfNeeded()
        guard var current = tokens else {
            throw MusicFailure(message: "Conecta Spotify en Ajustes → Música para usar las playlists.")
        }
        if current.expires > Date().addingTimeInterval(60) { return current.access }
        guard let clientID = Self.clientID else { throw MusicFailure(message: "Falta el Client ID de Spotify.") }
        do {
            try await tokenRequest(["client_id": clientID, "grant_type": "refresh_token", "refresh_token": current.refresh])
        } catch {
            // A revoked refresh token cannot recover: ask for a fresh sign-in instead of failing forever.
            if (error as? MusicFailure)?.code == 400 { disconnect() }
            throw error
        }
        current = tokens ?? current
        return current.access
    }

    private func tokenRequest(_ fields: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200,
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = row["access_token"] as? String else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error_description"] as? String
            throw MusicFailure(message: detail.map { "Spotify: \($0)" } ?? "Spotify no aceptó el inicio de sesión (\(code)).", code: code)
        }
        let refresh = (row["refresh_token"] as? String) ?? tokens?.refresh ?? ""
        let lifetime = (row["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        let value = Tokens(access: access, refresh: refresh, expires: Date().addingTimeInterval(lifetime))
        tokens = value
        loaded = true
        store(value)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: "tokens",
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let value = try? JSONDecoder().decode(Tokens.self, from: data) {
            tokens = value
        }
    }

    private func store(_ value: Tokens) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: "tokens"]
        if SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func randomString(_ length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// One-shot HTTP server on 127.0.0.1 that receives Spotify's redirect and shows a "done" page.
private final class LoopbackReceiver: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "isla.spotify.loopback")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var finished = false

    init(port: UInt16) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        do { listener = try NWListener(using: parameters) } catch {
            throw MusicFailure(message: "No se pudo abrir el puerto \(port) para el inicio de sesión. Cierra la app que lo use y reintenta.")
        }
    }

    func waitForCallback(timeout: TimeInterval) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: String], Error>) in
            lock.lock(); self.continuation = continuation; lock.unlock()
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    self?.finish(.failure(MusicFailure(message: "No se pudo abrir el puerto de inicio de sesión. Reintenta.")))
                }
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.failure(MusicFailure(message: "Se agotó el tiempo esperando a Spotify. Vuelve a pulsar Conectar.")))
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8),
                  let line = text.components(separatedBy: "\r\n").first else { connection.cancel(); return }
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let url = URL(string: "http://127.0.0.1" + parts[1]), url.path == "/callback" else {
                let notFound = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(notFound.utf8), completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            var query: [String: String] = [:]
            for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { query[item.name] = item.value ?? "" }
            let body = "<html><head><meta charset=\"utf-8\"><title>Isla</title></head><body style=\"font-family:-apple-system;text-align:center;padding-top:20vh\"><h2>Spotify conectado</h2><p>Ya puedes volver a Isla y cerrar esta pestaña.</p></body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            self.finish(.success(query))
        }
    }

    private func finish(_ result: Result<[String: String], Error>) {
        lock.lock()
        guard !finished, let continuation else { lock.unlock(); return }
        finished = true
        self.continuation = nil
        lock.unlock()
        listener.cancel()
        continuation.resume(with: result)
    }
}

/// Settings model for the Spotify connection.
@MainActor final class SpotifyConnection: ObservableObject {
    static let shared = SpotifyConnection()
    @Published var clientID = UserDefaults.standard.string(forKey: SpotifyWebAPI.clientIDKey) ?? ""
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published var message: String?

    func refresh() { Task { connected = await SpotifyWebAPI.shared.isConnected } }

    func connect() {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: SpotifyWebAPI.clientIDKey)
        guard !trimmed.isEmpty else { message = "Pega primero el Client ID."; return }
        busy = true
        message = "Se abrió tu navegador: acepta el acceso en Spotify…"
        Task {
            defer { busy = false }
            do {
                try await SpotifyWebAPI.shared.connect()
                connected = true
                message = nil
            } catch {
                connected = await SpotifyWebAPI.shared.isConnected
                message = error.localizedDescription
            }
        }
    }

    func disconnect() {
        Task {
            await SpotifyWebAPI.shared.disconnect()
            connected = false
            message = nil
        }
    }
}

/// Settings block: guided setup + connect button.
struct SpotifySetupView: View {
    @ObservedObject private var connection = SpotifyConnection.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spotify: playlists, cola y selector de discos").font(.headline)
            if connection.connected {
                Label("Spotify conectado", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Desconectar Spotify") { connection.disconnect() }
            } else {
                Text("Spotify solo deja usar sus playlists con una app propia, gratis y de 2 minutos (necesitas Spotify Premium):")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Abre el panel de Spotify, inicia sesión y pulsa «Create app».").font(.caption)
                    Button("Abrir developer.spotify.com/dashboard") {
                        NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!)
                    }.font(.caption)
                    Text("2. En «Redirect URI» pega este texto, marca «Web API» y guarda:").font(.caption)
                    HStack {
                        Text(SpotifyWebAPI.redirectURI).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Button("Copiar") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(SpotifyWebAPI.redirectURI, forType: .string)
                        }.font(.caption)
                    }
                    Text("3. Copia el «Client ID» de tu app y pégalo aquí:").font(.caption)
                }
                HStack {
                    TextField("Client ID", text: $connection.clientID).textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                    Button("Conectar") { connection.connect() }.disabled(connection.busy || connection.clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                    if connection.busy { ProgressView().controlSize(.small) }
                }
            }
            if let message = connection.message { Text(message).font(.caption).foregroundStyle(.orange) }
            Text("Solo se pueden usar playlists tuyas o colaborativas (límite de Spotify). Isla guarda el acceso en tu llavero.").font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { connection.refresh() }
    }
}

// MARK: - Playlists on Spotify

actor SpotifyPlaylistService {
    static let shared = SpotifyPlaylistService()
    private var artworkURLs: [String: URL] = [:]
    private var artworkData: [String: Data] = [:]
    private var contextURI: String?
    private let api = SpotifyWebAPI.shared

    private func json(_ method: String = "GET", _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> [String: Any] {
        let payload = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let data = try await api.data(method, path, query: query, body: payload)
        guard !data.isEmpty else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func playlists() async throws -> [MusicPlaylist] {
        let me = try await api.currentUserID()
        var result: [MusicPlaylist] = []
        var offset = 0
        while offset < 300 {
            let page = try await json("GET", "/me/playlists", query: ["limit": "50", "offset": "\(offset)"])
            let items = page["items"] as? [[String: Any]] ?? []
            for row in items {
                guard let id = row["id"] as? String, let name = row["name"] as? String else { continue }
                let owner = (row["owner"] as? [String: Any])?["id"] as? String
                // Spotify only lets third-party apps edit/read playlists the user owns or shares.
                if owner == me || row["collaborative"] as? Bool == true { result.append(MusicPlaylist(id: id, name: name)) }
            }
            if items.count < 50 { break }
            offset += 50
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func playPlaylist(_ playlist: MusicPlaylist) async throws {
        let uri = "spotify:playlist:" + playlist.id
        contextURI = uri
        try await MainActor.run { try Self.runSpotify("play track \"\(uri)\"") }
    }

    func play(trackID: String) async throws {
        let track = Self.escape(trackID)
        if let contextURI {
            try await MainActor.run { try Self.runSpotify("play track \"\(track)\" in context \"\(Self.escape(contextURI))\"") }
        } else {
            try await MainActor.run { try Self.runSpotify("play track \"\(track)\"") }
        }
    }

    func changerCatalog() async throws -> MusicPlaylistCatalog {
        let state = try await json("GET", "/me/player")
        if let context = state["context"] as? [String: Any], context["type"] as? String == "playlist",
           let uri = context["uri"] as? String, let id = uri.split(separator: ":").last.map(String.init) {
            contextURI = uri
            if let rows = try? await json("GET", "/playlists/\(id)/items", query: ["limit": "100"])["items"] as? [[String: Any]] {
                let tracks = rows.compactMap { Self.track(from: $0["item"] ?? $0["track"]) }
                if !tracks.isEmpty {
                    remember(tracks)
                    let name = (try? await json("GET", "/playlists/\(id)", query: ["fields": "name"])["name"] as? String) ?? "Playlist"
                    return MusicPlaylistCatalog(name: name, tracks: tracks.map(\.0))
                }
            }
        }
        // Not a readable playlist: fall back to what is playing and coming next.
        let queue = try await json("GET", "/me/player/queue")
        var rows: [Any?] = [queue["currently_playing"]]
        rows.append(contentsOf: (queue["queue"] as? [Any]) ?? [])
        let tracks = rows.compactMap { Self.track(from: $0) }
        guard !tracks.isEmpty else {
            throw MusicFailure(message: "Spotify no tiene canciones en la playlist ni en la cola ahora mismo.")
        }
        contextURI = nil
        remember(tracks)
        return MusicPlaylistCatalog(name: "Cola de Spotify", tracks: tracks.map(\.0))
    }

    func currentCatalog() async throws -> MusicPlaylistCatalog { try await changerCatalog() }

    func add(_ track: MediaSnapshot, to playlist: MusicPlaylist) async throws -> Bool {
        guard track.trackID.hasPrefix("spotify:track:") else {
            throw MusicFailure(message: "Spotify no permite añadir esta canción (no es del catálogo).")
        }
        _ = try await json("POST", "/playlists/\(playlist.id)/items", body: ["uris": [track.trackID]])
        return true
    }

    func artwork(trackID: String) async throws -> Data? {
        if let cached = artworkData[trackID] { return cached }
        guard let url = artworkURLs[trackID] else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 5_000_000, NSImage(data: data) != nil else { return nil }
        artworkData[trackID] = data
        return data
    }

    // MARK: helpers

    private func remember(_ tracks: [(MusicCassetteTrack, URL?)]) {
        for (track, url) in tracks { if let url { artworkURLs[track.id] = url } }
    }

    private static func track(from value: Any?) -> (MusicCassetteTrack, URL?)? {
        guard let row = value as? [String: Any], row["type"] as? String != "episode",
              let uri = row["uri"] as? String, uri.hasPrefix("spotify:track:"),
              let title = row["name"] as? String else { return nil }
        let artist = ((row["artists"] as? [[String: Any]])?.first?["name"] as? String) ?? ""
        let images = (row["album"] as? [String: Any])?["images"] as? [[String: Any]] ?? []
        // Prefer a mid-size cover: sharp enough for the vinyl, small to download.
        let raw = (images.first(where: { ($0["width"] as? Int ?? 0) <= 340 })?["url"] ?? images.first?["url"]) as? String
        return (MusicCassetteTrack(id: uri, title: title, artist: artist), raw.flatMap(URL.init(string:)))
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    @MainActor private static func runSpotify(_ command: String) throws {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else {
            throw MusicFailure(message: "Abre Spotify para reproducir.")
        }
        var details: NSDictionary?
        NSAppleScript(source: "tell application \"Spotify\" to \(command)")?.executeAndReturnError(&details)
        if let details {
            let code = details[NSAppleScript.errorNumber] as? Int
            throw MusicFailure(message: code == -1743
                ? "Permite a Isla controlar Spotify en Privacidad y seguridad → Automatización."
                : "Spotify no pudo reproducir eso.", code: code)
        }
    }
}
