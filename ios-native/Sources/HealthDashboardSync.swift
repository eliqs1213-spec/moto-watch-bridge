import Foundation
import Combine

@MainActor
final class HealthDashboardSync: ObservableObject {
    static let shared = HealthDashboardSync()
    @Published private(set) var isRunning = false
    @Published private(set) var progress = 0.0
    @Published private(set) var status = "Tu histórico está guardado en este iPhone"
    @Published private(set) var issues: [String] = []
    private var task: Task<Void, Never>?
    private enum SyncError: Error { case connectionChanged, didNotStart }

    func update(watch: WatchBLEManager) {
        guard !isRunning else { return }
        guard watch.isConnected, let watchID = watch.healthWatchID else {
            status = "Conectá tu Moto Watch desde la pestaña iWatch"; return
        }
        guard !WatchHealthSync.shared.isRunning, !WatchStressProbe.shared.isRunning,
              !WatchVitalsProbe.shared.isRunning, !WatchSleepProbe.shared.isRunning else {
            status = "Hay una consulta en curso. Esperá a que termine."; return
        }
        isRunning = true; progress = 0; issues = []
        task = Task { [weak self] in
            guard let self = self else { return }
            defer { self.isRunning = false; self.task = nil }
            let store = WatchHealthStore.shared
            do {
                self.status = "Actualizando pasos y ritmo cardíaco…"
                try await self.wait(watch.refreshHealth(), running: { WatchHealthSync.shared.isRunning })
                try self.check(watch, watchID)
                let health = WatchHealthSync.shared
                if let steps = health.steps {
                    try store.mergeCounter(watchID: watchID, metric: .steps, value: Double(steps.count), at: steps.timestamp)
                } else { self.issues.append("Pasos: no se recibieron registros nuevos") }
                if !health.pulse.isEmpty {
                    try store.mergeReadings(watchID: watchID, metric: .heartRate, readings: health.pulse.map {
                        WatchHealthReading(id: "31/07:\(Int64($0.timestamp.timeIntervalSince1970))", timestamp: $0.timestamp, value: Double($0.bpm))
                    })
                } else { self.issues.append("Ritmo cardíaco: no se recibieron muestras") }
                self.progress = 0.2

                self.status = "Actualizando estrés…"
                try await self.wait(watch.refreshStressProbe(), running: { WatchStressProbe.shared.isRunning })
                try self.check(watch, watchID)
                let stress = WatchStressProbe.shared.samples
                if !stress.isEmpty {
                    try store.mergeReadings(watchID: watchID, metric: .stress, readings: stress.map {
                        WatchHealthReading(id: "31/0E:\(Int64($0.timestamp.timeIntervalSince1970))", timestamp: $0.timestamp, value: Double($0.value))
                    })
                } else { self.issues.append("Estrés: no se recibieron muestras") }
                self.progress = 0.4

                self.status = "Actualizando oxígeno en sangre…"
                try await self.wait(watch.refreshVitalsProbe(.oxygen), running: { WatchVitalsProbe.shared.isRunning })
                try self.check(watch, watchID)
                // Solo candidato A, identificado y confirmado por el usuario.
                let oxygen = WatchVitalsProbe.shared.readings.filter { $0.channel == "A" }
                if !oxygen.isEmpty {
                    try store.mergeReadings(watchID: watchID, metric: .oxygen, readings: oxygen.map {
                        WatchHealthReading(id: "31/0C:\(Int64($0.timestamp.timeIntervalSince1970))", timestamp: $0.timestamp, value: Double($0.value))
                    })
                } else { self.issues.append("Oxígeno: no se recibieron muestras de la serie validada") }
                self.progress = 0.6

                self.status = "Actualizando calorías activas…"
                try await self.wait(watch.refreshVitalsProbe(.calories), running: { WatchVitalsProbe.shared.isRunning })
                try self.check(watch, watchID)
                if let counter = WatchVitalsProbe.shared.counters.first(where: { $0.field == 9 }),
                   let date = WatchVitalsProbe.shared.counterTime {
                    try store.mergeCounter(watchID: watchID, metric: .activeCalories, value: Double(counter.value), at: date)
                } else { self.issues.append("Calorías activas: no se recibió el contador validado") }
                self.progress = 0.8

                self.status = "Actualizando sesiones de sueño…"
                try await self.wait(watch.refreshSleepProbe(day: Date()), running: { WatchSleepProbe.shared.isRunning })
                try self.check(watch, watchID)
                let sessions = WatchSleepProbe.shared.sessions
                if !sessions.isEmpty { try store.mergeSleep(watchID: watchID, sessions: sessions) }
                else { self.issues.append("Sueño: no se recibieron sesiones") }
                self.progress = 1
                self.status = self.issues.isEmpty ? "Actualizado y guardado en este iPhone"
                    : "Actualización parcial: se guardaron los datos recibidos"
            } catch SyncError.connectionChanged {
                self.status = "La conexión cambió. Los datos ya guardados se conservan."
            } catch {
                self.status = store.storageError ?? "No se pudo completar la actualización. Revisá el diagnóstico."
            }
        }
    }
    private func check(_ watch: WatchBLEManager, _ id: String) throws {
        guard watch.isConnected, watch.healthWatchID == id else { throw SyncError.connectionChanged }
    }
    private func wait(_ launch: Task<Bool, Never>?, running: () -> Bool) async throws {
        guard let launch = launch else { throw SyncError.didNotStart }
        guard await launch.value else { throw SyncError.didNotStart }
        while running() {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 150_000_000)
        }
    }
}
