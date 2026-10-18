import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

let now = Date(timeIntervalSince1970: 3_000_000)
check(SpotifyMetadataRefreshPolicy.shouldStart(
    inFlight: false, forced: false, lastAutomaticAt: .distantPast, now: now),
    "Primer refresco permitido")
check(!SpotifyMetadataRefreshPolicy.shouldStart(
    inFlight: true, forced: true, lastAutomaticAt: .distantPast, now: now),
    "Evitar solicitudes paralelas incluso si se fuerza")
check(!SpotifyMetadataRefreshPolicy.shouldStart(
    inFlight: false, forced: false, lastAutomaticAt: now.addingTimeInterval(-5), now: now),
    "Evitar polling excesivo")
check(SpotifyMetadataRefreshPolicy.shouldStart(
    inFlight: false, forced: false, lastAutomaticAt: now.addingTimeInterval(-12), now: now),
    "Permitir consulta luego del intervalo")
check(SpotifyMetadataRefreshPolicy.shouldStart(
    inFlight: false, forced: true, lastAutomaticAt: now, now: now),
    "Permitir consulta manual aun con cooldown")
print("Spotify metadata Web API policy checks passed")
