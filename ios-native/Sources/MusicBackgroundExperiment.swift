import Foundation
import Combine
import UIKit
import ActivityKit

// Experimento EXPLÍCITO. No hay audio silencioso, polling infinito, ni
// lecturas de batería artificiales. Una Live Activity mejora ciertas
// operaciones Bluetooth en iOS 26, pero NO garantiza CPU ni eventos Spotify.
final class MusicBackgroundExperiment: ObservableObject {
    static let shared = MusicBackgroundExperiment()
    @Published private(set) var enabled = false
    @Published private(set) var status = "Prueba experimental desactivada"

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var probeTask: Task<Void, Never>?
    private var epoch = 0
    private var isFetching = false
    private var lastAttemptAt = Date.distantPast
    private var backgroundEnteredAt: Date?

    private init() {}

    func start() {
        guard #available(iOS 26.0, *) else {
            status = "La prueba con Actividad en vivo requiere iOS 26 o posterior"
            return
        }
        guard WatchBLEManager.shared.isConnected && SpotifyBridge.shared.controlEnabled else {
            status = "Antes conectá el reloj y activá controles Spotify"
            return
        }
        enabled = true
        lastAttemptAt = .distantPast
        status = "Iniciando Actividad en vivo · esperá a verla antes de bloquear"
        WatchBLEManager.shared.record("BG-EXPERIMENTO",
            "Inicio voluntario; iOS 26+; solo BLE real y breve ventana de salida; no garantiza actualización continua")
        // El gestor de Actividad en vivo existente usa la batería real.
        // El CBManager ya está instanciado desde didFinishLaunching.
        BatteryLiveActivityManager.shared.start(
            percentage: WatchBLEManager.shared.batteryPercentage)
    }

    func stop() {
        enabled = false
        epoch &+= 1
        probeTask?.cancel()
        probeTask = nil
        finishBackgroundTask()
        backgroundEnteredAt = nil
        isFetching = false
        status = "Prueba experimental detenida · Music Auto Sync normal"
        WatchBLEManager.shared.record("BG-EXPERIMENTO",
            "Prueba detenida; sin consultas adicionales")
        // Esta función es también un control explícito de la actividad de
        // batería compartida. La UI advierte que la actividad se detiene.
        BatteryLiveActivityManager.shared.stop()
    }

    func didEnterBackground() {
        guard enabled else { return }
        epoch &+= 1
        let currentEpoch = epoch
        backgroundEnteredAt = Date()
        let active = !Activity<MotoBatteryActivityAttributes>.activities.isEmpty
        WatchBLEManager.shared.record("BG-EXPERIMENTO",
            "Bloqueo: Live Activity \(active ? "activa" : "NO activa"); reloj=\(WatchBLEManager.shared.isConnected); esperando permisos reales iOS")
        status = active ? "Bloqueado · Live Activity activa; comprobando tiempo concedido" :
            "Bloqueado · Live Activity no iniciada; sin privilegios nuevos"
        guard active && WatchBLEManager.shared.isConnected else { return }

        // Tiempo FINITO para terminar tareas al ir al fondo. No confundir
        // beginBackgroundTask con una extensión permanente de ejecución.
        backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "MotoWatchMusicBackgroundTrial",
            expirationHandler: { [weak self] in
                self?.probeTask?.cancel()
                self?.probeTask = nil
                self?.status = "iOS agotó tiempo de ejecución de la prueba"
                WatchBLEManager.shared.record("BG-EXPERIMENTO",
                    "Expiró el tiempo de segundo plano; no se programan más sondeos")
                self?.finishBackgroundTask()
            })

        probeTask?.cancel()
        probeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var previous: UInt64 = 0
            for (index, second) in MusicBackgroundExperimentPolicy.foregroundExitOffsets.enumerated() {
                let delay = second - previous
                previous = second
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                }
                guard !Task.isCancelled, self.enabled,
                      self.epoch == currentEpoch,
                      UIApplication.shared.applicationState == .background else { break }
                let remaining = UIApplication.shared.backgroundTimeRemaining
                guard MusicBackgroundExperimentPolicy.canContinueShortWindow(
                    remainingTime: remaining, enabled: self.enabled, background: true
                ) else {
                    WatchBLEManager.shared.record("BG-EXPERIMENTO",
                        "Ventana limitada agotada antes del intento \(index+1)")
                    break
                }
                WatchBLEManager.shared.record("BG-EXPERIMENTO",
                    "Ventana al bloquear: consulta \(index+1)/3; tiempo iOS restante ~\(Int(remaining)) s")
                await self.fetchNow(trigger: "bloqueo \(index+1)/3")
            }
            self.finishBackgroundTask()
            WatchBLEManager.shared.record("BG-EXPERIMENTO",
                "Ventana inicial finalizada o suspendida; sin ejecución periódica garantizada")
        }
    }

    func willEnterForeground() {
        guard enabled else { return }
        epoch &+= 1
        probeTask?.cancel()
        probeTask = nil
        finishBackgroundTask()
        let elapsed = backgroundEnteredAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        status = "Volvió al primer plano tras ~\(elapsed) s; revisá registro BG-EXPERIMENTO"
        WatchBLEManager.shared.record("BG-EXPERIMENTO",
            "Desbloqueo tras ~\(elapsed) s; verificar qué consultas se ejecutaron realmente con teléfono bloqueado")
        backgroundEnteredAt = nil
    }

    // Un F8F0 real puede despertar la app para entregar datos de BLE. NO
    // enviamos eventos sintéticos para provocar ese despertar.
    func didReceiveRealBLEFrame(_ data: Data) {
        let command = MotoProtocol.decode(data)
        let isMusicCommand: Bool
        switch command {
        case .next?, .previous?, .toggle?: isMusicCommand = true
        default: isMusicCommand = false
        }
        let now = Date()
        guard MusicBackgroundExperimentPolicy.canProbeFromBLE(
            enabled: enabled,
            inBackground: UIApplication.shared.applicationState == .background,
            watchReady: WatchBLEManager.shared.isConnected,
            spotifyEnabled: SpotifyBridge.shared.controlEnabled,
            isMusicCommand: isMusicCommand,
            isBusy: isFetching,
            secondsSinceLastAttempt: now.timeIntervalSince(lastAttemptAt)
        ) else { return }
        lastAttemptAt = now
        WatchBLEManager.shared.record("BG-EXPERIMENTO",
            "Evento F8F0 auténtico recibido con teléfono bloqueado; buscando canción Spotify, sin poll BLE")
        Task { @MainActor [weak self] in
            await self?.fetchNow(trigger: "notificación BLE real")
        }
    }

    private func fetchNow(trigger: String) async {
        guard enabled, !isFetching, SpotifyBridge.shared.controlEnabled,
              WatchBLEManager.shared.isConnected,
              UIApplication.shared.applicationState == .background else { return }
        lastAttemptAt = Date()
        isFetching = true
        let started = Date()
        defer { isFetching = false }
        // Esta lectura ya alimenta MusicSyncEngine, y solo manda 24/01 cuando
        // el título/estado cambió. Mantener firma y cola de la 8.4.13.
        await SpotifyBridge.shared.refreshPlaybackInfo()
        WatchBLEManager.shared.record("BG-EXPERIMENTO",
            "Consulta \(trigger) completada en \(Int(Date().timeIntervalSince(started) * 1000)) ms; no prueba actualización visual")
    }

    private func finishBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        let token = backgroundTask
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(token)
    }
}
