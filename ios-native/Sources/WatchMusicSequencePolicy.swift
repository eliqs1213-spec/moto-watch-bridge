import Foundation

// Nunca eliminar el ESTADO final de una secuencia cuyo ANUNCIO ya salió,
// aunque Spotify publique otra pista antes de que termine el intervalo BLE.
// Una secuencia ANUNCIO+ESTADO todavía intacta en cola sí se reemplaza.
enum WatchMusicSequencePolicy {
    static func preserveClosingState(stages: [String]) -> Bool {
        stages.contains("ESTADO") && !stages.contains("ANUNCIO")
    }

    // Los informes reales mostraron 3 paquetes reemplazados en menos de
    // un segundo por varias fuentes que enviaban la MISMA canción.
    // No abrir otra transacción mientras su par ANUNCIO/ESTADO sigue activo.
    static func shouldCoalesce(requestedContent: String, latestContent: String?,
                               inFlightStage: String?, pendingStages: [String]) -> Bool {
        requestedContent == latestContent &&
            (inFlightStage != nil || !pendingStages.isEmpty)
    }
}
