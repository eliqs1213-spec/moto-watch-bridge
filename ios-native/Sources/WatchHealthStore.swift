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
    // nil: lectura de una versión antigua, cobertura sin verificar.
    // false: consulta parcial; true: el recorrido temporal concluyó.
    var sleepRetrievalComplete: Bool? = nil
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
    // Diagnóstico estructural: no incluye valores ni identificadores de salud.
    @Published private(set) var storageDiagnostic: String?
    private let fileURL: URL
    private var loadFailed = false
    enum StoreError: Error { case invalidReading, overlappingSleep, unreadableHistory }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchHealth/history-v1.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do { days = try JSONDecoder().decode([WatchHealthDay].self, from: Data(contentsOf: self.fileURL)) }
        catch {
            loadFailed = true
            storageError = "No se pudo abrir el histórico guardado. Se conserva el archivo original."
            storageDiagnostic = Self.safeLoadDiagnostic(error)
        }
    }

    private static func safeLoadDiagnostic(_ error: Error) -> String {
        func codingPath(_ path: [CodingKey]) -> String {
            let labels = path.map { $0.stringValue }
            return labels.isEmpty ? "raíz del JSON" : labels.joined(separator: " → ")
        }
        switch error {
        case let DecodingError.keyNotFound(key, context):
            return "Campo obligatorio ausente: \(key.stringValue). Ubicación: \(codingPath(context.codingPath))."
        case let DecodingError.typeMismatch(_, context):
            return "Tipo de dato incompatible. Ubicación: \(codingPath(context.codingPath))."
        case let DecodingError.valueNotFound(_, context):
            return "Valor obligatorio ausente. Ubicación: \(codingPath(context.codingPath))."
        case let DecodingError.dataCorrupted(context):
            return "Formato o fecha inválidos. Ubicación: \(codingPath(context.codingPath))."
        default:
            let failure = error as NSError
            return "Error de lectura del archivo: \(failure.domain), código \(failure.code)."
        }
    }

    // Si el primer intento falló por protección temporal del archivo en iOS,
    // reintentar SOLO al volver la app activa y el dispositivo desbloqueado.
    // Si persiste un error de JSON, seguir sin sobrescribir el original.
    @discardableResult
    func retryLoadAfterUnlockIfNeeded() -> Bool {
        guard loadFailed else { return false }
        do {
            let decoded = try JSONDecoder().decode([WatchHealthDay].self,
                                                   from: Data(contentsOf: fileURL))
            days = decoded
            loadFailed = false
            storageError = nil
            storageDiagnostic = nil
            return true
        } catch {
            storageDiagnostic = Self.safeLoadDiagnostic(error)
            return false
        }
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
    func mergeSleep(watchID: String, sessions: [WatchSleepProtocol.Session], retrievalComplete: Bool? = nil) throws {
        guard sessions.allSatisfy({
            $0.minutes.isFinite && $0.minutes > 0 && $0.minutes <= 1440 &&
            $0.startedAt < $0.endedAt
        }) else { throw StoreError.invalidReading }
        try mutate(keys: Set(sessions.map { Self.key($0.endedAt) }), watchID: watchID, metric: .sleep) { day, key in
            var indexed = Dictionary(
                (day.sleepSessions ?? []).map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest })
            var acceptedNewInformation = false
            let incoming = sessions.filter { Self.key($0.endedAt) == key }
                .sorted { $0.startedAt < $1.startedAt }

            for session in incoming {
                let row = StoredSleepSession(id: session.id, startedAt: session.startedAt,
                                             endedAt: session.endedAt, minutes: session.minutes)
                let overlapping = indexed.values.filter {
                    $0.startedAt < row.endedAt && row.startedAt < $0.endedAt
                }
                if overlapping.isEmpty {
                    indexed[row.id] = row
                    acceptedNewInformation = true
                    continue
                }

                // Motorola puede devolver primero 2h59 y, al terminar otro
                // bloque, actualizar el MISMO descanso a 4h08 (envolvente).
                // El registro total reemplaza a los fragmentos que abarca:
                // nunca se debe sumar ambos ni fallar por superposición.
                let fullyCoversOld = overlapping.allSatisfy {
                    row.startedAt <= $0.startedAt && row.endedAt >= $0.endedAt
                }
                let totalOverlappedMinutes = overlapping.reduce(0) { $0 + $1.minutes }
                if fullyCoversOld && row.minutes >= totalOverlappedMinutes {
                    if overlapping.count != 1 || overlapping[0].id != row.id ||
                        overlapping[0].minutes != row.minutes {
                        acceptedNewInformation = true
                    }
                    for old in overlapping { indexed.removeValue(forKey: old.id) }
                    indexed[row.id] = row
                    continue
                }

                // Una sincronización tardía puede traer nuevamente un bloque
                // antiguo de 2h59. No degradar un total ya recuperado de 4h08.
                if overlapping.count == 1, let saved = overlapping.first,
                   saved.startedAt <= row.startedAt, saved.endedAt >= row.endedAt,
                   saved.minutes >= row.minutes {
                    continue
                }
                // Superposición sin una relación inequívoca: no adivinar.
                throw StoreError.overlappingSleep
            }

            let sorted = indexed.values.sorted { $0.startedAt < $1.startedAt }
            for pair in zip(sorted, sorted.dropFirst()) where pair.0.endedAt > pair.1.startedAt {
                throw StoreError.overlappingSleep
            }
            day.sleepSessions = sorted
            day.sleepMinutes = sorted.reduce(0) { $0 + $1.minutes }
            if let retrievalComplete {
                // Una relectura parcial sin novedades no borra la confirmación
                // anterior; si sí hay información nueva parcial, se advierte.
                if retrievalComplete {
                    day.sleepRetrievalComplete = true
                } else if acceptedNewInformation {
                    day.sleepRetrievalComplete = false
                } else if day.sleepRetrievalComplete == nil {
                    day.sleepRetrievalComplete = false
                }
            }
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
