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
        // iOS puede devolver greatestFiniteMagnitude como valor especial:
        // permitir una ventana CORTA no significa hacer polling infinito.
        enabled && background && remainingTime > 6
    }

    static func remainingTimeLabel(_ seconds: TimeInterval) -> String {
        // Nunca convertir Double.greatestFiniteMagnitude a Int:
        // Swift hace trap y termina el proceso, incluso en interpolaciones
        // dentro de un log. El valor no significa CPU ilimitada.
        guard seconds.isFinite, seconds >= 0 else {
            return "no disponible"
        }
        guard seconds < 86_400 else {
            return "valor especial de iOS (no equivale a tiempo ilimitado)"
        }
        return "\(Int(seconds)) s"
    }

    // Diagnóstico: solo se registra el tipo de trama observado por F8F0.
    // Nunca se persiste el payload completo (puede contener datos de salud).
    static func bleFrameType(_ data: Data) -> String {
        let bytes = [UInt8](data)
        guard bytes.count >= 6, bytes[0] == 0xAA else { return "fragmento/no-AA" }
        let declaredSize = Int(bytes[1]) | (Int(bytes[2]) << 8)
        let kind = String(format: "%02X/%02X", bytes[4], bytes[5])
        return declaredSize + 4 == bytes.count ? kind : kind + " (fragmento)"
    }

    // No inundar el registro persistente con ráfagas BLE o paquetes de salud.
    // Primer evento por tipo y consultas realmente elegibles siempre se anotan;
    // los demás se agregan al resumen y sólo dejan una muestra cada 45 s.
    static let frameLogInterval: TimeInterval = 45
    static func shouldLogBLEFrame(firstOfType: Bool, queryEligible: Bool,
                                  secondsSinceLastLog: TimeInterval) -> Bool {
        firstOfType || queryEligible || secondsSinceLastLog >= frameLogInterval
    }

}
