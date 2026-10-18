import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

let now = Date(timeIntervalSince1970: 3_000_000)
func permitted(_ previous: TimeInterval, playing: Bool = true,
               forced: Bool = false, inFlight: Bool = false,
               retry: TimeInterval? = nil) -> Bool {
    SpotifyMetadataRefreshPolicy.shouldStart(
        inFlight: inFlight, forced: forced,
        lastAutomaticAt: now.addingTimeInterval(-previous),
        now: now, isPlaying: playing,
        retryAfterUntil: retry.map { now.addingTimeInterval($0) })
}
check(permitted(0, forced: true), "Permitir resync manual")
check(!permitted(100, forced: true, inFlight: true), "No GET paralelo")
check(!permitted(5), "Mientras reproduce, evitar polling antes de 7 s")
check(permitted(7), "Mientras reproduce, permitir consulta a 7 s")
check(!permitted(17, playing: false), "Mientras pausa, evitar polling antes de 18 s")
check(permitted(18, playing: false), "Mientras pausa, permitir consulta a 18 s")
check(!permitted(100, retry: 35), "Respetar Retry-After")
check(!permitted(100, forced: true, retry: 35), "Forzado tampoco evade 429")
check(permitted(100, retry: -1), "Permitir recuperación tras Retry-After")
check(SpotifyMetadataRefreshPolicy.shouldRefreshUnauthorizedGET(method: "GET", statusCode: 401), "Renovar token en GET 401")
check(!SpotifyMetadataRefreshPolicy.shouldRefreshUnauthorizedGET(method: "POST", statusCode: 401), "No repetir siguiente/previo")
check(!SpotifyMetadataRefreshPolicy.shouldRefreshUnauthorizedGET(method: "PUT", statusCode: 401), "No repetir play/pausa")
check(!SpotifyMetadataRefreshPolicy.shouldRefreshUnauthorizedGET(method: "GET", statusCode: 429), "429 no se soluciona renovando token")
check(SpotifyMetadataRefreshPolicy.nearTrackEndProbeDelay(
    progressMs: 165_000, durationMs: 180_000, isPlaying: true) == 16,
    "Programar comprobación un segundo después de fin previsto")
check(SpotifyMetadataRefreshPolicy.nearTrackEndProbeDelay(
    progressMs: 100_000, durationMs: 180_000, isPlaying: true) == nil,
    "No programar comprobación prematura de pista larga")
check(SpotifyMetadataRefreshPolicy.nearTrackEndProbeDelay(
    progressMs: 179_800, durationMs: 180_000, isPlaying: true) == 1.2,
    "Transición próxima: consulta sin delay largo")
check(SpotifyMetadataRefreshPolicy.nearTrackEndProbeDelay(
    progressMs: 20_000, durationMs: 180_000, isPlaying: false) == nil,
    "Pausa no implica transición automática")
check(SpotifyMetadataRefreshPolicy.nearTrackEndProbeDelay(
    progressMs: 180_100, durationMs: 180_000, isPlaying: true) == nil,
    "Posición inválida no habilita consulta")
print("Spotify Web metadata policy: eighteen checks passed")
