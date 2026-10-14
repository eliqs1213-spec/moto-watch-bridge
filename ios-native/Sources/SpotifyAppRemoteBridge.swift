import Foundation
import Combine
import UIKit
import SpotifyiOS

// Complemento opcional: eventos rápidos en primer plano.
// NO reemplaza Spotify Web API ni altera los controles con iPhone bloqueado.
final class SpotifyAppRemoteBridge: NSObject, ObservableObject,
    SPTSessionManagerDelegate, SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {

    static let shared = SpotifyAppRemoteBridge()

    @Published private(set) var status = "SDK opcional · sin conectar"
    @Published private(set) var isConnected = false
    @Published private(set) var enabled = false

    private var sessionManager: SPTSessionManager?
    private var appRemote: SPTAppRemote?
    private var authorizing = false

    private override init() { super.init() }

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
        status = "SDK desconectado; Web API sigue disponible"
    }

    func applicationDidEnterBackground() {
        // Recomendación del SDK oficial: cerrar su sesión cuando pasamos a fondo.
        // No afecta el CoreBluetooth que mantiene conectado al reloj.
        appRemote?.disconnect()
        isConnected = false
        if enabled { status = "SDK en reposo · Web API activa en segundo plano" }
    }

    func applicationDidBecomeActive() {
        // Reconectar únicamente si el usuario habilitó App Remote y se conserva
        // un token de la sesión del SDK; no disparar OAuth en segundo plano.
        guard enabled, let remote = appRemote,
              !remote.isConnected,
              remote.connectionParameters.accessToken != nil else { return }
        remote.connect()
    }

    // MARK: SPTSessionManagerDelegate

    func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        authorizing = false
        guard enabled, let remote = appRemote else { return }
        remote.connectionParameters.accessToken = session.accessToken
        status = "SDK autorizado · conectando con Spotify"
        remote.connect()
    }

    func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
        guard enabled, let remote = appRemote else { return }
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
        status = "SDK conectado · eventos de Spotify activos"
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] result, error in
            if let error = error {
                self?.status = "Error al suscribir eventos: \(error.localizedDescription)"
            } else if let state = result as? SPTAppRemotePlayerState {
                self?.playerStateDidChange(state)
            }
        })
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        isConnected = false
        status = "SDK sin conexión: \(error?.localizedDescription ?? "Spotify no disponible")"
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        isConnected = false
        status = "SDK desconectado · controles Web API disponibles"
    }

    // MARK: SPTAppRemotePlayerStateDelegate

    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        guard enabled, isConnected else { return }
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
