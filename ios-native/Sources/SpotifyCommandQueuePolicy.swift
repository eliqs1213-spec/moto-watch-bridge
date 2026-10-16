import Foundation

// "Siguiente", "Anterior" y "Play/Pausa" no son operaciones idempotentes.
// Una orden pendiente solo se ejecuta si el usuario la solicitó de verdad,
// dentro de una ventana breve. Nunca se crea un reintento automático ante 5xx.
enum SpotifyCommandQueuePolicy {
    static let maxPending = 2
    static let expirationSeconds: TimeInterval = 6
    // Después de NO_ACTIVE_DEVICE no insistir en NEXT/PREV a cada pulsación.
    // Reabrir Spotify o recibir un estado Web/SDK con dispositivo activo
    // libera el bloqueo inmediatamente.
    static let noActiveDeviceCooldownSeconds: TimeInterval = 20
    // Un toque NUEVO en el reloj puede solicitar una comprobación de estado
    // de Spotify incluso mientras NEXT/PREV está protegido por un 404.
    // Nunca reejecutar automáticamente el comando que produjo el 404.
    static let blockedSkipProbeCooldownSeconds: TimeInterval = 4

    static func shouldProbeBlockedSkip(until: Date?, lastProbeAt: Date?,
                                       now: Date, requestBusy: Bool,
                                       probeBusy: Bool) -> Bool {
        guard shouldHoldSkip(until: until, now: now),
              !requestBusy, !probeBusy else { return false }
        if let last = lastProbeAt,
           now.timeIntervalSince(last) < blockedSkipProbeCooldownSeconds { return false }
        return true
    }

    // Únicamente para órdenes Web API de reproducción conocidas (no OAuth).
    // Spotify devuelve tanto NO_ACTIVE_DEVICE como un 404 genérico ("Not found")
    // si el dispositivo Connect desaparece al pausar el iPhone.
    static func isMissingPlayerCommandResponse(status: Int) -> Bool {
        status == 404
    }

    static func shouldHoldSkip(until: Date?, now: Date) -> Bool {
        guard let until = until else { return false }
        return now < until
    }

    static func isFresh(receivedAt: Date, now: Date) -> Bool {
        let seconds = now.timeIntervalSince(receivedAt)
        return seconds >= 0 && seconds <= expirationSeconds
    }

    static func isTransientHTTP(_ status: Int) -> Bool {
        return status == 429 || (500...599).contains(status)
    }
}
