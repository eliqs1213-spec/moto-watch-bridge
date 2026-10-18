import Foundation

enum SpotifyMetadataRefreshPolicy {
    static let minimumAutomaticInterval: TimeInterval = 12

    static func shouldStart(inFlight: Bool, forced: Bool,
                            lastAutomaticAt: Date, now: Date) -> Bool {
        guard !inFlight else { return false }
        return forced || now.timeIntervalSince(lastAutomaticAt) >= minimumAutomaticInterval
    }
}
