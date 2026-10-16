import SwiftUI
import UIKit

struct SleepProbePanel: View {
    @EnvironmentObject private var watch: WatchBLEManager
    @StateObject private var sleep = WatchSleepProbe.shared
    @StateObject private var health = WatchHealthSync.shared
    @StateObject private var stress = WatchStressProbe.shared
    @StateObject private var vitals = WatchVitalsProbe.shared
    @StateObject private var store = WatchHealthStore.shared
    @State private var saveStatus = ""
    @State private var date = Date()
    @AppStorage("motowatch.sleep.goal.hours") private var goalHours = 8.0
    var body: some View {
        GroupBox("Sueño · sesiones del día") {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("Día de despertar", selection: $date, in: ...Date(), displayedComponents: .date)
                    .disabled(sleep.isRunning)
                Button(sleep.isRunning ? "Consultando…" : "Consultar sueño del reloj") {
                    watch.refreshSleepProbe(day: date)
                }.buttonStyle(.borderedProminent).disabled(busy)
                Text(sleep.status).font(.caption).foregroundStyle(.secondary)
                if !saveStatus.isEmpty {
                    Label(saveStatus, systemImage: saveStatus.hasPrefix("Guardado")
                          ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(saveStatus.hasPrefix("Guardado") ? Color.green : Color.orange)
                }
                if !sleep.isRunning, !sleep.daySessions.isEmpty, !sleep.scanCompleted {
                    Label("Total parcial: la consulta todavía no recuperó todas las sesiones verificables.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Stepper("Objetivo: \(goalHours.formatted(.number.precision(.fractionLength(0...1)))) h", value: $goalHours, in: 1...16, step: 0.5)
                    .font(.subheadline)
                if !sleep.daySessions.isEmpty {
                    Text("\(duration(sleep.totalMinutes)) de sueño").font(.title2.bold())
                    Text("\(sleep.daySessions.count) sesiones · \(sleep.requestedDay.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: min(sleep.totalMinutes / 60, max(goalHours, 1)), total: max(goalHours, 1))
                        .tint(.indigo)
                    Text("\(Int((sleep.totalMinutes / (max(goalHours, 1) * 60) * 100).rounded()))% del objetivo")
                        .font(.caption)
                    ForEach(sleep.daySessions) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(duration(session.minutes)).bold()
                            Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) → \(session.endedAt.formatted(date: .abbreviated, time: .shortened))")
                        }.font(.caption)
                    }
                }
                Text("Se suman las sesiones que terminaron en el día consultado. La duración informada por el reloj puede ser menor que el tiempo entre inicio y fin. Las etapas todavía están pendientes de identificar.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Al finalizar correctamente, la consulta guarda las sesiones en Salud y actualiza el gráfico. Si la suma no coincide con el reloj, copiá el diagnóstico 31/08 y 31/09.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Copiar diagnóstico de sueño") { UIPasteboard.general.string = sleep.report }
                    .buttonStyle(.bordered)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: sleep.isRunning) { isRunning in
            if isRunning {
                saveStatus = ""
            } else {
                persistCompletedProbe()
            }
        }
    }

    private func persistCompletedProbe() {
        guard sleep.scanCompleted, !sleep.daySessions.isEmpty else {
            if !sleep.sessions.isEmpty {
                saveStatus = "Consulta parcial: no se guardó como total completo."
            }
            return
        }
        guard let id = watch.healthWatchID, watch.isConnected else {
            saveStatus = "No se pudo guardar: el reloj se desconectó."
            return
        }
        do {
            // 31/09 puede pasar de 179 a 248 min para la misma noche;
            // mergeSleep reconcilia el total sin duplicar la sesión vieja.
            try store.mergeSleep(watchID: id, sessions: sleep.daySessions,
                                 retrievalComplete: true)
            if let stored = store.day(sleep.requestedDay, watchID: id),
               let minutes = stored.sleepMinutes {
                let rounded = Int(minutes.rounded())
                saveStatus = "Guardado en Salud: \(rounded / 60) h \(rounded % 60) min. El histórico ya puede actualizarse."
            } else {
                saveStatus = "Consulta finalizada, pero no se pudo verificar el histórico guardado."
            }
        } catch WatchHealthStore.StoreError.overlappingSleep {
            saveStatus = "No se guardó: hay sesiones superpuestas que necesitan revisión."
        } catch {
            saveStatus = "No se pudo guardar el sueño. Revisá el diagnóstico."
        }
    }

    private var busy: Bool { !watch.isConnected || sleep.isRunning || health.isRunning || stress.isRunning || vitals.isRunning }
    private func duration(_ minutes: Double) -> String {
        let rounded = Int(minutes.rounded())
        return "\(rounded / 60) h \(rounded % 60) min"
    }
}

