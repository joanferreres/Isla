import Foundation

/// Shared HTTPS client for Anthropic / OpenAI calls.
/// Avoids `URLSession.shared` connection reuse quirks (HTTP/3 / TLS flakiness →
/// “network connection was lost” / “TLS error caused the secure connection to fail”).
enum AIHTTPClient {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.httpShouldUsePipelining = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        // Prefer classic TLS 1.2+ over flaky QUIC/HTTP3 negotiation on some networks.
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: configuration)
    }()

    /// Transient URL errors worth retrying (TLS / dropped connection / timeout).
    private static let retryableCodes: Set<Int> = [
        NSURLErrorTimedOut,                 // -1001
        NSURLErrorCannotFindHost,           // -1003
        NSURLErrorCannotConnectToHost,      // -1004
        NSURLErrorNetworkConnectionLost,    // -1005
        NSURLErrorDNSLookupFailed,          // -1006
        NSURLErrorHTTPTooManyRedirects,     // -1007
        NSURLErrorNotConnectedToInternet,   // -1009
        NSURLErrorSecureConnectionFailed,   // -1200
        NSURLErrorServerCertificateUntrusted, // -1202
        NSURLErrorCannotLoadFromNetwork,    // -2000
    ]

    static func data(for request: URLRequest, attempts: Int = 3) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 1...max(1, attempts) {
            var req = request
            if req.timeoutInterval <= 0 || req.timeoutInterval > 45 {
                req.timeoutInterval = 30
            }
            // Keep Anthropic/OpenAI on HTTP/1.1–2; HTTP/3 has caused intermittent TLS failures.
            req.assumesHTTP3Capable = false
            do {
                return try await session.data(for: req)
            } catch {
                lastError = error
                let ns = error as NSError
                let retryable = ns.domain == NSURLErrorDomain && retryableCodes.contains(ns.code)
                guard retryable, attempt < attempts else { throw mapped(error) }
                // New ephemeral task each try; brief backoff clears half-open TLS sockets.
                try await Task.sleep(for: .milliseconds(250 * attempt * attempt))
            }
        }
        throw mapped(lastError ?? URLError(.unknown))
    }

    static func mapped(_ error: Error) -> Error {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return error }
        switch ns.code {
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return URLError(.secureConnectionFailed, userInfo: [
                NSLocalizedDescriptionKey:
                    "Falló el TLS con la API (Anthropic/OpenAI). Reintenta; si persiste, revisa VPN/proxy o el cortafuegos.",
            ])
        case NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut, NSURLErrorNotConnectedToInternet,
             NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return URLError(.networkConnectionLost, userInfo: [
                NSLocalizedDescriptionKey:
                    "Se perdió la conexión con la API. Isla reintenta sola; si sigue, comprueba la red y vuelve a pulsar Actualizar.",
            ])
        default:
            return error
        }
    }

    static func isTransient(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && retryableCodes.contains(ns.code)
    }
}
