import Foundation
import UIKit

// Lectura Web acotada en la transición a bloqueo. iOS puede suspender o
// finalizar la aplicación: esto NO habilita polling continuo con pantalla apagada.
final class SpotifyLockMetadataHandoff {
    static let shared = SpotifyLockMetadataHandoff()
    private var task: Task<Void, Never>?
    private var token: UIBackgroundTaskIdentifier = .invalid
    private init() {}

    func didEnterBackground() {
        guard task == nil,
              !MusicBackgroundExperiment.shared.enabled,
              SpotifyBridge.shared.controlEnabled,
              WatchBLEManager.shared.isConnected else { return }
        token = UIApplication.shared.beginBackgroundTask(
            withName: "iWatchSpotifyMetadataAtLock",
            expirationHandler: { [weak self] in
                DispatchQueue.main.async {
                    self?.task?.cancel()
                    self?.finish()
                }
            })
        guard token != .invalid else { return }
        WatchBLEManager.shared.record("SPOTIFY-WEB", "Verificación breve al bloquear; sin consulta periódica")
        task = Task { @MainActor [weak self] in
            await SpotifyBridge.shared.refreshPlaybackInfo(
                allowSDKFallback: true, bypassAutomaticCooldown: true)
            self?.finish()
        }
    }

    func didBecomeActive() {
        task?.cancel()
        finish()
    }

    private func finish() {
        task = nil
        guard token != .invalid else { return }
        let finishingToken = token
        token = .invalid
        UIApplication.shared.endBackgroundTask(finishingToken)
    }
}
