import Foundation

func shortcutCheck(_ ok: Bool, _ message: String) { precondition(ok, message) }
let start = Date(timeIntervalSince1970: 123456789)
shortcutCheck(!SpotifyShortcutSyncPolicy.hasNewObservation(
    startedAt: start, acceptedAt: nil), "sin respuesta no confirma éxito")
shortcutCheck(!SpotifyShortcutSyncPolicy.hasNewObservation(
    startedAt: start, acceptedAt: start.addingTimeInterval(-1)), "caché antiguo no confirma éxito")
shortcutCheck(SpotifyShortcutSyncPolicy.hasNewObservation(
    startedAt: start, acceptedAt: start), "evento contemporáneo confirma observación")
shortcutCheck(SpotifyShortcutSyncPolicy.hasNewObservation(
    startedAt: start, acceptedAt: start.addingTimeInterval(2)), "respuesta reciente confirma observación")
print("Spotify Shortcuts sync policy: OK")
