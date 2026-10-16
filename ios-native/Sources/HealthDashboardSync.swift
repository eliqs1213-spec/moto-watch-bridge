import Foundation
import Combine
import UIKit

@MainActor
final class HealthDashboardSync: ObservableObject {
    static let shared = HealthDashboardSync()
    @Published private(set) var isRunning = false
    @Published private(set) var progress = 0.0
    @Published private(set) var status = "Tu histórico está guardado en este iPhone"
    @Published private(set) var issues: [String] = []
    private var task: Task<Void, Never>?
    private var schedule = HealthRefreshSchedule()
    private var automaticTask: Task<Void, Never>?
    private var visible = false
    private var active = false
    private var automaticRun = false

    func setVisibility(_ visible: Bool, active: Bool, watch: WatchBLEManager) {
        self.visible = visible; self.active = active
        automaticTask?.cancel(); automaticTask = nil
        if !active || (!visible && automaticRun) { task?.cancel() }
        guard visible, active else { return }
        automaticTask = Task { [weak self, weak watch] in
            while !Task.isCancelled {
                guard let self = self, let watch = watch else { return }
                self.update(watch: watch, automatic: true)
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            }
        }
    }
    func connectionChanged(watch: WatchBLEManager) {
        if !watch.isConnected { task?.cancel() }
        else if visible && active { update(watch: watch, automatic: true) }
    }
    private enum SyncError: Error { case connectionChanged, didNotStart }

