import Foundation

// Un HTTP iniciado antes de un estado ya aceptado NO puede reemplazarlo.
// La protección es simétrica: sirve para observaciones SDK o Web posteriores.
// ActivityKit y Bluetooth no conceden ejecución HTTP garantizada.
enum SpotifyBackgroundProbePolicy {
    static func shouldApplyHTTPResult(inBackground: Bool,
                                      enabled: Bool,
                                      cancelled: Bool,
                                      startedEpoch: UInt64,
                                      currentEpoch: UInt64,
                                      startedAt: Date,
                                      latestAcceptedAt: Date?) -> Bool {
        guard inBackground && enabled && !cancelled,
              startedEpoch == currentEpoch else { return false }
        guard let latestAcceptedAt else { return true }
        return latestAcceptedAt <= startedAt
    }
}
