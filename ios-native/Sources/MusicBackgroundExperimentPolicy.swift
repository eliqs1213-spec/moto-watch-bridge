import Foundation

// Core Bluetooth puede despertar una app suspendida para atender eventos
// auténticos. Eso NO equivale a obtener ejecución periódica garantizada:
// únicamente se consulta Spotify al recibir un evento BLE real y con
// suficiente distancia entre consultas para no saturar Spotify.
enum MusicBackgroundExperimentPolicy {
    static let bleCooldownSeconds: TimeInterval = 35
    static let foregroundExitOffsets: [UInt64] = [0, 9, 18]

    static func canProbeFromBLE(enabled: Bool, inBackground: Bool,
                                watchReady: Bool, spotifyEnabled: Bool,
                                isMusicCommand: Bool, isBusy: Bool,
                                secondsSinceLastAttempt: TimeInterval) -> Bool {
        enabled && inBackground && watchReady && spotifyEnabled &&
            !isMusicCommand && !isBusy &&
            secondsSinceLastAttempt >= bleCooldownSeconds
    }

    static func canContinueShortWindow(remainingTime: TimeInterval,
                                       enabled: Bool, background: Bool) -> Bool {
        enabled && background && remainingTime > 6
    }
}
