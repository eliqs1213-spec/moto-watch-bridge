import Foundation
import Combine
import UIKit

// Coordina únicamente cuándo reenviar metadatos musicales ya validados.
// No obtiene tokens, no controla Spotify ni escribe directamente en un GATT
// desconocido. WatchBLEManager conserva el control de la cola y los avisos.
final class MusicSyncEngine: ObservableObject {
    static let shared = MusicSyncEngine()

    @Published private(set) var status = "Auto Sync listo · esperando Spotify"
    private enum RecoveryReason: Equatable {
        case foreground, reconnect
    }
    private var pendingRecovery: RecoveryReason?
    private var pendingUntil = Date.distantPast
    private var lastSubmittedSignature: String?
    private var lastAnnouncedAt = Date.distantPast
    private var transitionVerification: DispatchWorkItem?
    private var pendingTransitionSignature: String?
    private var pendingTransitionUntil = Date.distantPast

    private init() {}

    func reset() {
        transitionVerification?.cancel()
        transitionVerification = nil
        pendingTransitionSignature = nil
        pendingTransitionUntil = .distantPast
        pendingRecovery = nil
        lastSubmittedSignature = nil
        lastAnnouncedAt = .distantPast
        status = "Auto Sync en espera"
    }

    // No se reenvía el caché a ciegas: esta petición solo se satisface
    // al recibir una pista nueva y verificada por SDK o Web API.
    func requestForegroundRecovery() {
        guard WatchBLEManager.shared.isConnected else { return }
        pendingRecovery = .foreground
        pendingUntil = Date().addingTimeInterval(MusicAutoSyncPolicy.recoveryRequestLifetime)
        status = "Auto Sync · verificando Spotify al volver a iWatch"
    }

    func requestReconnectRecovery() {
        pendingRecovery = .reconnect
        pendingUntil = Date().addingTimeInterval(MusicAutoSyncPolicy.recoveryRequestLifetime)
        status = "Auto Sync · esperando metadatos actuales tras reconexión"
    }

    func acceptFresh(_ snapshot: WatchMusicSnapshot,
                     manual: Bool = false, recoveredFromIdle: Bool = false) {
        let watch = WatchBLEManager.shared
        guard watch.isConnected else {
            status = "Auto Sync esperando Bluetooth"
            return
        }
        let now = Date()
        // Los ID del SDK (spotify:track:...) y Web API (...) pueden diferir
        // aunque representen la misma canción. Título, artista, álbum y
        // reproducción determinan si reanunciar; progreso no es nuevo tema.
        let signature = "\(snapshot.title)|\(snapshot.artist)|\(snapshot.album)|\(snapshot.isPlaying)"
        let recoveryIsCurrent = pendingRecovery != nil && now <= pendingUntil
        let isReconnect = recoveryIsCurrent && pendingRecovery == .reconnect
        let elapsed = now.timeIntervalSince(lastAnnouncedAt)
        // Releer Spotify después de un cambio real permite recuperar un
        // reproductor que aceptó la escritura BLE pero no refrescó su pantalla.
        // Solo actuar sobre la MISMA pista confirmada, una única vez.
        let recoveredTransition = MusicAutoSyncPolicy.confirmsFreshTransition(
            expected: pendingTransitionSignature, actual: signature,
            isPlaying: snapshot.isPlaying,
            inForeground: UIApplication.shared.applicationState == .active,
            receivedAt: now, expiresAt: pendingTransitionUntil)
        if pendingTransitionSignature != nil {
            pendingTransitionSignature = nil
        }
        let decision = recoveredTransition ? .recovery : MusicAutoSyncPolicy.decide(
            changed: signature != lastSubmittedSignature,
            manual: manual,
            recoveredFromIdle: recoveredFromIdle,
            recoveryRequested: recoveryIsCurrent,
            recoveryIsReconnect: isReconnect,
            elapsedSinceAnnouncement: elapsed,
            isPlaying: snapshot.isPlaying,
            foreground: UIApplication.shared.applicationState == .active
        )
        if recoveryIsCurrent { pendingRecovery = nil }
        switch decision {
        case .none:
            return
        case .changed:
            // Forzar envío completo incluso si la firma BLE basada en URI no
            // refleja un cambio de título/artista/álbum en menos de 25 s.
            watch.sendMusic(snapshot, force: true, reannounce: true)
            status = "Auto Sync · cambio de canción/estado enviado (pantalla no verificada)"
            if MusicAutoSyncPolicy.shouldVerifyTransition(
                isPlaying: snapshot.isPlaying,
                inForeground: UIApplication.shared.applicationState == .active,
                watchConnected: watch.isConnected
            ) {
                scheduleOneShotVerification(of: signature)
            }
        case .manual:
            watch.sendMusic(snapshot, force: true, reannounce: true)
            status = "Auto Sync · resincronización manual enviada (pantalla no verificada)"
        case .recovery:
            watch.sendMusic(snapshot, force: true, reannounce: true)
            status = recoveredTransition ? "Auto Sync · segunda verificación de cambio natural" :
                (isReconnect ? "Auto Sync · recuperando tras reconexión (pantalla no verificada)"
                             : "Auto Sync · recuperando al abrir iWatch (pantalla no verificada)")
            watch.record("MUSICA-AUTO", recoveredTransition
                ? "Reanuncio único tras cambio natural con canción nuevamente verificada"
                : isReconnect ? "Reanuncio controlado tras reconexión con pista validada"
                              : "Reanuncio controlado al volver a primer plano con pista validada")
        case .heartbeat:
            watch.sendMusic(snapshot, force: true, reannounce: true)
            status = "Auto Sync · reanuncio preventivo espaciado (pantalla no verificada)"
            watch.record("MUSICA-AUTO", "Reanuncio preventivo a partir de 180 s; solo con iWatch visible")
        }
        lastSubmittedSignature = signature
        lastAnnouncedAt = now
    }

    private func scheduleOneShotVerification(of signature: String) {
        transitionVerification?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self,
                  self.lastSubmittedSignature == signature,
                  WatchBLEManager.shared.isConnected,
                  UIApplication.shared.applicationState == .active else { return }
            self.pendingTransitionSignature = signature
            self.pendingTransitionUntil = Date().addingTimeInterval(
                MusicAutoSyncPolicy.transitionVerificationLifetime)
            WatchBLEManager.shared.record("MUSICA-AUTO",
                "Verificación única del cambio natural: consultando estado actual, sin reutilizar caché")
            // Si no hay respuesta válida o la canción ya cambió, el reanuncio
            // no se realiza. La lectura del SDK tiene prioridad sobre Web API.
            SpotifyBridge.shared.forceWatchMusicRecovery()
        }
        transitionVerification = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MusicAutoSyncPolicy.transitionVerificationDelay,
            execute: work)
    }
}
