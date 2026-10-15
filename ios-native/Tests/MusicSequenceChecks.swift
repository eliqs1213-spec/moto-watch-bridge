import Foundation

func ensure(_ ok: @autoclosure () -> Bool, _ name: String) {
    if !ok() { fatalError(name) }
}
ensure(!WatchMusicSequencePolicy.preserveClosingState(stages: []), "Cola vacía")
ensure(!WatchMusicSequencePolicy.preserveClosingState(stages: ["ANUNCIO", "ESTADO"]),
       "Reemplazar pareja musical que todavía no comenzó")
ensure(WatchMusicSequencePolicy.preserveClosingState(stages: ["ESTADO"]),
       "No perder ESTADO después del ANUNCIO BLE")
ensure(!WatchMusicSequencePolicy.preserveClosingState(stages: ["ANUNCIO", "ESTADO", "ESTADO"]),
       "Descartar secuencias obsoletas todavía no iniciadas")
print("Music sequence checks passed: pair replacement, in-flight stage protection")
