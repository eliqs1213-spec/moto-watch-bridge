import Foundation

// Una respuesta 204 de /me/player (o un dispositivo momentáneamente ausente)
// no demuestra que el usuario haya detenido Spotify. El reloj solo debe
// quedarse sin información si NUNCA conocimos una pista y la ausencia persiste.
enum SpotifyPlaybackContinuityPolicy {
    enum Decision: Equatable {
        case waiting
        case preserveLastTrack
        case showIdle
    }

    static func decide(unavailableSeconds: TimeInterval,
                       hasLastTrack: Bool,
                       graceSeconds: TimeInterval = 30) -> Decision {
        if unavailableSeconds < graceSeconds { return .waiting }
        return hasLastTrack ? .preserveLastTrack : .showIdle
    }
}
