import SwiftUI
import UIKit

struct HealthSyncPanel: View {
    @EnvironmentObject private var watch: WatchBLEManager
    @StateObject private var sync = WatchHealthSync.shared
    @StateObject private var stress = WatchStressProbe.shared
    @StateObject private var vitals = WatchVitalsProbe.shared
    var body: some View {
        GroupBox("Pasos y ritmo cardíaco · prueba experimental") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Consultá el reloj y compará las lecturas. La interpretación del protocolo todavía está en prueba.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button(sync.isRunning ? "Consultando…" : "Consultar Moto Watch") {
                    watch.refreshHealth()
                }.buttonStyle(.borderedProminent).disabled(!watch.isConnected || sync.isRunning || stress.isRunning || vitals.isRunning)
                Text(sync.status).font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pasos: " + sync.stepsDetail)
                    Text("Ritmo cardíaco: " + sync.heartRateDetail)
                }.font(.caption)
                Button("Copiar diagnóstico de salud") {
                    UIPasteboard.general.string = sync.diagnosticReport
                }.buttonStyle(.bordered)
                Text("El diagnóstico incluye estados de la consulta; no copia mediciones ni identificadores del reloj.")
                    .font(.caption2).foregroundStyle(.secondary)
                if let steps = sync.steps {
                    Label("Posibles pasos: \(steps.count.formatted())", systemImage: "figure.walk")
                    Text("Medición: \(steps.timestamp.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let latest = sync.pulse.last {
                    Label("Posible ritmo cardíaco: \(latest.bpm) lpm", systemImage: "heart.fill")
                    Text("\(sync.pulse.count) muestras · Última: \(latest.timestamp.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if sync.canSave || sync.saved {
                    Text("Guardar incorpora estas lecturas al histórico con una etiqueta experimental. Compará los pasos con el reloj y las mediciones de ritmo cardíaco por su hora; no son necesariamente valores en vivo.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(sync.saved ? "Guardado" : "Guardar histórico experimental") {
                        sync.saveExperimentalHistory()
                    }.buttonStyle(.bordered).disabled(!sync.canSave)
                }
                Text("Consulta de pasos disponibles y hasta 24 horas de ritmo cardíaco; no garantiza que el reloj entregue todo el período.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

