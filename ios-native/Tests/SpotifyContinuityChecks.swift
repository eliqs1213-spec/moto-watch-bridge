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
