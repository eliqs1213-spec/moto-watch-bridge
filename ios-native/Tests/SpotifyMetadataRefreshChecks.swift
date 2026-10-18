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
print("Spotify Web metadata policy: nine checks passed")
