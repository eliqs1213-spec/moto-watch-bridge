import Foundation
import AuthenticationServices
import CryptoKit
import Security
import SwiftUI
import UIKit

private struct SpotifyCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: TimeInterval
}

private enum SecureTokenStorage {
    static let service = "org.motowatchbridge.spotify"
    static let account = "oauth-token"

    static func load() -> SpotifyCredentials? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SpotifyCredentials.self, from: data)
    }

    static func save(_ value: SpotifyCredentials) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attrs.forEach { insert[$0.key] = $0.value }
            _ = SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func clear() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

private struct SpotifyPlayback: Decodable {
    struct Device: Decodable {
        let id: String?
        let name: String?
    }
    struct Artist: Decodable { let name: String }
    struct Album: Decodable { let name: String }
    struct Song: Decodable {
        let id: String?
        let name: String
        let duration_ms: Int?
        let artists: [Artist]?
        let album: Album?
    }
    let is_playing: Bool
    let progress_ms: Int?
    let device: Device?
    let item: Song?
}

private struct SpotifyConnectDevices: Decodable {
    struct Device: Decodable {
        let id: String?
        let name: String
        let type: String
        let is_active: Bool
        let is_restricted: Bool
    }
    let devices: [Device]
}

private struct OAuthReply: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
}

enum SpotifyBridgeError: LocalizedError {
    case invalidClientId
    case unauthorized
    case sessionExpired
    case emptyPlayer
    case badURL
    case response(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidClientId: return "Ingresá un Spotify Client ID válido (32 caracteres)."
        case .unauthorized: return "Autorizá Spotify desde la app antes de usar el reloj."
        case .sessionExpired: return "Spotify requiere volver a autorizar."
        case .emptyPlayer: return "Spotify no informó reproducción activa. Abrí Spotify y reproducí una canción primero."
        case .badURL: return "No se pudo generar la URL de Spotify."
        case let .response(status, body): return "Spotify HTTP \(status): \(body.prefix(180))"
        }
    }
}

