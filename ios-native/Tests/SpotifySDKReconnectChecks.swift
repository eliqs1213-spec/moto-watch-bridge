import Foundation

func requireSDK(_ valid: Bool, _ message: String) {
    guard valid else { fatalError(message) }
}

let now = Date(timeIntervalSince1970: 1_000_000)
requireSDK(SpotifySDKReconnectPolicy.shouldConnect(
    enabled: true, inForeground: true, connected: false,
    lastAttempt: nil, now: now), "Primera reconexión foreground")
requireSDK(!SpotifySDKReconnectPolicy.shouldConnect(
    enabled: true, inForeground: true, connected: false,
    lastAttempt: now, now: now.addingTimeInterval(2)), "ScenePhase/Delegate no deben duplicar connect()")
requireSDK(!SpotifySDKReconnectPolicy.shouldConnect(
    enabled: true, inForeground: false, connected: false,
    lastAttempt: nil, now: now), "No conectar SDK en background")
requireSDK(!SpotifySDKReconnectPolicy.shouldConnect(
    enabled: true, inForeground: true, connected: true,
    lastAttempt: nil, now: now), "No reconectar SDK conectado")
requireSDK(!SpotifySDKReconnectPolicy.shouldConnect(
    enabled: false, inForeground: true, connected: false,
    lastAttempt: nil, now: now), "No reactivar SDK deshabilitado")
requireSDK(SpotifySDKReconnectPolicy.shouldConnect(
    enabled: true, inForeground: true, connected: false,
    lastAttempt: now, now: now.addingTimeInterval(8)), "Reintentar solo tras pausa mínima")
requireSDK(SpotifySDKReconnectPolicy.shouldConnect(
    enabled: true, inForeground: true, connected: false,
    lastAttempt: now, now: now.addingTimeInterval(1), force: true),
    "Reintento manual explícito permitido")
requireSDK(!SpotifySDKReconnectPolicy.shouldConnect(
    enabled: true, inForeground: false, connected: false,
    lastAttempt: nil, now: now, force: true), "Manual no evita restricción background")
requireSDK(SpotifySDKReconnectPolicy.responseTimeoutSeconds == 12,
    "No dejar Reconectando de forma indefinida")
print("Spotify SDK reconnect policy checks: OK")
