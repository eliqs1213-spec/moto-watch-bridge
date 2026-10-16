import Foundation

// Decidir si una respuesta Web de una comprobación limitada por iOS
// todavía es válida. Un GET lento nunca debe reemplazar un evento SDK
// más reciente ni escribir en el reloj después de salir de background.
enum SpotifyBackgroundProbePolicy {
    static func shouldApplyHTTPResult(inBackground: Bool,
                                      enabled: Bool,
                                      cancelled: Bool,
                                      startedEpoch: UInt64,
                                      currentEpoch: UInt64,
                                      startedNativeRevision: UInt64,
                                      currentNativeRevision: UInt64) -> Bool {
        inBackground && enabled && !cancelled &&
            startedEpoch == currentEpoch &&
            startedNativeRevision == currentNativeRevision
    }
}
