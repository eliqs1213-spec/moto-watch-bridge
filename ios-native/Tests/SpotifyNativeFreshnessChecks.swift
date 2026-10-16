import Foundation

func assertStatus(_ ok: @autoclosure () -> Bool, _ label: String) {
    guard ok() else { fatalError(label) }
}
let now = Date(timeIntervalSince1970: 2_000_000)
func fresh(connected: Bool = true, metadata: Bool = true,
           age: TimeInterval? = 0) -> Bool {
    let last = age.map { now.addingTimeInterval(-$0) }
    return SpotifyNativeFreshnessPolicy.isFresh(
        connected: connected, hasMetadata: metadata,
        lastReceivedAt: last, now: now)
}
assertStatus(fresh(age: 0), "SDK recién recibido")
assertStatus(fresh(age: 19.9), "SDK válido antes del umbral")
assertStatus(fresh(age: 20), "SDK válido al límite")
assertStatus(!fresh(age: 20.1), "SDK estancado: fallback Web habilitado")
assertStatus(!fresh(age: 660), "11 minutos sin evento debe habilitar Web")
assertStatus(!fresh(connected: false), "SDK desconectado")
assertStatus(!fresh(metadata: false), "Sin metadatos SDK")
assertStatus(!fresh(age: nil), "Suscripto sin evento nunca es fresco")
assertStatus(!fresh(age: -1), "Timestamp futuro inválido")
print("Spotify SDK freshness checks passed: 20 s, 11 minutes stale, disconnected, no callback")
