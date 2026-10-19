import Foundation

// No existe prioridad fija entre las fuentes de Spotify.
// Una respuesta de red sólo puede aplicarse si ninguna fuente aceptó una
// observación MÁS RECIENTE desde que comenzó ese GET.
enum SpotifyMetadataArbiter {
    static let webCrossCheckWhenSDKFresh: TimeInterval = 21

    static func acceptsWebResponse(requestStartedAt: Date,
                                   latestAcceptedAt: Date?) -> Bool {
        guard let latestAcceptedAt else { return true }
        return latestAcceptedAt <= requestStartedAt
    }

    static func shouldCrossCheckWeb(sdkFresh: Bool,
                                    sinceLastWebRequest: TimeInterval) -> Bool {
        !sdkFresh || sinceLastWebRequest >= webCrossCheckWhenSDKFresh
    }

    // Aceptar un evento SDK realmente recibido, no el simple indicador
    // "conectado". Un SDK suscrito y silencioso no veta la consulta HTTP.
    static func sdkEventIsUsable(title: String, playing: Bool) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
