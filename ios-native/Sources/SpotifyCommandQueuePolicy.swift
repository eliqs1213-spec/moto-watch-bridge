import Foundation

// "Siguiente", "Anterior" y "Play/Pausa" no son operaciones idempotentes.
// Una orden pendiente solo se ejecuta si el usuario la solicitó de verdad,
// dentro de una ventana breve. Nunca se crea un reintento automático ante 5xx.
enum SpotifyCommandQueuePolicy {
    static let maxPending = 2
    static let expirationSeconds: TimeInterval = 6

    static func isFresh(receivedAt: Date, now: Date) -> Bool {
        let seconds = now.timeIntervalSince(receivedAt)
        return seconds >= 0 && seconds <= expirationSeconds
    }

    static func isTransientHTTP(_ status: Int) -> Bool {
        return status == 429 || (500...599).contains(status)
    }
}
