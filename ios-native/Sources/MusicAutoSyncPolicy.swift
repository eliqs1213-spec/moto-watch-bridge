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
    static let foregroundRecoveryCooldown: TimeInterval = 90
    static let recoveryRequestLifetime: TimeInterval = 30

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
