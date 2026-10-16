import Foundation
import Combine
import UserNotifications

/// Se guardan horas reales, no estimaciones. Una sesión no se completa sola al
/// vencer la meta; el usuario registra explícitamente cuando corta el ayuno.
struct FastingSession: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    let targetEndAt: Date
    var endedAt: Date?
    var plannedStartAt: Date?
    var durationHours: Int
}

@MainActor
final class FastingStore: ObservableObject {
    static let shared = FastingStore()
    @Published private(set) var sessions: [FastingSession] = []
    @Published private(set) var status = "Listo para registrar tu próxima sesión"
    private let key = "motowatch.fasting.sessions.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key) {
            if let value = try? JSONDecoder().decode([FastingSession].self, from: data) {
                sessions = value.sorted { $0.startedAt > $1.startedAt }
            } else {
                status = "No se pudo leer el historial de ayuno. No se sobrescribirá."
                loadFailed = true
            }
        }
    }
    private var loadFailed = false
    var active: FastingSession? { sessions.first { $0.endedAt == nil } }
    var lastCompleted: FastingSession? { sessions.first { $0.endedAt != nil } }

    func start(hours: Int, plannedStart: Date? = nil, at date: Date = Date()) {
        guard active == nil, (8...18).contains(hours), !loadFailed else { return }
        let item = FastingSession(id: UUID(), startedAt: date,
                                  targetEndAt: date.addingTimeInterval(Double(hours) * 3600),
                                  endedAt: nil, plannedStartAt: plannedStart,
                                  durationHours: hours)
        sessions.insert(item, at: 0)
        persist()
        status = "Ayuno iniciado y hora real guardada"
    }

    func finish(at date: Date = Date()) {
        guard let i = sessions.firstIndex(where: { $0.endedAt == nil }), !loadFailed,
              date >= sessions[i].startedAt else { return }
        sessions[i].endedAt = date
        persist()
        status = "Hora real de corte registrada"
    }

    private func persist() {
        guard !loadFailed else { return }
        do {
            let data = try JSONEncoder().encode(Array(sessions.prefix(365)))
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            status = "Error al guardar el historial de ayuno"
        }
    }
}

/// Los recordatorios requieren permisos locales iOS; no usan Atajos ni BLE.
/// Nunca dispara una notificación si el usuario no la habilita.
@MainActor
final class FastingReminderManager: ObservableObject {
    static let shared = FastingReminderManager()
    @Published private(set) var status = "Recordatorios desactivados"
    private let startID = "iwatch.fasting.planned.start"
    private let endID = "iwatch.fasting.planned.end"
    private init() {}

    func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [startID, endID])
        status = "Recordatorios cancelados"
    }

    func schedule(start: Date, end: Date, includeStart: Bool = true) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [startID, endID])
        center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] accepted, error in
            Task { @MainActor in
                guard let self else { return }
                guard accepted else {
                    self.status = "Activá las notificaciones de iWatch en Ajustes del iPhone"
                    return
                }
                if let error {
                    self.status = "No se pudieron habilitar avisos: \(error.localizedDescription)"
                    return
                }
                let reminders: [(String, Date, String, String)] = includeStart ? [
                    (self.startID, start, "Comienza tu horario previsto de ayuno", "Podés iniciar el registro cuando decidas."),
                    (self.endID, end, "Terminó tu horario previsto", "Abrí iWatch para registrar la hora real en que cortás el ayuno.")
                ] : [
                    (self.endID, end, "Llegó tu horario previsto de finalización", "Registrá cuando realmente cortes el ayuno.")
                ]
                for (identifier, date, title, message) in reminders where date > Date() {
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.body = message
                    content.sound = .default
                    let trigger = UNCalendarNotificationTrigger(
                        dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
                        repeats: false)
                    center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) { error in
                        guard let error else { return }
                        Task { @MainActor in
                            self.status = "No se pudo programar el aviso: \(error.localizedDescription)"
                        }
                    }
                }
                self.status = "Avisos locales de inicio y fin programados"
            }
        }
    }
}
