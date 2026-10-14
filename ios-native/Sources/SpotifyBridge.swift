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
    struct Song: Decodable { let name: String }
    let is_playing: Bool
    let device: Device?
    let item: Song?
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

    private var authentication: ASWebAuthenticationSession?
    private var oauthVerifier = ""
    private var oauthState = ""
    private var lastDeviceID: String?
    private var lastIsPlaying: Bool?
    private var requestBusy = false
    private var lastCommandTimes: [String: Date] = [:]
    private let scopes = "user-read-playback-state user-modify-playback-state"

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first(where: { $0.isKeyWindow })
        return window ?? ASPresentationAnchor()
    }

    func setEnabled(_ enabled: Bool) {
        controlEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "motowatch.spotify.enabled")
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
        SecureTokenStorage.clear()
        lastDeviceID = nil
        lastIsPlaying = nil
        setEnabled(false)
        status = "Sin autorizar"
        record("Spotify desvinculado")
    }

    func refreshPlaybackInfo() async {
        do {
            if let playback = try await fetchPlayback() {
                updateCachedPlayback(playback)
                status = playback.is_playing ? "Spotify reproduciendo" : "Spotify pausado"
            } else {
                status = "Sin reproductor activo informado"
            }
        } catch { failure(error) }
    }

    func receive(_ command: WatchCommand) {
        guard command != .unknown else { return }
        guard controlEnabled else { record("Spotify deshabilitado; comando sin ejecutar"); return }
        let now = Date()
        let key = command.rawValue
        let limit = command == .toggle ? 1.5 : 0.65
        if let prior = lastCommandTimes[key], now.timeIntervalSince(prior) < limit { return }
        lastCommandTimes[key] = now
        if requestBusy {
            record("Spotify ocupado: comando \(key) no enviado")
            return
        }
        requestBusy = true
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
            }
            do {
                try await self.run(command)
            } catch { self.failure(error) }
        }
    }

    private func run(_ command: WatchCommand) async throws {
        var action: String
        let devicePath: String
        switch command {
        case .next: action = "next"
        case .previous: action = "previous"
        case .toggle:
            if let playing = try await fetchPlayback() {
                updateCachedPlayback(playing)
            }
            if lastIsPlaying == nil { throw SpotifyBridgeError.emptyPlayer }
            action = lastIsPlaying! ? "pause" : "play"
        case .unknown: return
        }
        devicePath = lastDeviceID.map { "?device_id=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)" } ?? ""
        let method = (action == "next" || action == "previous") ? "POST" : "PUT"
        _ = try await api("/me/player/\(action)\(devicePath)", method: method)
        if action == "play" { lastIsPlaying = true }
        if action == "pause" { lastIsPlaying = false }
        lastAction = "Enviado: \(action.uppercased())"
        record("[SPOTIFY] \(action.uppercased()) enviado")
        // No mantener una encuesta periódica: iOS limita la ejecución en segundo plano.
        if UIApplication.shared.applicationState == .active {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshPlaybackInfo()
        }
    }

    private func updateCachedPlayback(_ playback: SpotifyPlayback) {
        if let id = playback.device?.id { lastDeviceID = id }
        lastIsPlaying = playback.is_playing
        if let name = playback.item?.name { lastSong = name }
    }

    private func fetchPlayback() async throws -> SpotifyPlayback? {
        let result = try await api("/me/player", method: "GET")
        guard !result.isEmpty else { return nil }
        return try JSONDecoder().decode(SpotifyPlayback.self, from: result)
    }

    private func api(_ path: String, method: String) async throws -> Data {
        let token = try await validAccessToken()
        guard let url = URL(string: "https://api.spotify.com/v1\(path)") else { throw SpotifyBridgeError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
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
