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
ensure(WatchMusicSequencePolicy.shouldCoalesce(
    requestedContent: "Tema A|PLAY", latestContent: "Tema A|PLAY",
    inFlightStage: "ANUNCIO", pendingStages: ["ESTADO"]),
    "Auto y manual no deben crear varias parejas de la misma canción")
ensure(WatchMusicSequencePolicy.shouldCoalesce(
    requestedContent: "Tema A|PLAY", latestContent: "Tema A|PLAY",
    inFlightStage: nil, pendingStages: ["ANUNCIO", "ESTADO"]),
    "Coalescer pareja musical esperando BLE")
ensure(!WatchMusicSequencePolicy.shouldCoalesce(
    requestedContent: "Tema B|PLAY", latestContent: "Tema A|PLAY",
    inFlightStage: "ANUNCIO", pendingStages: ["ESTADO"]),
    "Una canción distinta debe quedar encolada")
ensure(!WatchMusicSequencePolicy.shouldCoalesce(
    requestedContent: "Tema A|PLAY", latestContent: "Tema A|PLAY",
    inFlightStage: nil, pendingStages: []),
    "La resincronización manual después del ACK debe poder enviar")
ensure(!WatchMusicSequencePolicy.shouldCoalesce(
    requestedContent: "Tema A|PAUSA", latestContent: "Tema A|PLAY",
    inFlightStage: "ESTADO", pendingStages: []),
    "PLAY/PAUSA no debe perderse por coalescing")
print("Music sequence checks passed: 24/01 pair closure, BLE coalescing, manual resync, play/pause")
