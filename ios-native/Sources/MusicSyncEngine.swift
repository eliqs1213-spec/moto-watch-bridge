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

    private init() {}

    func reset() {
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
        // aunque representen la misma canción. El nombre/artista/estado
        // determinan si debemos reanunciar; progreso no es un nuevo tema.
        let signature = "\(snapshot.title)|\(snapshot.artist)|\(snapshot.isPlaying)"
        let recoveryIsCurrent = pendingRecovery != nil && now <= pendingUntil
        let isReconnect = recoveryIsCurrent && pendingRecovery == .reconnect
        let elapsed = now.timeIntervalSince(lastAnnouncedAt)
        let decision = MusicAutoSyncPolicy.decide(
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
            watch.sendMusic(snapshot)
            status = "Auto Sync · cambio de canción/estado enviado (pantalla no verificada)"
        case .manual:
            watch.sendMusic(snapshot, force: true, reannounce: true)
            status = "Auto Sync · resincronización manual enviada (pantalla no verificada)"
        case .recovery:
            watch.sendMusic(snapshot, force: true, reannounce: true)
            status = isReconnect
                ? "Auto Sync · recuperando tras reconexión (pantalla no verificada)"
                : "Auto Sync · recuperando al abrir iWatch (pantalla no verificada)"
            watch.record("MUSICA-AUTO", isReconnect
                ? "Reanuncio controlado tras reconexión con pista validada"
                : "Reanuncio controlado al volver a primer plano con pista validada")
        case .heartbeat:
            watch.sendMusic(snapshot, force: true, reannounce: true)
            status = "Auto Sync · reanuncio preventivo espaciado (pantalla no verificada)"
            watch.record("MUSICA-AUTO", "Reanuncio preventivo a partir de 180 s; solo con iWatch visible")
        }
        lastSubmittedSignature = signature
        lastAnnouncedAt = now
    }
}
