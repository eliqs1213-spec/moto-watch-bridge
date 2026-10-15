import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

func choose(changed: Bool = false, manual: Bool = false, idle: Bool = false,
            recovery: Bool = false, reconnect: Bool = false,
            elapsed: TimeInterval = 0, playing: Bool = true,
            foreground: Bool = true) -> MusicAutoSyncDecision {
    MusicAutoSyncPolicy.decide(changed: changed, manual: manual,
                               recoveredFromIdle: idle,
                               recoveryRequested: recovery,
                               recoveryIsReconnect: reconnect,
                               elapsedSinceAnnouncement: elapsed,
                               isPlaying: playing, foreground: foreground)
}

check(choose(changed: true) == .changed, "Se perdió un cambio de canción")
check(choose(manual: true) == .manual, "Se ignoró recuperación manual")
check(choose(idle: true) == .manual, "No se recupera estado sin música")
check(choose(recovery: true, reconnect: true) == .recovery, "Reconexión no reanuncia")
check(choose(recovery: true, elapsed: 90) == .recovery, "Regreso al primer plano sin recuperación")
check(choose(recovery: true, elapsed: 89) == .none, "Reanuncio prematuro en primer plano")
check(choose(elapsed: 179) == .none, "Reanuncio periódico demasiado frecuente")
check(choose(elapsed: 180) == .heartbeat, "No se activa protección preventiva")
check(choose(elapsed: 300, playing: false) == .none, "Heartbeat no debe despertar pista pausada")
check(choose(elapsed: 300, foreground: false) == .none, "No sondear en segundo plano")
check(choose(recovery: true, reconnect: true, elapsed: 3, foreground: false) == .recovery, "Recuperación por BLE debe aceptar evento de iOS")
check(choose(changed: true, manual: true) == .manual, "Manual debe forzar anuncio")
check(MusicAutoSyncPolicy.heartbeatSeconds == 180, "Intervalo de recuperación preventiva")
check(MusicAutoSyncPolicy.recoveryRequestLifetime == 30, "Vida útil de solicitud de recuperación")
print("Music Auto Sync checks passed: new song, manual, BLE reconnect, cooldown, foreground, background")
