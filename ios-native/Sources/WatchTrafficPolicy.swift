import Foundation

enum WatchTrafficKind {
    case notification, weather, weatherUnit, watchFaceRead, fileLEProbe, music, health, vitals, sleepRead, battery
    var priority: Int {
        switch self {
        case .notification, .weather, .weatherUnit: return 0
        case .music: return 1
        case .watchFaceRead, .fileLEProbe, .health, .vitals, .sleepRead: return 2
        case .battery: return 3
        }
    }
}

enum WatchTrafficPolicy {
    // Stable ordering within each class; a music handshake delay never blocks notices.
    static func nextIndex(_ kinds: [WatchTrafficKind], musicReady: Bool) -> Int? {
        kinds.indices.filter { musicReady || kinds[$0] != .music }.min {
            kinds[$0].priority == kinds[$1].priority ? $0 < $1 : kinds[$0].priority < kinds[$1].priority
        }
    }
    static func acceptsNotice(target: String?, current: String?, expiresAt: Date?, now: Date) -> Bool {
        guard let target = target, target == current, let expiry = expiresAt else { return false }
        return expiry > now
    }
    static func reconnectDelay(failures: Int) -> TimeInterval {
        min(60, pow(2, Double(min(max(failures - 1, 0), 6))))
    }
}

enum HealthRefreshGroup: String, CaseIterable {
    case counters, pulse, stress, oxygen, sleep
    var interval: TimeInterval {
        switch self { case .counters: return 300; case .pulse, .stress, .oxygen: return 900; case .sleep: return 3600 }
    }
}
struct HealthRefreshSchedule {
    private var lastAttempts: [String: [HealthRefreshGroup: Date]] = [:]
    func due(watchID: String, now: Date) -> Set<HealthRefreshGroup> {
        Set(HealthRefreshGroup.allCases.filter {
            now.timeIntervalSince(lastAttempts[watchID]?[$0] ?? .distantPast) >= $0.interval
        })
    }
    mutating func mark(_ group: HealthRefreshGroup, watchID: String, at date: Date) {
        lastAttempts[watchID, default: [:]][group] = date
    }
}
