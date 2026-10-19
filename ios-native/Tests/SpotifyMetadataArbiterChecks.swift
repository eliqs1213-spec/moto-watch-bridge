import Foundation

func arbiterCheck(_ ok: Bool, _ msg: String) {
    precondition(ok, msg)
}
let request = Date(timeIntervalSince1970: 12_000)
arbiterCheck(SpotifyMetadataArbiter.acceptsWebResponse(
    requestStartedAt: request, latestAcceptedAt: nil), "sin datos previos")
arbiterCheck(SpotifyMetadataArbiter.acceptsWebResponse(
    requestStartedAt: request, latestAcceptedAt: request.addingTimeInterval(-3)),
    "Web debe poder actualizar un SDK anterior")
arbiterCheck(!SpotifyMetadataArbiter.acceptsWebResponse(
    requestStartedAt: request, latestAcceptedAt: request.addingTimeInterval(1)),
    "GET antiguo no pisa un evento SDK o Web posterior")
arbiterCheck(SpotifyMetadataArbiter.shouldCrossCheckWeb(
    sdkFresh: false, sinceLastWebRequest: 7), "SDK silencioso admite Web")
arbiterCheck(!SpotifyMetadataArbiter.shouldCrossCheckWeb(
    sdkFresh: true, sinceLastWebRequest: 8), "sin GET redundante cada 7s")
arbiterCheck(SpotifyMetadataArbiter.shouldCrossCheckWeb(
    sdkFresh: true, sinceLastWebRequest: 21), "SDK fresco no impide validar con Web")
arbiterCheck(SpotifyMetadataArbiter.sdkEventIsUsable(title: "Canción", playing: true),
             "SDK válido")
arbiterCheck(!SpotifyMetadataArbiter.sdkEventIsUsable(title: " ", playing: true),
             "SDK sin pista no reemplaza metadatos")
print("Spotify metadata arbiter checks: OK")
