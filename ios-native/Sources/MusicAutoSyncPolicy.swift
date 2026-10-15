import Foundation

enum MusicAutoSyncDecision: Equatable {
    case none
    case changed
    case manual
    case recovery
    case heartbeat
}

enum MusicAutoSyncPolicy {
    // Una reproducción confirmada y sin cambios solo requiere un nuevo
    // anuncio de vez en cuando; no cada consulta de Spotify (cada ~6 s).
    static let heartbeatSeconds: TimeInterval = 180
    // Abrir iWatch sí recupera la pantalla: reproducir ese disparador
    // sin reanunciar cada 6 segundos de polling ni cada cambio de vista.
    static let foregroundRecoveryCooldown: TimeInterval = 15
    static let recoveryRequestLifetime: TimeInterval = 30
    // La primera secuencia puede quedar sin efecto visual aun con ACK GATT.
    // Verificar una vez contra Spotify y reanunciar solo la misma canción.
    static let transitionVerificationDelay: TimeInterval = 5
    static let transitionVerificationLifetime: TimeInterval = 12

    static func shouldVerifyTransition(isPlaying: Bool, inForeground: Bool,
                                       watchConnected: Bool) -> Bool {
        isPlaying && inForeground && watchConnected
    }

    static func confirmsFreshTransition(expected: String?, actual: String,
                                        isPlaying: Bool, inForeground: Bool,
                                        receivedAt: Date, expiresAt: Date) -> Bool {
        expected == actual && isPlaying && inForeground && receivedAt <= expiresAt
    }

    static func decide(changed: Bool,
                       manual: Bool,
                       recoveredFromIdle: Bool,
                       recoveryRequested: Bool,
                       recoveryIsReconnect: Bool,
                       elapsedSinceAnnouncement: TimeInterval,
                       isPlaying: Bool,
                       foreground: Bool) -> MusicAutoSyncDecision {
        if manual || recoveredFromIdle { return .manual }
        if changed { return .changed }
        if recoveryRequested {
            if recoveryIsReconnect || elapsedSinceAnnouncement >= foregroundRecoveryCooldown {
                return .recovery
            }
        }
        if isPlaying && foreground && elapsedSinceAnnouncement >= heartbeatSeconds {
            return .heartbeat
        }
        return .none
    }
}
