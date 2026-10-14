import Foundation
import Combine

enum HealthMetric: String, CaseIterable, Identifiable {
    case steps, heartRate, sleep, stress, workouts
    var id: String { rawValue }
    var title: String {
        switch self {
        case .steps: return "Pasos"
        case .heartRate: return "Frecuencia cardíaca"
        case .sleep: return "Sueño"
        case .stress: return "Estrés"
        case .workouts: return "Entrenamientos"
        }
    }
    var symbol: String {
        switch self {
        case .steps: return "figure.walk"
        case .heartRate: return "heart.fill"
        case .sleep: return "moon.fill"
        case .stress: return "waveform.path"
        case .workouts: return "figure.run"
        }
    }
}

struct WatchHealthReading: Codable, Identifiable {
    let id: String // Identificador estable de la muestra del reloj.
    let timestamp: Date
    let value: Double
}

struct WatchWorkout: Codable, Identifiable {
    let id: String
    let startedAt: Date
    let name: String
    let durationMinutes: Double
}

// Un registro por reloj y día local de origen. Sueño se atribuye al día de
// despertar. Un valor nil significa ausencia de datos; cero es un valor real.
// La futura sincronización debe entregar un snapshot completo de ese día,
// conservar campos ya leídos y usar IDs estables para evitar duplicados.
struct WatchHealthDay: Codable, Identifiable {
    let watchID: String
    let dayKey: String // yyyy-MM-dd, conserva el día aunque cambie la zona horaria.
    var steps: Int?
    var sleepMinutes: Double?
    var heartRate: [WatchHealthReading]
    var stress: [WatchHealthReading]
    var workouts: [WatchWorkout]
    var workoutsComplete: Bool
    let syncedAt: Date
    var id: String { "\(watchID)|\(dayKey)" }

    func value(for metric: HealthMetric) -> Double? {
        switch metric {
        case .steps: return steps.map(Double.init)
        case .sleep: return sleepMinutes.map { $0 / 60 }
        case .heartRate: return average(heartRate)
        case .stress: return average(stress)
        case .workouts: return workoutsComplete || !workouts.isEmpty ? Double(workouts.count) : nil
        }
    }
    private func average(_ readings: [WatchHealthReading]) -> Double? {
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0) { $0 + $1.value } / Double(readings.count)
    }
}

@MainActor
final class WatchHealthStore: ObservableObject {
    static let shared = WatchHealthStore()
    @Published private(set) var days: [WatchHealthDay] = []
    @Published private(set) var storageError: String?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                                          in: .userDomainMask)[0]
            .appendingPathComponent("WatchHealth/history-v1.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            days = try JSONDecoder().decode([WatchHealthDay].self,
                                           from: Data(contentsOf: self.fileURL))
        } catch {
            storageError = "No se pudo abrir el histórico guardado."
        }
    }

    // Punto de integración para el decoder BLE, una vez validado.
    // No importa ni envía el contenido del bugreport.
    func upsert(_ day: WatchHealthDay) throws {
        var updated = days.filter { $0.id != day.id }
        updated.append(day)
        updated.sort { $0.dayKey < $1.dayKey }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            days = updated
            storageError = nil
        } catch {
            storageError = "No se pudo guardar el histórico en este iPhone."
            throw error
        }
    }

    var watchIDs: [String] { Array(Set(days.map(\.watchID))).sorted() }
    func day(_ date: Date, watchID: String) -> WatchHealthDay? {
        days.first { $0.watchID == watchID && $0.dayKey == Self.key(date) }
    }
    static func key(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