    func update(watch: WatchBLEManager, automatic: Bool = false) {
        guard UIApplication.shared.applicationState == .active else { return }
        guard !isRunning else { return }
        guard watch.isConnected, let watchID = watch.healthWatchID else {
            if !automatic { status = "Conectá tu Moto Watch desde la pestaña iWatch" }; return
        }
        guard !WatchHealthSync.shared.isRunning, !WatchStressProbe.shared.isRunning,
              !WatchVitalsProbe.shared.isRunning, !WatchSleepProbe.shared.isRunning else {
            if !automatic { status = "Hay una consulta en curso. Esperá a que termine." }; return
        }
        let groups = automatic ? schedule.due(watchID: watchID, now: Date()) : Set(HealthRefreshGroup.allCases)
        guard !groups.isEmpty else { return }
        isRunning = true; automaticRun = automatic; progress = 0; issues = []
        task = Task { [weak self] in
            guard let self = self else { return }
            defer { self.isRunning = false; self.automaticRun = false; self.task = nil }
            let store = WatchHealthStore.shared
            do {
                if groups.contains(.counters) || groups.contains(.pulse) {
                try self.check(watch, watchID)
                self.schedule.mark(.counters, watchID: watchID, at: Date())
                if groups.contains(.pulse) { self.schedule.mark(.pulse, watchID: watchID, at: Date()) }
                self.status = groups.contains(.pulse) ? "Actualizando pasos, calorías y ritmo cardíaco…" : "Actualizando pasos y calorías…"
                try await self.wait(watch.refreshHealth(includePulse: groups.contains(.pulse)), running: { WatchHealthSync.shared.isRunning })
                try self.check(watch, watchID)
                let health = WatchHealthSync.shared
                if let steps = health.steps {
                    try store.mergeCounter(watchID: watchID, metric: .steps, value: Double(steps.count), at: steps.timestamp)
                } else { self.issues.append("Pasos: no se recibieron registros nuevos") }
                if let calories = health.activeCalories {
                    try store.mergeCounter(watchID: watchID, metric: .activeCalories, value: Double(calories.value), at: calories.timestamp)
                } else { self.issues.append("Calorías activas: sin contador nuevo") }
                if groups.contains(.pulse) {
                if !health.pulse.isEmpty {
                    try store.mergeReadings(watchID: watchID, metric: .heartRate, readings: health.pulse.map {
                        WatchHealthReading(id: "31/07:\(Int64($0.timestamp.timeIntervalSince1970))", timestamp: $0.timestamp, value: Double($0.bpm))
                    })
                } else { self.issues.append("Ritmo cardíaco: no se recibieron muestras") }
                }
                }
                self.progress = 0.2

                if groups.contains(.stress) {
                try self.check(watch, watchID)
                self.schedule.mark(.stress, watchID: watchID, at: Date())
                self.status = "Actualizando estrés…"
                try await self.wait(watch.refreshStressProbe(), running: { WatchStressProbe.shared.isRunning })
                try self.check(watch, watchID)
                let stress = WatchStressProbe.shared.samples
                if !stress.isEmpty {
                    try store.mergeReadings(watchID: watchID, metric: .stress, readings: stress.map {
                        WatchHealthReading(id: "31/0E:\(Int64($0.timestamp.timeIntervalSince1970))", timestamp: $0.timestamp, value: Double($0.value))
                    })
                } else { self.issues.append("Estrés: no se recibieron muestras") }

                }
                self.progress = 0.4

                if groups.contains(.oxygen) {
                try self.check(watch, watchID)
                self.schedule.mark(.oxygen, watchID: watchID, at: Date())
                self.status = "Actualizando oxígeno en sangre…"
                try await self.wait(watch.refreshVitalsProbe(.oxygen, validatedOnly: true), running: { WatchVitalsProbe.shared.isRunning })
                try self.check(watch, watchID)
                // Solo candidato A, identificado y confirmado por el usuario.
                let oxygen = WatchVitalsProbe.shared.readings.filter { $0.channel == "A" }
                if !oxygen.isEmpty {
                    try store.mergeReadings(watchID: watchID, metric: .oxygen, readings: oxygen.map {
                        WatchHealthReading(id: "31/0C:\(Int64($0.timestamp.timeIntervalSince1970))", timestamp: $0.timestamp, value: Double($0.value))
                    })
                } else { self.issues.append("Oxígeno: no se recibieron muestras de la serie validada") }

                }
                self.progress = 0.6

                if groups.contains(.sleep) {
                try self.check(watch, watchID)
                self.schedule.mark(.sleep, watchID: watchID, at: Date())
                self.status = "Actualizando sesiones de sueño…"
                try await self.wait(watch.refreshSleepProbe(day: Date()), running: { WatchSleepProbe.shared.isRunning })
                try self.check(watch, watchID)
                let sleepProbe = WatchSleepProbe.shared
                let sessions = sleepProbe.sessions
                if !sessions.isEmpty {
                    try store.mergeSleep(watchID: watchID, sessions: sessions,
                                         retrievalComplete: sleepProbe.scanCompleted)
                    if !sleepProbe.scanCompleted {
                        self.issues.append("Sueño: lectura parcial · \(sessions.count) sesión(es). Verificá el total en el reloj.")
                    }
                } else {
                    self.issues.append(sleepProbe.scanCompleted ?
                        "Sueño: no se encontraron sesiones en el rango" :
                        "Sueño: consulta inconclusa, no se recibieron sesiones")
                }

                }
                self.progress = 1
                self.status = self.issues.isEmpty ? "Actualizado y guardado en este iPhone"
                    : "Actualización parcial: se guardaron los datos recibidos"
            } catch is CancellationError {
                WatchHealthSync.shared.cancel(); WatchStressProbe.shared.cancel()
                WatchVitalsProbe.shared.cancel(); WatchSleepProbe.shared.cancel()
                self.status = "Actualización en pausa; se conservan los datos guardados"
            } catch SyncError.connectionChanged {
                self.status = "La conexión cambió. Los datos ya guardados se conservan."
            } catch {
                self.status = store.storageError ?? "No se pudo completar la actualización. Revisá el diagnóstico."
            }
        }
    }
    private func check(_ watch: WatchBLEManager, _ id: String) throws {
        try Task.checkCancellation()
        guard watch.isConnected, watch.healthWatchID == id else { throw SyncError.connectionChanged }
    }
    private func wait(_ launch: Task<Bool, Never>?, running: () -> Bool) async throws {
        guard let launch = launch else { throw SyncError.didNotStart }
        guard await launch.value else { throw SyncError.didNotStart }
        while running() {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        try Task.checkCancellation()
    }
}
