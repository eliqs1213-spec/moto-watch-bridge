import Foundation

// Una suscripción activa no demuestra que el SDK siga entregando estados.
// Si pasaron muchos segundos sin eventos válidos, consultar Web API como
// respaldo en primer plano, sin reemplazar una respuesta nativa más reciente.
enum SpotifyNativeFreshnessPolicy {
    static let maxAge: TimeInterval = 20

    static func isFresh(connected: Bool, hasMetadata: Bool,
                        lastReceivedAt: Date?, now: Date) -> Bool {
        guard connected, hasMetadata, let lastReceivedAt else { return false }
        let age = now.timeIntervalSince(lastReceivedAt)
        return age >= 0 && age <= maxAge
    }
}
