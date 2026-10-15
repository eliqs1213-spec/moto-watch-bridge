import Foundation
import Combine

enum HealthMetric: String, CaseIterable, Identifiable {
    case steps, heartRate, oxygen, stress, sleep, activeCalories, workouts
    var id: String { rawValue }
    var title: String {
        switch self {
        case .steps: return "Pasos"
        case .heartRate: return "Ritmo cardíaco"
        case .oxygen: return "Oxígeno en sangre"
        case .stress: return "Estrés"
        case .sleep: return "Sueño"
        case .activeCalories: return "Calorías activas"
        case .workouts: return "Entrenamientos"
        }
    }
    var symbol: String {
        switch self {
        case .steps: return "figure.walk"
        case .heartRate: return "heart.fill"
        case .oxygen: return "lungs.fill"
        case .stress: return "waveform.path"
        case .sleep: return "moon.stars.fill"
        case .activeCalories: return "flame.fill"
        case .workouts: return "figure.run"
        }
    }
    var isSample: Bool { [.heartRate, .oxygen, .stress].contains(self) }
}

struct WatchHealthReading: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let value: Double
}
struct WatchWorkout: Codable, Identifiable {
    let id: String
    let startedAt: Date
    let name: String
    let durationMinutes: Double
}
struct StoredSleepSession: Codable, Identifiable {
    let id: String
    let startedAt: Date
    let endedAt: Date
    let minutes: Double
}
struct HealthSnapshot {
    let value: Double
    let measuredAt: Date
    let updatedAt: Date
}

// Los campos nuevos son opcionales para conservar el JSON de las versiones
// anteriores. La ruta history-v1.json no cambia. Sueño: día de despertar.
struct WatchHealthDay: Codable, Identifiable {
    let watchID: String
    let dayKey: String
    var steps: Int?
    var sleepMinutes: Double?
    var heartRate: [WatchHealthReading]
    var stress: [WatchHealthReading]
    var workouts: [WatchWorkout]
    var workoutsComplete: Bool
    var syncedAt: Date
    var stepsExperimental: Bool? = nil
    var heartRateExperimental: Bool? = nil
    var stepsMeasuredAt: Date? = nil
    var oxygen: [WatchHealthReading]? = nil
    var stepsHistory: [WatchHealthReading]? = nil
    var activeCaloriesHistory: [WatchHealthReading]? = nil
    var sleepSessions: [StoredSleepSession]? = nil
    var metricUpdates: [String: Date]? = nil
    var id: String { "\(watchID)|\(dayKey)" }

    func readings(for metric: HealthMetric) -> [WatchHealthReading] {
        switch metric {
        case .heartRate: return heartRate.sorted { $0.timestamp < $1.timestamp }
        case .stress: return stress.sorted { $0.timestamp < $1.timestamp }
        case .oxygen: return (oxygen ?? []).sorted { $0.timestamp < $1.timestamp }
        case .steps:
            if let rows = stepsHistory, !rows.isEmpty { return rows.sorted { $0.timestamp < $1.timestamp } }
            return steps.map { [WatchHealthReading(id: "legacy-steps-\(id)", timestamp: stepsMeasuredAt ?? syncedAt, value: Double($0))] } ?? []
        case .activeCalories: return (activeCaloriesHistory ?? []).sorted { $0.timestamp < $1.timestamp }
        case .sleep:
            guard let minutes = sleepMinutes else { return [] }
            return [WatchHealthReading(id: "sleep-total-\(id)", timestamp: sleepSessions?.map(\.endedAt).max() ?? syncedAt, value: minutes / 60)]
        case .workouts:
            guard workoutsComplete || !workouts.isEmpty else { return [] }
            return [WatchHealthReading(id: "workouts-\(id)", timestamp: workouts.map(\.startedAt).max() ?? syncedAt, value: Double(workouts.count))]
        }
    }
    func value(for metric: HealthMetric) -> Double? {
        let rows = readings(for: metric)
        guard !rows.isEmpty else { return nil }
        if metric.isSample { return rows.reduce(0) { $0 + $1.value } / Double(rows.count) }
        return rows.last?.value
    }
}

