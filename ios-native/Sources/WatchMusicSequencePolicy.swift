import Foundation

// Nunca eliminar el ESTADO final de una secuencia cuyo ANUNCIO ya salió,
// aunque Spotify publique otra pista antes de que termine el intervalo BLE.
// Una secuencia ANUNCIO+ESTADO todavía intacta en cola sí se reemplaza.
enum WatchMusicSequencePolicy {
    static func preserveClosingState(stages: [String]) -> Bool {
        stages.contains("ESTADO") && !stages.contains("ANUNCIO")
    }
}
