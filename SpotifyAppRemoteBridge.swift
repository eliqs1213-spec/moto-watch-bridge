import Foundation
import Combine
import UIKit
import Security
import SpotifyiOS

// Motor prioritario de Spotify cuando la sesión App Remote está realmente activa.
// El SDK NO puede mantenerse conectado al suspenderse Spotify/iWatch; la Web API
// conserva el respaldo cuando el iPhone está bloqueado.
final class SpotifyAppRemoteBridge: NSObject, ObservableObject,
    SPTSessionManagerDelegate, SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {

    static let shared = SpotifyAppRemoteBridge()

    @Published private(set) var status = "SDK · esperando conexión"
    @Published private(set) var isConnected = false
    // Permite recurrir a Web API si falla la suscripción de eventos del SDK.
    @Published private(set) var metadataEventsActive = false
    @Published private(set) var hasNativeMetadata = false
    @Published private(set) var lastNativeEvent = "Sin evento nativo todavía"
    @Published private(set) var enabled = false

    private var sessionManager: SPTSessionManager?
    private var appRemote: SPTAppRemote?
    private var authorizing = false

    // Distinguir entre SDK no disponible y comando enviado con resultado incierto.
    // Un salto NEXT/PREV no se repite por Web si el SDK ya lo intentó.
    enum CommandResult {
        case unavailable
        case succeeded
        case failed(String)
    }

    private static let enabledKey = "motowatch.spotify.sdk.enabled"
    private static let keychainService = "org.motowatchbridge.spotify.appremote"
    private static let keychainAccount = "sdk-session"

    private override init() {
        super.init()
        // Una reinstalación/relanzamiento no debe cambiar silenciosamente a Web API.
        // La sesión del SDK se conserva exclusivamente en Keychain (nunca en UserDefaults).
        if UserDefaults.standard.bool(forKey: Self.enabledKey) {
            let id = UserDefaults.standard.string(forKey: "motowatch.spotify.clientid") ?? ""
            if !restoreAuthorizedSession(clientID: id) {
                status = "SDK: sesión no recuperable · tocá Activar SDK Spotify"
            }
        }
    }

    private static func saveSession(_ session: SPTSession) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: session, requiringSecureCoding: true) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecAttrAccount as String: keychainAccount]
        SecItemDelete(query as CFDictionary)
        var values = query
        values[kSecValueData as String] = data
        values[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(values as CFDictionary, nil)
    }

    private static func storedSession() -> SPTSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecAttrAccount as String: keychainAccount,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: SPTSession.self, from: data)
    }

    private static func clearSession() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecAttrAccount as String: keychainAccount]
        SecItemDelete(query as CFDictionary)
    }

    @discardableResult
    private func restoreAuthorizedSession(clientID: String) -> Bool {
        guard clientID.count == 32, clientID.allSatisfy({ $0.isHexDigit }),
              let url = URL(string: SpotifyBridge.redirect),
              let session = Self.storedSession() else { return false }
        let config = SPTConfiguration(clientID: clientID, redirectURL: url)
        let remote = SPTAppRemote(configuration: config, logLevel: .debug)
        remote.delegate = self
        let manager = SPTSessionManager(configuration: config, delegate: self)
        manager.session = session
        self.appRemote = remote
        self.sessionManager = manager
        enabled = true
        if session.isExpired {
            status = "SDK: renovando sesión guardada"
            manager.renewSession()
        } else {
            remote.connectionParameters.accessToken = session.accessToken
            status = "SDK: sesión recuperada · conectando"
            if UIApplication.shared.applicationState == .active { remote.connect() }
        }
        return true
    }

    // Debe ser una acción voluntaria: OAuth del SDK no sustituye el flujo
    // PKCE existente. Configurar en Spotify Developer Dashboard el mismo
    // Client ID, Redirect URI y aplicación iOS.
    func authorize(clientID: String) {
        guard clientID.count == 32, clientID.allSatisfy({ $0.isHexDigit }),
              let callbackURL = URL(string: SpotifyBridge.redirect) else {
            status = "Primero ingresá un Spotify Client ID válido"
            return
        }
        guard UIApplication.shared.canOpenURL(URL(string: "spotify://")!) else {
            status = "Instalá y abrí Spotify en el iPhone para utilizar App Remote"
            return
        }
        let config = SPTConfiguration(clientID: clientID, redirectURL: callbackURL)
        let remote = SPTAppRemote(configuration: config, logLevel: .debug)
        remote.delegate = self
        appRemote = remote
        sessionManager = SPTSessionManager(configuration: config, delegate: self)
        enabled = true
        UserDefaults.standard.set(clientID, forKey: "motowatch.spotify.clientid")
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        authorizing = true
        status = "Esperando autorización del SDK de Spotify..."
        // Solicita app-remote-control, sin iniciar música artificialmente.
        sessionManager?.initiateSession(with: [.appRemoteControl], options: .clientOnly, campaign: nil)
    }

    func handleOpenURL(_ url: URL) {
        guard authorizing, url.scheme?.lowercased() == SpotifyBridge.callbackScheme else { return }
        _ = sessionManager?.application(UIApplication.shared, open: url, options: [:])
    }

    func disable() {
        authorizing = false
        enabled = false
        appRemote?.disconnect()
        appRemote = nil
        sessionManager = nil
        isConnected = false
        metadataEventsActive = false
        hasNativeMetadata = false
        lastNativeEvent = "SDK desactivado"
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        Self.clearSession()
        status = "SDK desactivado; Web API sigue disponible"
    }

    func applicationDidEnterBackground() {
        // Recomendación del SDK oficial: cerrar su sesión cuando pasamos a fondo.
        // No afecta el CoreBluetooth que mantiene conectado al reloj.
        appRemote?.disconnect()
        isConnected = false
        metadataEventsActive = false
        hasNativeMetadata = false
        if enabled { status = "SDK en reposo · Web API activa en segundo plano" }
    }

    func applicationDidBecomeActive() {
        // Reconectar únicamente si el usuario habilitó App Remote y se conserva
        // un token de la sesión del SDK; no disparar OAuth en segundo plano.
        guard enabled else { return }
        guard let remote = appRemote else {
            status = "SDK sin sesión · tocá Activar SDK Spotify"
            return
        }
        if remote.isConnected {
            requestCurrentPlayerState(fallbackToWeb: true)
            return
        }
        guard remote.connectionParameters.accessToken != nil else {
            status = "SDK sin token · tocá Activar SDK Spotify"
            return
        }
        status = "SDK reconectando con Spotify..."
        remote.connect()
    }

    // MARK: SPTSessionManagerDelegate

    func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        authorizing = false
        guard enabled, let remote = appRemote else { return }
        Self.saveSession(session)
        remote.connectionParameters.accessToken = session.accessToken
        status = "SDK autorizado · conectando con Spotify"
        remote.connect()
    }

    func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
        guard enabled, let remote = appRemote else { return }
        Self.saveSession(session)
        remote.connectionParameters.accessToken = session.accessToken
        if UIApplication.shared.applicationState == .active { remote.connect() }
    }

    func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        authorizing = false
        status = "Autorización SDK fallida: \(error.localizedDescription)"
    }

    // MARK: SPTAppRemoteDelegate

    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        isConnected = true
        metadataEventsActive = false
        hasNativeMetadata = false
        status = "SDK conectado · activando eventos de Spotify"
        appRemote.playerAPI?.delegate = self
        // Lectura inicial sin esperar a que Spotify cambie de canción.
        requestCurrentPlayerState(fallbackToWeb: true)
        appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] result, error in
            if let error = error {
                self?.metadataEventsActive = false
                self?.status = "SDK sin eventos: \(error.localizedDescription) · Web API de respaldo"
                Task { @MainActor in
                    await SpotifyBridge.shared.refreshPlaybackInfo(force: true, allowSDKFallback: true)
                }
            } else {
                self?.metadataEventsActive = true
                self?.status = "SDK conectado · eventos de Spotify activos"
                if let state = result as? SPTAppRemotePlayerState {
                    self?.playerStateDidChange(state)
                }
            }
        })
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        isConnected = false
        metadataEventsActive = false
        hasNativeMetadata = false
        status = "SDK sin conexión: \(error?.localizedDescription ?? "Spotify no disponible")"
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        isConnected = false
        metadataEventsActive = false
        hasNativeMetadata = false
        status = "SDK desconectado · controles Web API disponibles"
    }

    // Comandos oficiales del Spotify iOS SDK. Deben invocarse en el hilo principal.
    // No intentamos reabrir Spotify silenciosamente: iOS podría haberlo suspendido.
    @MainActor
    func sendWatchCommand(_ command: WatchCommand) async -> CommandResult {
        guard enabled, isConnected,
              UIApplication.shared.applicationState == .active,
              let playerAPI = appRemote?.playerAPI else { return .unavailable }

        // Obtener estado ACTUAL para el toggle; nunca alternar en base a un cache
        // que puede haber quedado viejo mientras Spotify estuvo suspendido.
        if command == .toggle {
            let state: SPTAppRemotePlayerState? = await withCheckedContinuation { continuation in
                playerAPI.getPlayerState { result, error in
                    continuation.resume(returning: error == nil ? result as? SPTAppRemotePlayerState : nil)
                }
            }
            guard let state = state else {
                status = "SDK no entregó estado; usando respaldo Web API"
                return .unavailable // Todavía no se envió ninguna orden: fallback seguro.
            }
            let shouldResume = state.isPaused
            let failure: String? = await withCheckedContinuation { continuation in
                let callback: SPTAppRemoteCallback = { _, error in
                    continuation.resume(returning: error?.localizedDescription)
                }
                if shouldResume { playerAPI.resume(callback) }
                else { playerAPI.pause(callback) }
            }
            if let failure = failure {
                status = "SDK no pudo cambiar reproducción: \(failure)"
                return .failed(failure)
            }
            status = shouldResume ? "SDK · reproducción reanudada" : "SDK · reproducción pausada"
            requestCurrentPlayerState()
            return .succeeded
        }

        let failure: String? = await withCheckedContinuation { continuation in
            let callback: SPTAppRemoteCallback = { _, error in
                continuation.resume(returning: error?.localizedDescription)
            }
            switch command {
            case .next: playerAPI.skip(toNext: callback)
            case .previous: playerAPI.skip(toPrevious: callback)
            default: continuation.resume(returning: "Comando no disponible")
            }
        }
        if let failure = failure {
            status = "SDK no pudo avanzar: \(failure)"
            return .failed(failure)
        }
        status = "SDK · comando enviado"
        requestCurrentPlayerState()
        return .succeeded
    }

    // Obtener estado real del SDK cuando lo solicitamos; no esperar un cambio
    // de canción para que el reloj salga de «No se está reproduciendo música».
    func requestCurrentPlayerState(fallbackToWeb: Bool = false) {
        guard enabled, isConnected, let playerAPI = appRemote?.playerAPI else {
            if fallbackToWeb {
                Task { @MainActor in
                    await SpotifyBridge.shared.refreshPlaybackInfo(force: true)
                }
            }
            return
        }
        playerAPI.getPlayerState { [weak self] result, error in
            if let state = result as? SPTAppRemotePlayerState, error == nil {
                self?.playerStateDidChange(state)
                return
            }
            self?.hasNativeMetadata = false
            self?.lastNativeEvent = "Falló lectura SDK: \(error?.localizedDescription ?? "sin estado")"
            self?.status = "SDK: estado no disponible; consultando respaldo Web API"
            if fallbackToWeb {
                Task { @MainActor in
                    await SpotifyBridge.shared.refreshPlaybackInfo(force: true, allowSDKFallback: true)
                }
            }
        }
    }

    // MARK: SPTAppRemotePlayerStateDelegate

    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        guard enabled, isConnected else { return }
        hasNativeMetadata = true
        lastNativeEvent = "Estado recibido: \(Date().formatted(date: .omitted, time: .standard))"
        status = "SDK conectado · metadatos nativos recibidos"
        let track = playerState.track
        let title = track.name
        let artist = track.artist.name
        let album = track.album.name
        // Nunca guardar tokens ni contenido del usuario en registros.
        SpotifyBridge.shared.receiveAppRemoteState(
            uri: track.uri, title: title, artist: artist, album: album,
            durationMs: Int(track.duration),
            progressMs: Int(playerState.playbackPosition),
            isPlaying: !playerState.isPaused
        )
    }
}
