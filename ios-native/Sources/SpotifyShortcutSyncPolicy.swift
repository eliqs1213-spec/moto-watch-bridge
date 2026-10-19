import Foundation

// El caché aceptado ANTES del Atajo nunca cuenta como éxito.
enum SpotifyShortcutSyncPolicy {
    static func hasNewObservation(startedAt: Date, acceptedAt: Date?) -> Bool {
        guard let acceptedAt else { return false }
        return acceptedAt >= startedAt
    }
}
