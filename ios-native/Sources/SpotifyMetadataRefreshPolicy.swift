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

    // Una lectura Web que confirma metadatos idénticos no debe aparentar
    // que reemplazó el origen SDK. Si cambia pista o reproducción sí.
    static func shouldLabelWebAsSource(previousTitle: String?,
                                       previousArtist: String?,
                                       previousAlbum: String?,
                                       previousPlaying: Bool?,
                                       newTitle: String?,
                                       newArtist: String?,
                                       newAlbum: String?,
                                       newPlaying: Bool?,
                                       previousSourceWasNative: Bool) -> Bool {
        guard previousSourceWasNative else { return true }
        return previousTitle != newTitle || previousArtist != newArtist
            || previousAlbum != newAlbum || previousPlaying != newPlaying
    }

    // Reintentos graduales sólo para lecturas fallidas; no repetir POST/PUT.
    static func transientRetryDelay(consecutiveFailures: Int) -> TimeInterval {
        let tier = min(max(consecutiveFailures - 1, 0), 4)
        return min(60, Double(5 * (1 << tier)))
    }

    // Un GET de lectura puede repetirse tras renovar el token. Las operaciones
    // que cambian reproducción no deben reintentarse automáticamente.
    static func shouldRefreshUnauthorizedGET(method: String, statusCode: Int) -> Bool {
        method.uppercased() == "GET" && statusCode == 401
    }

    static func shouldStart(inFlight: Bool, forced: Bool,
                            lastAutomaticAt: Date, now: Date,
                            isPlaying: Bool, retryAfterUntil: Date?,
                            transientRetryUntil: Date? = nil) -> Bool {
        guard !inFlight else { return false }
        // El Retry-After y los fallos temporales limitan también GET forzados.
        if let retryAfterUntil, now < retryAfterUntil { return false }
        if let transientRetryUntil, now < transientRetryUntil { return false }
        if forced { return true }
        let interval = isPlaying ? playingInterval : pausedOrUnknownInterval
        return now.timeIntervalSince(lastAutomaticAt) >= interval
    }
}
