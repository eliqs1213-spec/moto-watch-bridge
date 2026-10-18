import Foundation

// La Web API no envía eventos de cambio de pista como el SDK.
// En primer plano se comprueba Spotify periódicamente con un intervalo acotado;
// en segundo plano sólo cuando iOS permite una ventana de ejecución.
enum SpotifyMetadataRefreshPolicy {
    static let playingInterval: TimeInterval = 7
    static let pausedOrUnknownInterval: TimeInterval = 18

    // La Web API no emite callbacks. Usamos la posición/duración sólo para
    // una consulta cerca de una transición esperada, sin adivinar la pista.
    static func nearTrackEndProbeDelay(progressMs: Int?, durationMs: Int?,
                                       isPlaying: Bool) -> TimeInterval? {
        guard isPlaying, let progressMs, let durationMs,
              durationMs > 0, progressMs >= 0, progressMs <= durationMs else { return nil }
        let remainingMs = durationMs - progressMs
        guard remainingMs <= 30_000 else { return nil }
        return max(1, Double(remainingMs) / 1000 + 1)
    }

    // Un GET de lectura puede repetirse tras renovar el token. Las operaciones
    // que cambian reproducción no deben reintentarse automáticamente.
    static func shouldRefreshUnauthorizedGET(method: String, statusCode: Int) -> Bool {
        method.uppercased() == "GET" && statusCode == 401
    }

    static func shouldStart(inFlight: Bool, forced: Bool,
                            lastAutomaticAt: Date, now: Date,
                            isPlaying: Bool, retryAfterUntil: Date?) -> Bool {
        guard !inFlight else { return false }
        // El Retry-After protege tanto consultas manuales como automáticas.
        if let retryAfterUntil, now < retryAfterUntil { return false }
        if forced { return true }
        let interval = isPlaying ? playingInterval : pausedOrUnknownInterval
        return now.timeIntervalSince(lastAutomaticAt) >= interval
    }
}
