import SwiftUI
import UIKit

struct VitalsProbePanel: View {
    @EnvironmentObject private var watch: WatchBLEManager
    @StateObject private var probe = WatchVitalsProbe.shared
    @StateObject private var health = WatchHealthSync.shared
    @StateObject private var stress = WatchStressProbe.shared
    var body: some View {
        GroupBox("Oxígeno y calorías · validar lecturas") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Compará los candidatos con el reloj. No se guardan en el histórico ni se consideran categorías confirmadas.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Consultar candidatos de oxígeno") { watch.refreshVitalsProbe(.oxygen) }
                    .buttonStyle(.borderedProminent).disabled(busy)
                Button("Consultar candidatos de calorías del día") { watch.refreshVitalsProbe(.calories) }
                    .buttonStyle(.bordered).disabled(busy)
                Text(probe.status).font(.caption).foregroundStyle(.secondary)
                if probe.mode == .oxygen {
                    ForEach(Array(probe.readings.suffix(20).reversed())) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Candidato \(row.channel) · valor \(row.value)").bold()
                            Text(row.timestamp.formatted(date: .abbreviated, time: .standard))
                        }.font(.caption)
                    }
                }
                if probe.mode == .calories {
                    if let time = probe.counterTime {
                        Text(time.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    }
                    ForEach(probe.counters) { counter in
                        Text("\(counter.label): \(counter.value.formatted())").font(.subheadline.bold())
                    }
                    Text("Compará estos valores crudos con las kcal totales del día que muestra el reloj. La unidad y el tipo de cada contador siguen pendientes de validar. No se calculan calorías desde los pasos.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Copiar diagnóstico de candidatos") { UIPasteboard.general.string = probe.report }
                    .buttonStyle(.bordered)
                Text("El diagnóstico contiene estados y tamaños; no copia mediciones ni identificadores del reloj. Consultar otra categoría reemplaza las lecturas temporales de este panel.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var busy: Bool { !watch.isConnected || probe.isRunning || health.isRunning || stress.isRunning }
}

