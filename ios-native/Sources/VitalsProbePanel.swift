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
                Text("Oxígeno sigue en validación. El contador de calorías activas ya fue comparado con el reloj. Estas lecturas no se guardan en el histórico.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Consultar candidatos de oxígeno") { watch.refreshVitalsProbe(.oxygen) }
                    .buttonStyle(.borderedProminent).disabled(busy)
                Button("Consultar calorías activas del día") { watch.refreshVitalsProbe(.calories) }
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
                        Text("\(counter.label): \(counter.value.formatted())\(counter.unitSuffix)").font(.subheadline.bold())
                    }
                    Text("Calorías activas corresponde al contador validado con el reloj. El contador B sigue sin identificar. Estas lecturas todavía no se guardan en el histórico.")
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

