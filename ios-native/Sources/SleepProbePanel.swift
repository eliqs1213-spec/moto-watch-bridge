import SwiftUI
import UIKit

struct SleepProbePanel: View {
    @EnvironmentObject private var watch: WatchBLEManager
    @StateObject private var sleep = WatchSleepProbe.shared
    @StateObject private var health = WatchHealthSync.shared
    @StateObject private var stress = WatchStressProbe.shared
    @StateObject private var vitals = WatchVitalsProbe.shared
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
                Text("Este panel consulta sin guardar. Actualizar en Salud consulta y guarda las sesiones. Si la suma no coincide con el reloj, copiá el diagnóstico 31/08 y 31/09.")
                    .font(.caption).foregroundStyle(.secondary)
                    .font(.caption).foregroundStyle(.secondary)
                Button("Copiar diagnóstico de sueño") { UIPasteboard.general.string = sleep.report }
                    .buttonStyle(.bordered)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var busy: Bool { !watch.isConnected || sleep.isRunning || health.isRunning || stress.isRunning || vitals.isRunning }
    private func duration(_ minutes: Double) -> String {
        let rounded = Int(minutes.rounded())
        return "\(rounded / 60) h \(rounded % 60) min"
    }
}

