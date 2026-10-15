import Foundation

func verify(_ actual: SpotifyPlaybackContinuityPolicy.Decision,
            _ expected: SpotifyPlaybackContinuityPolicy.Decision, _ name: String) {
    guard actual == expected else { fatalError("\(name): expected \(expected), got \(actual)") }
}

// /me/player HTTP 204 al pausar una canción NO debe borrar el reloj.
verify(SpotifyPlaybackContinuityPolicy.decide(unavailableSeconds: 0, hasLastTrack: true), .waiting,
       "Primera consulta sin reproductor")
verify(SpotifyPlaybackContinuityPolicy.decide(unavailableSeconds: 29.9, hasLastTrack: true), .waiting,
       "Tolerancia antes de 30 s")
verify(SpotifyPlaybackContinuityPolicy.decide(unavailableSeconds: 30, hasLastTrack: true), .preserveLastTrack,
       "Pausa larga debe conservar metadatos")
verify(SpotifyPlaybackContinuityPolicy.decide(unavailableSeconds: 3600, hasLastTrack: true), .preserveLastTrack,
       "Sin pruebas de cierre no borrar canción por tiempo")
verify(SpotifyPlaybackContinuityPolicy.decide(unavailableSeconds: 30, hasLastTrack: false), .showIdle,
       "Nunca se observó una canción")
verify(SpotifyPlaybackContinuityPolicy.decide(unavailableSeconds: 10, hasLastTrack: false), .waiting,
       "Ausencia inicial por pocos segundos")
verify(SpotifyPlaybackContinuityPolicy.decide(unavailableSeconds: 45, hasLastTrack: true, graceSeconds: 60), .waiting,
       "Tolerancia personalizada")
print("Spotify playback continuity checks: OK")


func verifyCheck(_ ok: Bool, _ name: String) {
    guard ok else { fatalError(name) }
}

let baseline = Date(timeIntervalSince1970: 1_000_000)
verifyCheck(SpotifyCommandQueuePolicy.isFresh(receivedAt: baseline,
                now: baseline.addingTimeInterval(0)), "Comando recién recibido")
verifyCheck(SpotifyCommandQueuePolicy.isFresh(receivedAt: baseline,
                now: baseline.addingTimeInterval(6)), "Comando válido a 6 s")
verifyCheck(!SpotifyCommandQueuePolicy.isFresh(receivedAt: baseline,
                now: baseline.addingTimeInterval(6.1)), "Comando caducado")
verifyCheck(SpotifyCommandQueuePolicy.maxPending == 2, "Límite de cola")
verifyCheck(SpotifyCommandQueuePolicy.isTransientHTTP(502), "HTTP 502 es transitorio")
verifyCheck(SpotifyCommandQueuePolicy.isTransientHTTP(503), "HTTP 503 es transitorio")
verifyCheck(SpotifyCommandQueuePolicy.isTransientHTTP(429), "HTTP 429 es transitorio")
verifyCheck(!SpotifyCommandQueuePolicy.isTransientHTTP(404), "404 no es transitorio 5xx")
verifyCheck(!SpotifyCommandQueuePolicy.isTransientHTTP(401), "401 exige autorizar")
let missingSince = Date(timeIntervalSince1970: 2_000_000)
let blockingUntil = missingSince.addingTimeInterval(SpotifyCommandQueuePolicy.noActiveDeviceCooldownSeconds)
verifyCheck(SpotifyCommandQueuePolicy.noActiveDeviceCooldownSeconds == 20, "Cooldown ante 404 debe ser 20 s")
verifyCheck(SpotifyCommandQueuePolicy.shouldHoldSkip(until: blockingUntil, now: missingSince),
            "No filtra tormenta inicial 404")
verifyCheck(SpotifyCommandQueuePolicy.shouldHoldSkip(until: blockingUntil, now: missingSince.addingTimeInterval(19)),
            "No filtra repetición antes de 20 s")
verifyCheck(!SpotifyCommandQueuePolicy.shouldHoldSkip(until: blockingUntil, now: missingSince.addingTimeInterval(20)),
            "El cooldown no se libera a los 20 s")
verifyCheck(!SpotifyCommandQueuePolicy.shouldHoldSkip(until: nil, now: missingSince),
            "No permitir controles cuando no hay bloqueo")

print("Spotify pending commands checks: OK")
