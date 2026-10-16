import Foundation

// Al volver al primer plano, SwiftUI scenePhase y UIApplicationDelegate
// pueden pedir reconexión a la vez. No lanzar connect() duplicados.
enum SpotifySDKReconnectPolicy {
    static let minimumSecondsBetweenAttempts: TimeInterval = 8
    static let responseTimeoutSeconds: TimeInterval = 12

    static func shouldConnect(enabled: Bool, inForeground: Bool, connected: Bool,
                              lastAttempt: Date?, now: Date, force: Bool = false) -> Bool {
        guard enabled, inForeground, !connected else { return false }
        if force { return true }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= minimumSecondsBetweenAttempts
    }
}