final class SpotifyBridge: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = SpotifyBridge()
    static let redirect = "motowatchbridgeeliqs://callback"
    static let callbackScheme = "motowatchbridgeeliqs"

    @Published var clientID: String = UserDefaults.standard.string(forKey: "motowatch.spotify.clientid") ?? ""
    @Published private(set) var status: String = SecureTokenStorage.load() == nil ? "Sin autorizar" : "Token guardado"
    @Published private(set) var lastSong: String = "Sin canción"
    @Published private(set) var lastAction: String = "Esperando comandos"
    @Published var controlEnabled: Bool = UserDefaults.standard.bool(forKey: "motowatch.spotify.enabled")
    @Published private(set) var playbackAvailability = "Sin comprobar"
    // Diagnóstico: fuente que produjo los últimos metadatos aceptados.
    @Published private(set) var metadataSource = "Sin datos"

    private var authentication: ASWebAuthenticationSession?
    private var oauthVerifier = ""
    private var oauthState = ""
    private var lastDeviceID: String?
    private var lastIsPlaying: Bool?
    private var lastMusicSnapshot: WatchMusicSnapshot?
    // Cada evento nativo invalida consultas Web todavía pendientes.
    // Evita que un GET /me/player lento reemplace una pista más nueva del SDK.
    private var sdkMetadataRevision: UInt64 = 0
    private var controlEpoch: UInt64 = 0
    private var recoveryInProgress = false
    private var unavailableChecks = 0
    private var idleModeRequested = false
    private let inactiveThreshold = 3
    // Confirmar ausencia de reproductor durante ~30 s, no sólo 3 consultas.
    private let inactiveGraceSeconds: TimeInterval = 30
    private var playerUnavailableSince: Date?
    private var retainedTrackWarningLogged = false
    private var manualResyncUntil: Date?
    private var manualIdlePreviewUntil: Date?
    private var requestBusy = false
    // Evita respuestas Web duplicadas de distintas pantallas y callbacks.
    private var playbackRefreshInProgress = false
    private var lastAutomaticWebRefreshAt = Date.distantPast
    private var skipNoActiveDeviceUntil: Date?
    private var lastBlockedSkipLoggedAt = Date.distantPast
    private var lastBlockedSkipProbeAt: Date?
    private var blockedSkipProbeInProgress = false
    private struct PendingWatchCommand {
        let command: WatchCommand
        let receivedAt: Date
    }
    private var pendingWatchCommands: [PendingWatchCommand] = []
    private var lastCommandTimes: [String: Date] = [:]
    private let scopes = "user-read-playback-state user-modify-playback-state"

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first(where: { $0.isKeyWindow })
        return window ?? ASPresentationAnchor()
    }

    func setEnabled(_ enabled: Bool) {
        controlEpoch &+= 1
        controlEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "motowatch.spotify.enabled")
        if !enabled {
            skipNoActiveDeviceUntil = nil
            lastBlockedSkipProbeAt = nil
            pendingWatchCommands.removeAll()
            manualResyncUntil = nil
            MusicSyncEngine.shared.reset()
            sendIdle(reason: "Controles Spotify desactivados")
            playbackAvailability = "Controles desactivados"
            metadataSource = "Desactivado"
            status = "Controles Spotify desactivados"
        } else {
            // Al reactivar hay que pedir un estado NUEVO: el SDK puede seguir
            // marcando hasNativeMetadata de antes de apagar los controles.
            playbackAvailability = "Reactivando controles · verificando Spotify"
            metadataSource = "Verificando estado actual"
            status = "Spotify reactivado · esperando datos nuevos"
            MusicSyncEngine.shared.requestControlReactivation()
            record("Spotify: controles reactivados; solicitando estado actual SDK/Web API")
            let enabledAt = Date()
            let epoch = controlEpoch
            if SpotifyAppRemoteBridge.shared.isConnected {
                SpotifyAppRemoteBridge.shared.requestCurrentPlayerState(fallbackToWeb: true)
                // Algunos SDK quedan «Suscripto» sin nuevos callbacks.
                // Si la reactivación no recibió dato fresco después de 4 s,
                // intentar Web API una vez, no reabrir OAuth ni Spotify.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    guard controlEnabled && controlEpoch == epoch else { return }
                    let nativeUpdated = SpotifyAppRemoteBridge.shared.lastNativeReceivedAt
                        .map { $0 >= enabledAt } ?? false
                    if !nativeUpdated {
                        record("Spotify: SDK sin respuesta nueva al reactivar; intentando Web API")
                        await refreshPlaybackInfo(force: true, allowSDKFallback: true)
                    }
                }
            } else {
                Task { await refreshPlaybackInfo(force: true) }
            }
        }
    }

    func authorize() {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.count == 32, id.allSatisfy({ $0.isHexDigit }) else {
            status = SpotifyBridgeError.invalidClientId.localizedDescription
            return
        }
        UserDefaults.standard.set(id, forKey: "motowatch.spotify.clientid")
        let random = (0..<48).map { _ in UInt8.random(in: 0...255) }
        oauthVerifier = Data(random).base64URLEncodedString()
        oauthState = UUID().uuidString
        let challenge = Data(SHA256.hash(data: Data(oauthVerifier.utf8))).base64URLEncodedString()
        var url = URLComponents(string: "https://accounts.spotify.com/authorize")!
        url.queryItems = [URLQueryItem(name: "client_id", value: id),
                          URLQueryItem(name: "response_type", value: "code"),
                          URLQueryItem(name: "redirect_uri", value: Self.redirect),
                          URLQueryItem(name: "scope", value: scopes),
                          URLQueryItem(name: "state", value: oauthState),
                          URLQueryItem(name: "code_challenge_method", value: "S256"),
                          URLQueryItem(name: "code_challenge", value: challenge)]
        guard let loginURL = url.url else { status = "URL de Spotify inválida"; return }
        let session = ASWebAuthenticationSession(url: loginURL, callbackURLScheme: Self.callbackScheme) { [weak self] callbackURL, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.authentication = nil
                if let error = error { self.status = "Autorización cancelada: \(error.localizedDescription)"; return }
                guard let callbackURL = callbackURL,
                      let pieces = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      pieces.queryItems?.first(where: { $0.name == "state" })?.value == self.oauthState,
                      let code = pieces.queryItems?.first(where: { $0.name == "code" })?.value else {
                    self.status = "Autorización inválida (state o code)"
                    return
                }
                Task { @MainActor in
                    do {
                        let token = try await self.tokenExchange(["grant_type": "authorization_code", "code": code,
                                                                  "redirect_uri": Self.redirect, "client_id": id,
                                                                  "code_verifier": self.oauthVerifier], priorRefreshToken: nil)
                        self.status = "Spotify autorizado"
                        self.unavailableChecks = 0
                        self.playbackAvailability = "Spotify autorizado · comprobando"
                        self.record("Spotify autorizado; token vigente hasta \(Date(timeIntervalSince1970: token.expiresAt))")
                        await self.refreshPlaybackInfo()
                    } catch { self.failure(error) }
                }
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authentication = session
        if !session.start() { status = "No se pudo abrir Spotify" }
    }

    func disconnectSpotify() {
        skipNoActiveDeviceUntil = nil
        lastBlockedSkipProbeAt = nil
        MusicSyncEngine.shared.reset()
        pendingWatchCommands.removeAll()
        SecureTokenStorage.clear()
        lastDeviceID = nil
        lastIsPlaying = nil
        lastMusicSnapshot = nil
        unavailableChecks = 0
        playerUnavailableSince = nil
        retainedTrackWarningLogged = false
        manualResyncUntil = nil
        SpotifyAppRemoteBridge.shared.disable()
        // La desconexión voluntaria debe limpiar el panel aunque no haya
        // una respuesta de Spotify o el iPhone esté sin conexión a internet.
        controlEnabled = false
        UserDefaults.standard.set(false, forKey: "motowatch.spotify.enabled")
        sendIdle(reason: "Spotify desvinculado manualmente", force: true)
        playbackAvailability = "Spotify desvinculado"
        lastSong = "Sin canción"
        metadataSource = "Sin datos"
        status = "Sin autorizar"
        record("Spotify desvinculado")
    }

    // Botón diagnóstico: permite probar el comportamiento del firmware
    // sin necesitar cerrar Spotify de verdad. No modifica el token ni el player.
    func testNoMusicScreen() {
        manualIdlePreviewUntil = Date().addingTimeInterval(20)
        sendIdle(reason: "Prueba manual de pantalla sin música", force: true)
        playbackAvailability = "Prueba: mensaje de reposo enviado"
    }

    private func sendIdle(reason: String, force: Bool = false) {
        if idleModeRequested && !force { return }
        idleModeRequested = true
        WatchBLEManager.shared.sendNoMusic(reason: reason, force: force)
        record("Modo sin música solicitado: \(reason) (no confirmado por firmware)")
    }

    private func markAvailable(_ playback: SpotifyPlayback, force: Bool = false,
                               diagnosticSource: String = "Web API") {
        // El SDK/Web API vuelve a informar un dispositivo actual.
        // Rehabilitar los botones inmediatamente, sin esperar el cooldown.
        if playback.device != nil, skipNoActiveDeviceUntil != nil {
            skipNoActiveDeviceUntil = nil
            record("Spotify Connect: dispositivo activo recuperado; SIGUIENTE/ANTERIOR habilitados")
        }
        unavailableChecks = 0
        playerUnavailableSince = nil
        retainedTrackWarningLogged = false
        let wasIdle = idleModeRequested
        idleModeRequested = false
        let previousSnapshot = lastMusicSnapshot
        updateCachedPlayback(playback)
        if let snapshot = lastMusicSnapshot, playback.item != nil,
           previousSnapshot?.title != snapshot.title ||
           previousSnapshot?.artist != snapshot.artist ||
           previousSnapshot?.isPlaying != snapshot.isPlaying {
            WatchBLEManager.shared.record("SPOTIFY-ORIGEN",
                "WEB [\(diagnosticSource)]: pista nueva=\(snapshot.title) — \(snapshot.artist); estadoApp=\(UIApplication.shared.applicationState.rawValue)")
            WatchBLEManager.shared.flushLog()
        }
        if playback.item != nil {
            metadataSource = "Spotify Web API · respaldo"
        }
        if playback.item != nil {
            playbackAvailability = playback.is_playing ? "Reproduciendo" : "Pausado"
        } else {
            playbackAvailability = "Dispositivo disponible, sin canción identificada"
        }
        status = playback.is_playing ? "Spotify reproduciendo" : "Spotify pausado"
        if let snapshot = lastMusicSnapshot, playback.item != nil {
            let manualResync = consumeManualResyncRequest()
            MusicSyncEngine.shared.acceptFresh(snapshot,
                                               manual: manualResync || force,
                                               recoveredFromIdle: wasIdle)
        }
    }

    private func markNoActivePlayer(reason: String = "Spotify sin reproductor") {
        // HTTP 204 no diferencia una pausa prolongada de la pérdida temporal
        // del dispositivo Connect. Evitar borrar la última canción por ello.
        let now = Date()
        if playerUnavailableSince == nil { playerUnavailableSince = now }
        unavailableChecks += 1
        let elapsed = now.timeIntervalSince(playerUnavailableSince ?? now)
        switch SpotifyPlaybackContinuityPolicy.decide(
            unavailableSeconds: elapsed,
            hasLastTrack: lastMusicSnapshot != nil,
            graceSeconds: inactiveGraceSeconds
        ) {
        case .waiting:
            let seconds = max(0, Int(inactiveGraceSeconds - elapsed))
            playbackAvailability = "Sin reproductor · comprobando (\(seconds)s)"
            record("Spotify: \(reason), revisión \(unavailableChecks), faltan ~\(seconds)s")
        case .preserveLastTrack:
            // Conservar el título y estado ya mostrado en el reloj, pero sin
            // afirmar que Spotify continúa: desconocemos su estado actual.
            // La próxima orden Play/Pausa no debe usar un estado antiguo.
            playbackAvailability = "Reproductor no disponible · canción conservada"
            status = "Spotify sin dispositivo activo · esperando recuperación"
            metadataSource = "Últimos metadatos válidos (estado no confirmado)"
            lastDeviceID = nil
            lastIsPlaying = nil
            if !retainedTrackWarningLogged {
                retainedTrackWarningLogged = true
                record("Spotify: 204 prolongado; última canción conservada, sin paquete 24/01 vacío")
            }
        case .showIdle:
            // Sin una canción conocida sí podemos anunciar falta de música.
            // El usuario puede limpiar la pantalla manualmente o desvincular.
            playbackAvailability = "No se está reproduciendo música"
            status = "Spotify sin reproductor activo"
            lastDeviceID = nil
            lastIsPlaying = nil
            metadataSource = "Sin reproductor confirmado"
            sendIdle(reason: "Sin reproductor ni canción previa después de 30 segundos")
        }
    }

    // Una resincronización manual exige un estado NUEVO de Spotify; nunca
    // reenviamos la última pista en caché sin verificarla. El pedido expira
    // para que una consulta futura no provoque un reanuncio inesperado.
    func resyncWatchMusicManually() {
        guard controlEnabled, WatchBLEManager.shared.isConnected else {
            lastAction = "Resincronización: se requieren controles Spotify y reloj conectado"
            record("MUSICA-DIAG: sin envío, controles o Bluetooth no disponibles")
            return
        }
        manualResyncUntil = Date().addingTimeInterval(20)
        MusicSyncEngine.shared.cancelAutomaticVerificationForManualResync()
        WatchBLEManager.shared.captureNextMusicFrames()
        lastAction = "Resincronización: consultando canción actual"
        record("MUSICA-DIAG: solicitando estado fresco; reanuncio forzado si Spotify responde")
        forceWatchMusicRecovery()
    }

    private func consumeManualResyncRequest() -> Bool {
        guard let expiry = manualResyncUntil else { return false }
        manualResyncUntil = nil
        return Date() <= expiry
    }

    // Consultar el reproductor ACTUAL antes de reenviar el título anterior.
    // El cache puede representar una canción vieja tras una desconexión.
    func forceWatchMusicRecovery() {
        guard controlEnabled else { return }
        if SpotifyAppRemoteBridge.shared.isConnected {
            SpotifyAppRemoteBridge.shared.requestCurrentPlayerState(fallbackToWeb: true)
        }
        if !SpotifyAppRemoteBridge.shared.isConnected {
            Task { await refreshPlaybackInfo(force: true) }
        }
        record("Recuperación musical: SDK prioritario, Web API de respaldo")
    }

    // Verificar la canción también en Salud, Inicio y Notificaciones.
    // No se ejecuta en suspensión; iOS decide qué eventos BLE despiertan la app.
    func verifyCurrentMetadataForWatch() async {
        guard UIApplication.shared.applicationState == .active,
              controlEnabled, WatchBLEManager.shared.isConnected else { return }
        if SpotifyAppRemoteBridge.shared.isConnected {
            if !SpotifyAppRemoteBridge.shared.nativeMetadataIsFresh {
                SpotifyAppRemoteBridge.shared.requestCurrentPlayerState(fallbackToWeb: false)
                await refreshPlaybackInfo(allowSDKFallback: true)
            }
        } else {
            await refreshPlaybackInfo()
        }
    }

    func recoverAfterWatchReady() async {
        guard controlEnabled, !recoveryInProgress else { return }
        MusicSyncEngine.shared.requestReconnectRecovery()
        recoveryInProgress = true
        defer { recoveryInProgress = false }
        // NO transmitir la canción antigua desde lastMusicSnapshot a ciegas:
        // Spotify pudo seguir reproduciendo y cambiar de pista sin que iOS nos
        // permitiera consultar la Web API durante la desconexión.
        record("Reloj reconectado: verificando canción actual de Spotify")
        if SpotifyAppRemoteBridge.shared.isConnected {
            SpotifyAppRemoteBridge.shared.requestCurrentPlayerState(fallbackToWeb: true)
        }
        // Si el SDK está conectado, su estado es la fuente principal.
        // No competir con un GET Web que puede llegar tarde y pisar los metadatos.
        if !SpotifyAppRemoteBridge.shared.isConnected {
            await refreshPlaybackInfo(force: true)
        }
    }

    // Recibe eventos de App Remote sólo en primer plano. Al bloquear el iPhone
    // continúa vigente nuestro mecanismo Web API + CoreBluetooth.
    func receiveAppRemoteState(uri: String, title: String, artist: String,
                               album: String, durationMs: Int, progressMs: Int,
                               isPlaying: Bool) {
        guard controlEnabled else { return }
        guard !title.isEmpty else { return }
        if skipNoActiveDeviceUntil != nil {
            skipNoActiveDeviceUntil = nil
            record("Spotify SDK: estado musical nativo recuperado; controles habilitados")
        }
        unavailableChecks = 0
        playerUnavailableSince = nil
        retainedTrackWarningLogged = false
        let wasIdle = idleModeRequested
        idleModeRequested = false
        let previousSnapshot = lastMusicSnapshot
        let snapshot = WatchMusicSnapshot(
            id: uri, title: title, artist: artist, album: album,
            durationMs: durationMs, progressMs: progressMs, isPlaying: isPlaying
        )
        sdkMetadataRevision &+= 1
        if previousSnapshot?.title != snapshot.title ||
           previousSnapshot?.artist != snapshot.artist ||
           previousSnapshot?.isPlaying != snapshot.isPlaying {
            WatchBLEManager.shared.record("SPOTIFY-ORIGEN",
                "SDK playerStateDidChange: pista nueva=\(snapshot.title) — \(snapshot.artist); estadoApp=\(UIApplication.shared.applicationState.rawValue); remotoConectado=\(SpotifyAppRemoteBridge.shared.isConnected)")
            WatchBLEManager.shared.flushLog()
        }
        lastMusicSnapshot = snapshot
        lastIsPlaying = isPlaying
        lastSong = title
        metadataSource = "Spotify iOS SDK · App Remote"
        status = isPlaying ? "Spotify App Remote · reproduciendo" : "Spotify App Remote · pausado"
        playbackAvailability = isPlaying ? "Reproduciendo (SDK)" : "Pausado (SDK)"
        let manualResync = consumeManualResyncRequest()
        MusicSyncEngine.shared.acceptFresh(snapshot,
                                           manual: manualResync,
                                           recoveredFromIdle: wasIdle)
    }

    // Diagnóstico opt-in independiente de refreshPlaybackInfo:
    // este GET no puede ser omitido porque el SDK haya informado una pista
    // recién antes del bloqueo. La Web API no se vuelve una tarea periódica:
    // MusicBackgroundExperiment lo invoca solo durante la ventana finita de iOS
    // o ante una notificación Bluetooth REAL y permitida.
    @MainActor
    func probeWebPlaybackWhileBackgrounded() async -> String {
        guard UIApplication.shared.applicationState == .background else {
            return "OMITIDA: iWatch ya no está en segundo plano"
        }
        guard controlEnabled else {
            return "OMITIDA: controles Spotify desactivados"
        }
        guard SecureTokenStorage.load() != nil else {
            return "OMITIDA: Spotify Web API sin autorización guardada"
        }
        let epochAtStart = controlEpoch
        let nativeRevisionAtStart = sdkMetadataRevision
        let started = Date()
        record("BG-HTTP: GET /me/player iniciado (Web API real; no depende del caché SDK)")
        do {
            // HTTP 204 representa ausencia de player, no una canción vacía
            // ni autorización para borrar la pantalla del reloj.
            let playback = try await fetchPlayback()
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            let sdkChanged = sdkMetadataRevision != nativeRevisionAtStart
            guard SpotifyBackgroundProbePolicy.shouldApplyHTTPResult(
                inBackground: UIApplication.shared.applicationState == .background,
                enabled: controlEnabled,
                cancelled: Task.isCancelled,
                startedEpoch: epochAtStart,
                currentEpoch: controlEpoch,
                startedNativeRevision: nativeRevisionAtStart,
                currentNativeRevision: sdkMetadataRevision
            ) else {
                return sdkChanged
                    ? "HTTP respondió en \(elapsed) ms, descartado: llegó estado SDK más nuevo"
                    : "HTTP respondió en \(elapsed) ms, descartado por salida/cancelación/cambio de sesión"
            }
            guard let playback else {
                return "GET /me/player HTTP 204 confirmado en \(elapsed) ms; última canción conservada"
            }
            guard playback.device != nil || playback.item != nil else {
                return "GET /me/player HTTP 200 sin pista/dispositivo en \(elapsed) ms; metadatos conservados"
            }
            let previousTitle = lastMusicSnapshot?.title
            let previousArtist = lastMusicSnapshot?.artist
            let previousPlaying = lastIsPlaying
            markAvailable(playback, diagnosticSource: "BG-HTTP")
            // Los metadatos sólo se reenvían si MusicSyncEngine detecta un
            // cambio confirmado. Este log no afirma que la pantalla lo muestre.
            let newTitle = lastMusicSnapshot?.title ?? "sin título"
            let newArtist = lastMusicSnapshot?.artist ?? "sin artista"
            let changed = previousTitle != newTitle || previousArtist != newArtist
                || previousPlaying != playback.is_playing
            return "GET /me/player HTTP 200 en \(elapsed) ms; cambio=\(changed ? "sí" : "no"); pista=\(newTitle) — \(newArtist); pantalla no verificada"
        } catch {
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            if let spotifyError = error as? SpotifyBridgeError,
               case let .response(code, _) = spotifyError {
                return "GET /me/player HTTP \(code) en \(elapsed) ms; se conservan metadatos"
            }
            return "GET /me/player sin respuesta HTTP válida tras \(elapsed) ms: \(error.localizedDescription)"
        }
    }

    func refreshPlaybackInfo(force: Bool = false, allowSDKFallback: Bool = false) async {
        guard controlEnabled else { return }
        if !force, let until = manualIdlePreviewUntil, Date() < until { return }
        // No consumir cooldown Web cuando el SDK sí está aportando datos vigentes.
        if SpotifyAppRemoteBridge.shared.nativeMetadataIsFresh && !allowSDKFallback { return }
        let now = Date()
        guard SpotifyMetadataRefreshPolicy.shouldStart(
            inFlight: playbackRefreshInProgress, forced: force,
            lastAutomaticAt: lastAutomaticWebRefreshAt, now: now
        ) else { return }
        if !force { lastAutomaticWebRefreshAt = now }
        playbackRefreshInProgress = true
        defer { playbackRefreshInProgress = false }
        let epochAtStart = controlEpoch
        if force { manualIdlePreviewUntil = nil }
        // Un GET Web lento no puede reemplazar una canción SDK posterior.
        // Si el dato nativo está vencido se permite este respaldo HTTP.
        let nativeRevisionAtStart = sdkMetadataRevision
        guard SecureTokenStorage.load() != nil else {
            if !SpotifyAppRemoteBridge.shared.isConnected {
                playbackAvailability = "Spotify sin autorizar"
            }
            return
        }
        do {
            let playback = try await fetchPlayback()
            guard controlEnabled && controlEpoch == epochAtStart else { return }
            // Un callback App Remote llegó mientras esperaba HTTP: sus metadatos
            // son más recientes que la respuesta Web y tienen prioridad.
            if sdkMetadataRevision != nativeRevisionAtStart { return }
            if SpotifyAppRemoteBridge.shared.nativeMetadataIsFresh && !allowSDKFallback { return }
            if let playback = playback {
                // Una pista pausada sin dispositivo Connect sigue siendo válida.
                if playback.device != nil || playback.item != nil {
                    markAvailable(playback, force: force)
                } else {
                    markNoActivePlayer()
                }
            } else {
                markNoActivePlayer()
            }
        } catch {
            guard controlEnabled && controlEpoch == epochAtStart else { return }
            if sdkMetadataRevision != nativeRevisionAtStart { return }
            if SpotifyAppRemoteBridge.shared.nativeMetadataIsFresh && !allowSDKFallback { return }
            // No ocultar la música por fallos temporales de red o HTTP 429.
            playbackAvailability = "Consulta fallida; estado conservado"
            if let spotifyError = error as? SpotifyBridgeError,
               case let .response(code, body) = spotifyError {
                if code == 401 || (code == 400 && body.contains("invalid_grant")) {
                    playbackAvailability = "Spotify rechazó la autorización"
                    sendIdle(reason: "Sesión Spotify inválida")
                } else if code == 404 &&
                          (body.localizedCaseInsensitiveContains("device not found") ||
                           body.contains("NO_ACTIVE_DEVICE")) {
                    // Un identificador viejo no debe conservarse. Verificar de nuevo
                    // sin convertir una caída de red en desconexión.
                    lastDeviceID = nil
                    // El 404 de la Web API no es prueba de que Spotify haya
                    // detenido el audio en el iPhone (comprobado en pruebas).
                    // No iniciar cuenta atrás de 30 s para borrar la canción.
                    playerUnavailableSince = nil
                    unavailableChecks = 0
                    playbackAvailability = "Spotify 404 temporal · conservando música"
                    lastAction = "Web API sin dispositivo; esperando nuevo estado válido"
                    record("Spotify: HTTP 404 al consultar; no se borra la música")
                    return
                }
            }
            failure(error)
        }
    }

    private func protectAgainstNoActiveDevice404() {
        skipNoActiveDeviceUntil = Date().addingTimeInterval(
            SpotifyCommandQueuePolicy.noActiveDeviceCooldownSeconds)
        // Órdenes antiguas en cola no deben saltar canciones cuando el
        // dispositivo reaparezca: exigen una pulsación nueva y explícita.
        let removed = pendingWatchCommands.count
        pendingWatchCommands.removeAll()
        lastDeviceID = nil
        lastIsPlaying = nil
        if removed > 0 {
            record("Spotify: descartadas \(removed) órdenes pendientes tras 404 sin dispositivo")
        }
        lastAction = "Spotify Connect sin dispositivo · abrí Spotify y reproducí una canción"
        playbackAvailability = "Spotify 404 · sin dispositivo activo · música conservada"
        record("Spotify: HTTP 404 NO_ACTIVE_DEVICE; pausando NEXT/PREV 20 s, sin borrar metadatos")
    }

    func receive(_ command: WatchCommand) {
        switch command {
        case .next, .previous, .toggle: break
        case .findStart, .findStop, .unknown: return
        }
        guard controlEnabled else { record("Spotify deshabilitado; comando sin ejecutar"); return }
        let now = Date()
        let key = command.rawValue
        let limit = command == .toggle ? 1.5 : 0.65
        if let prior = lastCommandTimes[key], now.timeIntervalSince(prior) < limit { return }
        lastCommandTimes[key] = now
        if command != .toggle &&
           SpotifyCommandQueuePolicy.shouldHoldSkip(until: skipNoActiveDeviceUntil, now: now) {
            lastAction = "Spotify Connect sin dispositivo · comprobando si volvió"
            // Esta pulsación es NUEVA: un solo GET seguro, limitado y sin
            // mandar NEXT/ANTERIOR si no hay un dispositivo ACTIVO confirmado.
            probeBlockedSkipFromFreshTap(command, receivedAt: now)
            if now.timeIntervalSince(lastBlockedSkipLoggedAt) >= 5 {
                record("Spotify: SIGUIENTE/ANTERIOR retenido por 404; comprobación controlada si iOS lo permite")
                lastBlockedSkipLoggedAt = now
            }
            return
        }
        if requestBusy {
            enqueuePendingWatchCommand(command, receivedAt: now)
            return
        }
        performWatchCommand(command)
    }

    // El usuario puede despertar la app con un botón BLE cuando Spotify Connect
    // ya volvió; el cooldown de 404 no debe descartar esa pulsación recién hecha.
    // Una sola consulta GET con un límite de 4 s entre verificaciones, y solo
    // ejecutar el botón si el dispositivo ACTIVO y su antigüedad están confirmados.
    private func probeBlockedSkipFromFreshTap(_ command: WatchCommand, receivedAt: Date) {
        let now = Date()
        guard SpotifyCommandQueuePolicy.shouldProbeBlockedSkip(
            until: skipNoActiveDeviceUntil, lastProbeAt: lastBlockedSkipProbeAt,
            now: now, requestBusy: requestBusy, probeBusy: blockedSkipProbeInProgress
        ) else { return }
        lastBlockedSkipProbeAt = now
        blockedSkipProbeInProgress = true
        let epoch = controlEpoch
        Task { @MainActor in
            let bgTask: UIBackgroundTaskIdentifier = UIApplication.shared.applicationState == .background
                ? UIApplication.shared.beginBackgroundTask(
                    withName: "MotoWatchSpotifyConnectRecheck", expirationHandler: nil)
                : .invalid
            defer {
                self.blockedSkipProbeInProgress = false
                if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
            }
            do {
                let playback = try await self.fetchPlayback()
                guard self.controlEnabled, self.controlEpoch == epoch,
                      WatchBLEManager.shared.isConnected else { return }
                guard SpotifyCommandQueuePolicy.isFresh(
                    receivedAt: receivedAt, now: Date()
                ) else {
                    self.record("Spotify: verificación 404 tardía; pulsación vencida, NO enviada")
                    return
                }
                guard let playback = playback, playback.device?.id != nil else {
                    self.record("Spotify: verificación 404: iPhone aún sin dispositivo activo; botón NO enviado")
                    return
                }
                self.markAvailable(playback)
                self.record("Spotify: dispositivo recuperado por pulsación BLE reciente; reactivando controles")
                if self.requestBusy {
                    self.enqueuePendingWatchCommand(command, receivedAt: receivedAt)
                } else {
                    self.performWatchCommand(command)
                }
            } catch {
                self.record("Spotify: verificación 404 sin respuesta válida; controles protegidos: \(error.localizedDescription)")
            }
        }
    }

    private func enqueuePendingWatchCommand(_ command: WatchCommand, receivedAt: Date) {
        pendingWatchCommands.removeAll {
            !SpotifyCommandQueuePolicy.isFresh(receivedAt: $0.receivedAt, now: receivedAt)
        }
        // Dos toques Play/Pausa encolados mientras Spotify responde con lentitud
        // pueden pausar y reanudar de manera inesperada. Exigir una acción nueva
        // cuando termine el comando anterior, en lugar de acumular toggles.
        if command == .toggle && pendingWatchCommands.contains(where: { $0.command == .toggle }) {
            record("[SPOTIFY] PLAY/PAUSA repetido en cola: descartado para evitar alternancia inesperada")
            return
        }
        guard pendingWatchCommands.count < SpotifyCommandQueuePolicy.maxPending else {
            lastAction = "Cola Spotify llena: \(command.rawValue) descartado"
            record("[SPOTIFY] Cola llena: \(command.rawValue) descartado explícitamente")
            return
        }
        pendingWatchCommands.append(PendingWatchCommand(command: command, receivedAt: receivedAt))
        lastAction = "Spotify ocupado · \(command.rawValue) en espera"
        record("[SPOTIFY] Encolado: \(command.rawValue), vence a los 6 s")
    }

    private func dispatchPendingWatchCommand() {
        guard controlEnabled, WatchBLEManager.shared.isConnected else {
            if !pendingWatchCommands.isEmpty {
                record("[SPOTIFY] Pendientes cancelados: controles o Bluetooth no disponibles")
                pendingWatchCommands.removeAll()
            }
            return
        }
        let now = Date()
        while !pendingWatchCommands.isEmpty {
            let pending = pendingWatchCommands.removeFirst()
            guard SpotifyCommandQueuePolicy.isFresh(receivedAt: pending.receivedAt, now: now) else {
                record("[SPOTIFY] Pendiente vencido: \(pending.command.rawValue); no se ejecuta tarde")
                continue
            }
            if pending.command != .toggle &&
               SpotifyCommandQueuePolicy.shouldHoldSkip(until: skipNoActiveDeviceUntil, now: now) {
                record("[SPOTIFY] Pendiente descartado: Spotify Connect sin dispositivo activo")
                continue
            }
            record("[SPOTIFY] Ejecutando pulsación pendiente: \(pending.command.rawValue)")
            performWatchCommand(pending.command)
            return
        }
    }

    private func performWatchCommand(_ command: WatchCommand) {
        requestBusy = true
        let key = command.rawValue
        lastAction = "Procesando \(key)"
        Task { @MainActor in
            // El evento BLE puede despertar la app con iOS bloqueado. Solicitamos
            // tiempo breve adicional para terminar la petición HTTP, sin garantizarlo.
            let backgroundTask: UIBackgroundTaskIdentifier = UIApplication.shared.applicationState == .background
                ? UIApplication.shared.beginBackgroundTask(withName: "MotoWatchSpotify", expirationHandler: nil)
                : .invalid
            defer {
                self.requestBusy = false
                if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
                self.dispatchPendingWatchCommand()
            }
            do {
                // App Remote (iOS) es prioritario si tenemos sesión real activa.
                // En segundo plano, App Remote se desconecta por diseño:
                // los eventos BLE usarán la Web API como hasta ahora.
                switch await SpotifyAppRemoteBridge.shared.sendWatchCommand(command) {
                case .succeeded:
                    self.lastAction = "Comando enviado con Spotify iOS SDK"
                    self.record("[SPOTIFY] Comando \(key) por SDK nativo")
                    return
                case .failed(let message):
                    // No repetir automáticamente un comando potencialmente aplicado.
                    self.lastAction = "SDK rechazó el comando: \(message)"
                    self.record("[SPOTIFY] SDK falló; sin reenvío duplicado")
                    return
                case .unavailable:
                    self.record("[SPOTIFY] SDK no disponible; usando Web API")
                }
                try await self.run(command)
            } catch {
                if let spotifyError = error as? SpotifyBridgeError,
                   case let .response(code, body) = spotifyError,
                   SpotifyCommandQueuePolicy.isMissingPlayerCommandResponse(status: code) {
                    // Un 404 genérico como {"message":"Not found."} durante
                    // PAUSA es también compatible con perder el dispositivo
                    // Spotify Connect. Nunca reenviar a ciegas el comando.
                    self.record("Spotify: comando \(key) recibió HTTP \(code) (\(body.prefix(65))); comprobando Connect")
                    self.protectAgainstNoActiveDevice404()
                    // Un 404 al mandar un comando NO prueba que la música paró:
                    // el audio puede seguir sonando en el iPhone. No activar
                    // modo sin música hasta confirmar el reproductor por GET.
                    self.record("Spotify: HTTP 404 en comando; comprobando reproductor sin descartar música")
                    await self.refreshPlaybackInfo(force: true)
                    return
                }
                if let spotifyError = error as? SpotifyBridgeError,
                   case let .response(code, _) = spotifyError,
                   SpotifyCommandQueuePolicy.isTransientHTTP(code) {
                    // Una orden Next/Prev/Toggle podría haberse aplicado pese a
                    // recibir 5xx o 429. Nunca reenviar a ciegas: doble salto.
                    self.status = "Spotify temporalmente no disponible"
                    self.playbackAvailability = "Error temporal de Spotify · metadatos conservados"
                    self.lastAction = "HTTP \(code) en \(key) · sin reintento automático"
                    self.record("[SPOTIFY] HTTP \(code) en \(key); sin reintento automático")
                    return
                }
                self.failure(error)
            }
        }
    }

    // Solo para órdenes que no pudo gestionar el SDK. No llamar desde ambas vías.
    private func run(_ command: WatchCommand) async throws {
        var action: String
        var currentPlayback: SpotifyPlayback?
        switch command {
        case .next: action = "next"
        case .previous: action = "previous"
        case .toggle:
            // Consultamos el estado de Spotify antes de decidir Play o Pausa.
            // En pausa prolongada /me/player puede responder 204 (sin player).
            currentPlayback = try await fetchPlayback()
            if let playing = currentPlayback {
                updateCachedPlayback(playing)
            } else {
                // Si Spotify ya no tiene reproductor activo, solo es razonable
                // intentar PLAY, nunca una pausa basada en datos viejos.
                lastIsPlaying = false
            }
            action = (lastIsPlaying == true) ? "pause" : "play"
        case .findStart, .findStop, .unknown: return
        }

        // La Web API usa el dispositivo activo, nunca un ID viejo de cache.
        // Si no queda dispositivo activo, buscamos UN iPhone disponible antes
        // de rendirnos. No transferir a otro teléfono ni a parlantes por error.
        if action == "play" {
            if currentPlayback?.device == nil {
                guard let target = try await findUnambiguousIPhone() else {
                    lastAction = "Spotify sin dispositivo iPhone disponible; abrí Spotify una vez"
                    playbackAvailability = "Spotify suspendido · sin dispositivo Connect activo"
                    record("[SPOTIFY] Web API sin iPhone disponible; no se fabricó reproducción")
                    return
                }
                // Transferir con play=true es un único comando de reanudación.
                // No enviar inmediatamente otro PUT /play: Spotify no garantiza
                // el orden de las operaciones de control de dispositivos.
                let body = try JSONSerialization.data(withJSONObject:
                    ["device_ids": [target], "play": true])
                _ = try await api("/me/player", method: "PUT", body: body)
                lastIsPlaying = true
                lastAction = "Spotify Connect: intentando reanudar en iPhone"
                record("[SPOTIFY] Transferencia PLAY hacia iPhone disponible")
                await refreshPlaybackInfo(force: true)
                return
            }
        }
        let method = (action == "next" || action == "previous") ? "POST" : "PUT"
        _ = try await api("/me/player/\(action)", method: method)
        if action == "play" { lastIsPlaying = true }
        if action == "pause" { lastIsPlaying = false }
        if action == "play" || action == "pause", var snapshot = lastMusicSnapshot {
            snapshot.isPlaying = action == "play"
            lastMusicSnapshot = snapshot
            WatchBLEManager.shared.sendMusic(snapshot)
        }
        lastAction = "Web API: \(action.uppercased()) enviado"
        record("[SPOTIFY] Web API \(action.uppercased()) enviado")
        try? await Task.sleep(nanoseconds: 850_000_000)
        await refreshPlaybackInfo()
        if UIApplication.shared.applicationState == .active && (action == "next" || action == "previous") {
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            await refreshPlaybackInfo()
        }
    }

    private func findUnambiguousIPhone() async throws -> String? {
        let data = try await api("/me/player/devices", method: "GET")
        let candidates = try JSONDecoder().decode(SpotifyConnectDevices.self, from: data)
            .devices.filter { $0.is_restricted == false && $0.id != nil }
        let phones = candidates.filter {
            $0.type.localizedCaseInsensitiveCompare("Smartphone") == .orderedSame &&
            $0.name.localizedCaseInsensitiveContains("iPhone")
        }
        // Evitar elegir un dispositivo equivocado si hay más de un iPhone.
        guard phones.count == 1 else { return nil }
        return phones[0].id
    }

    private func updateCachedPlayback(_ playback: SpotifyPlayback) {
        if let id = playback.device?.id { lastDeviceID = id }
        lastIsPlaying = playback.is_playing
        if let song = playback.item {
            lastSong = song.name
            let artists = (song.artists ?? []).map { $0.name }.joined(separator: ", ")
            lastMusicSnapshot = WatchMusicSnapshot(
                id: song.id ?? song.name,
                title: song.name,
                artist: artists.isEmpty ? "Spotify" : artists,
                album: song.album?.name ?? "Spotify",
                durationMs: song.duration_ms ?? 0,
                progressMs: playback.progress_ms ?? 0,
                isPlaying: playback.is_playing
            )
        } else if var snapshot = lastMusicSnapshot {
            snapshot.isPlaying = playback.is_playing
            lastMusicSnapshot = snapshot
        }
    }

    private func fetchPlayback() async throws -> SpotifyPlayback? {
        let result = try await api("/me/player", method: "GET")
        guard !result.isEmpty else { return nil }
        return try JSONDecoder().decode(SpotifyPlayback.self, from: result)
    }

    private func api(_ path: String, method: String, body: Data? = nil) async throws -> Data {
        let token = try await validAccessToken()
        guard let url = URL(string: "https://api.spotify.com/v1\(path)") else { throw SpotifyBridgeError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw SpotifyBridgeError.response(statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func validAccessToken() async throws -> String {
        guard let token = SecureTokenStorage.load() else { throw SpotifyBridgeError.unauthorized }
        if Date().timeIntervalSince1970 < token.expiresAt - 60 { return token.accessToken }
        guard !token.refreshToken.isEmpty else { throw SpotifyBridgeError.sessionExpired }
        let renewed = try await tokenExchange(["grant_type": "refresh_token", "refresh_token": token.refreshToken,
                                               "client_id": clientID.trimmingCharacters(in: .whitespacesAndNewlines)],
                                              priorRefreshToken: token.refreshToken)
        return renewed.accessToken
    }

    @discardableResult
    private func tokenExchange(_ form: [String: String], priorRefreshToken: String?) async throws -> SpotifyCredentials {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { key, value in
            "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
        }.sorted().joined(separator: "&").data(using: .utf8)
        request.timeoutInterval = 12
        let (body, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw SpotifyBridgeError.response(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
        let reply = try JSONDecoder().decode(OAuthReply.self, from: body)
        let stored = SpotifyCredentials(accessToken: reply.access_token,
                                        refreshToken: reply.refresh_token ?? priorRefreshToken ?? "",
                                        expiresAt: Date().timeIntervalSince1970 + Double(reply.expires_in))
        SecureTokenStorage.save(stored)
        return stored
    }

    private func failure(_ error: Error) {
        lastAction = "Error: \(error.localizedDescription)"
        status = "Error Spotify"
        record("[SPOTIFY] \(error.localizedDescription)")
    }

    private func record(_ message: String) {
        WatchBLEManager.shared.record("SPOTIFY", message)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var urlFormEncoded: String {
        // La URL codifica cada byte; los espacios de los formularios pasan a %20, válidos para OAuth.
        addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? self
    }
}
