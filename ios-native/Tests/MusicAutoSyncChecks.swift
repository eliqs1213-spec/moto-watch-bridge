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
check(MusicAutoSyncPolicy.foregroundRecoveryCooldown == 15, "Reapertura debe reanunciar luego de 15 s")
check(MusicAutoSyncPolicy.transitionVerificationDelay == 5, "Demora única de verificación")
check(MusicAutoSyncPolicy.transitionVerificationLifetime == 12, "Caducidad de comprobación")
check(MusicAutoSyncPolicy.shouldVerifyTransition(isPlaying: true, inForeground: true, watchConnected: true),
      "Se verifica cambio natural visible")
check(!MusicAutoSyncPolicy.shouldVerifyTransition(isPlaying: true, inForeground: false, watchConnected: true),
      "No se programan verificaciones en segundo plano")
check(!MusicAutoSyncPolicy.shouldVerifyTransition(isPlaying: false, inForeground: true, watchConnected: true),
      "No se fuerza música pausada")
let now = Date(timeIntervalSince1970: 1000)
check(MusicAutoSyncPolicy.confirmsFreshTransition(expected: "tema A", actual: "tema A",
      isPlaying: true, inForeground: true, receivedAt: now, expiresAt: now.addingTimeInterval(12)),
      "Reanunciar únicamente pista confirmada")
check(!MusicAutoSyncPolicy.confirmsFreshTransition(expected: "tema A", actual: "tema B",
      isPlaying: true, inForeground: true, receivedAt: now, expiresAt: now.addingTimeInterval(12)),
      "Una canción nueva cancela comprobación vieja")
check(!MusicAutoSyncPolicy.confirmsFreshTransition(expected: "tema A", actual: "tema A",
      isPlaying: true, inForeground: true, receivedAt: now.addingTimeInterval(13),
      expiresAt: now.addingTimeInterval(12)), "No reanunciar pistas obsoletas")
check(!MusicAutoSyncPolicy.confirmsFreshTransition(expected: nil, actual: "tema A",
      isPlaying: true, inForeground: true, receivedAt: now, expiresAt: now.addingTimeInterval(12)),
      "No aceptar reanuncio no solicitado")
print("Music Auto Sync checks passed: new song, manual, BLE reconnect, cooldown, foreground, background")