@MainActor
final class WatchHealthStore: ObservableObject {
    static let shared = WatchHealthStore()
    @Published private(set) var days: [WatchHealthDay] = []
    @Published private(set) var storageError: String?
    private let fileURL: URL
    private var loadFailed = false
    enum StoreError: Error { case invalidReading, overlappingSleep, unreadableHistory }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchHealth/history-v1.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do { days = try JSONDecoder().decode([WatchHealthDay].self, from: Data(contentsOf: self.fileURL)) }
        catch { loadFailed = true; storageError = "No se pudo abrir el histórico guardado. Se conserva el archivo original." }
    }
    private func persist(_ updated: [WatchHealthDay]) throws {
        guard !loadFailed else { throw StoreError.unreadableHistory }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated.sorted { $0.dayKey < $1.dayKey }).write(to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            days = updated.sorted { $0.dayKey < $1.dayKey }; storageError = nil
        } catch { storageError = "No se pudo guardar el histórico en este iPhone."; throw error }
    }
    func upsert(_ day: WatchHealthDay) throws {
        try persist(days.filter { $0.id != day.id } + [day])
    }
    private func mutate(keys: Set<String>, watchID: String, metric: HealthMetric,
                        body: (inout WatchHealthDay, String) throws -> Void) throws {
        guard !keys.isEmpty else { return }
        var updated = days
        for key in keys {
            var day = updated.first { $0.watchID == watchID && $0.dayKey == key }
                ?? WatchHealthDay(watchID: watchID, dayKey: key, steps: nil, sleepMinutes: nil,
                    heartRate: [], stress: [], workouts: [], workoutsComplete: false, syncedAt: Date())
            try body(&day, key)
            day.syncedAt = Date()
            var stamps = day.metricUpdates ?? [:]; stamps[metric.rawValue] = Date(); day.metricUpdates = stamps
            updated.removeAll { $0.id == day.id }; updated.append(day)
        }
        try persist(updated)
    }
    private static func union(_ previous: [WatchHealthReading], _ incoming: [WatchHealthReading]) -> [WatchHealthReading] {
        var indexed = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for item in incoming { indexed[item.id] = item }
        return indexed.values.sorted { $0.timestamp < $1.timestamp }
    }
    func mergeReadings(watchID: String, metric: HealthMetric, readings: [WatchHealthReading]) throws {
        guard metric.isSample else { throw StoreError.invalidReading }
        let bounds: ClosedRange<Double> = metric == .heartRate ? 25...240 : 0...100
        guard readings.allSatisfy({ $0.value.isFinite && bounds.contains($0.value) }) else { throw StoreError.invalidReading }
        try mutate(keys: Set(readings.map { Self.key($0.timestamp) }), watchID: watchID, metric: metric) { day, key in
            let incoming = readings.filter { Self.key($0.timestamp) == key }
            switch metric {
            case .heartRate: day.heartRate = Self.union(day.heartRate, incoming); day.heartRateExperimental = false
            case .stress: day.stress = Self.union(day.stress, incoming)
            case .oxygen: day.oxygen = Self.union(day.oxygen ?? [], incoming)
            default: break
            }
        }
    }
    func mergeCounter(watchID: String, metric: HealthMetric, value: Double, at timestamp: Date) throws {
        guard [.steps, .activeCalories].contains(metric), value.isFinite, value >= 0,
              value <= 10000000, value.rounded() == value else { throw StoreError.invalidReading }
        let key = Self.key(timestamp)
        let row = WatchHealthReading(id: "\(metric.rawValue):\(Int64(timestamp.timeIntervalSince1970))", timestamp: timestamp, value: value)
        try mutate(keys: [key], watchID: watchID, metric: metric) { day, _ in
            if metric == .steps {
                let previous = day.readings(for: .steps).map {
                    WatchHealthReading(id: "steps:\(Int64($0.timestamp.timeIntervalSince1970))", timestamp: $0.timestamp, value: $0.value)
                }
                day.stepsHistory = Self.union(previous, [row])
                if let last = day.stepsHistory?.last {
                    day.steps = Int(last.value); day.stepsMeasuredAt = last.timestamp
                }
                day.stepsExperimental = false
            } else { day.activeCaloriesHistory = Self.union(day.activeCaloriesHistory ?? [], [row]) }
        }
    }
    func mergeSleep(watchID: String, sessions: [WatchSleepProtocol.Session]) throws {
        guard sessions.allSatisfy({ $0.minutes.isFinite && $0.minutes > 0 && $0.minutes <= 1440 && $0.startedAt < $0.endedAt }) else { throw StoreError.invalidReading }
        try mutate(keys: Set(sessions.map { Self.key($0.endedAt) }), watchID: watchID, metric: .sleep) { day, key in
            var indexed = Dictionary((day.sleepSessions ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            for session in sessions where Self.key(session.endedAt) == key {
                indexed[session.id] = StoredSleepSession(id: session.id, startedAt: session.startedAt, endedAt: session.endedAt, minutes: session.minutes)
            }
            let sorted = indexed.values.sorted { $0.startedAt < $1.startedAt }
            for pair in zip(sorted, sorted.dropFirst()) where pair.0.endedAt > pair.1.startedAt { throw StoreError.overlappingSleep }
            day.sleepSessions = sorted; day.sleepMinutes = sorted.reduce(0) { $0 + $1.minutes }
        }
    }
    // Conserva la API del panel de diagnóstico anterior.
    func mergeExperimental(watchID: String, steps: WatchHealthProtocol.StepCandidate?, pulse: [WatchHealthProtocol.PulseCandidate]) throws {
        if let steps = steps { try mergeCounter(watchID: watchID, metric: .steps, value: Double(steps.count), at: steps.timestamp) }
        try mergeReadings(watchID: watchID, metric: .heartRate, readings: pulse.map {
            WatchHealthReading(id: "31/07:\(Int64($0.timestamp.timeIntervalSince1970))", timestamp: $0.timestamp, value: Double($0.bpm))
        })
    }
    var watchIDs: [String] { Array(Set(days.map(\.watchID))).sorted() }
    func day(_ date: Date, watchID: String) -> WatchHealthDay? {
        days.first { $0.watchID == watchID && $0.dayKey == Self.key(date) }
    }
    func latest(_ metric: HealthMetric, watchID: String, dates: [Date]? = nil) -> HealthSnapshot? {
        let keys = dates.map { Set($0.map(Self.key)) }
        return days.filter { $0.watchID == watchID && (keys?.contains($0.dayKey) ?? true) }.compactMap { day -> HealthSnapshot? in
            guard let last = day.readings(for: metric).last else { return nil }
            return HealthSnapshot(value: last.value, measuredAt: last.timestamp,
                                  updatedAt: day.metricUpdates?[metric.rawValue] ?? day.syncedAt)
        }.max { $0.measuredAt < $1.measuredAt }
    }
    static func key(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
